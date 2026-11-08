import AppKit
import Foundation
import os.log

/// Where a piece of leftover application data was found.
///
/// The kind is not decoration: it is what tells the user whether losing the folder costs
/// them a login (`container`), a window layout (`savedState`), or nothing at all (`caches`).
public enum OrphanedDataKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case preferences
    case caches
    case container
    case groupContainer
    case applicationSupport
    case savedState
    case httpStorage
    case webKit
    case logs
    case cookies

    public var displayName: String {
        switch self {
        case .preferences: return "Preferences"
        case .caches: return "Cache"
        case .container: return "Container"
        case .groupContainer: return "Group Container"
        case .applicationSupport: return "Application Support"
        case .savedState: return "Saved Window State"
        case .httpStorage: return "Website Storage"
        case .webKit: return "WebKit Data"
        case .logs: return "Logs"
        case .cookies: return "Cookies"
        }
    }

    /// What the user loses if they are wrong about the app being gone.
    ///
    /// Containers and Application Support hold the app's actual documents and licences, so
    /// they never claim to be scratch data. Caches and saved state do.
    public var carriesUserData: Bool {
        switch self {
        case .container, .groupContainer, .applicationSupport, .preferences:
            return true
        case .caches, .savedState, .httpStorage, .webKit, .logs, .cookies:
            return false
        }
    }
}

/// One directory or file left behind by an application that is no longer installed.
public struct OrphanedAppData: Equatable, Hashable, Sendable {
    /// The bundle identifier the path is named after — the evidence for the claim.
    public let bundleIdentifier: String
    /// Best-effort readable name, derived from the identifier when nothing better exists.
    public let displayName: String
    public let location: URL
    public let kind: OrphanedDataKind
    public let size: Int64
    public let lastModified: Date
    /// The size is understated because the path is TCC-protected.
    public let needsFullDiskAccess: Bool
    /// The size is a lower bound because measurement hit its time budget.
    public let isPartialSize: Bool

    public init(
        bundleIdentifier: String,
        displayName: String,
        location: URL,
        kind: OrphanedDataKind,
        size: Int64,
        lastModified: Date,
        needsFullDiskAccess: Bool = false,
        isPartialSize: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.location = location
        self.kind = kind
        self.size = size
        self.lastModified = lastModified
        self.needsFullDiskAccess = needsFullDiskAccess
        self.isPartialSize = isPartialSize
    }
}

/// Every bundle identifier this Mac can currently launch.
///
/// The index is the whole safety story of the orphan scan: anything it does not know
/// about gets proposed for deletion, so it errs towards knowing too much. It reads the
/// Spotlight application index (which finds apps on external volumes and in nested
/// folders, not just `/Applications`), then walks the usual directories anyway in case
/// Spotlight is disabled or still indexing.
public struct InstalledApplicationIndex: Sendable {
    /// Lower-cased identifiers. Case matters to the filesystem, never to the comparison.
    public let bundleIdentifiers: Set<String>

    public init(bundleIdentifiers: Set<String>) {
        self.bundleIdentifiers = Set(bundleIdentifiers.map { $0.lowercased() })
    }

    /// True when this identifier belongs to something still installed.
    ///
    /// Matching is deliberately generous in both directions. A helper writes its data under
    /// `com.foo.App.Helper` while only `com.foo.App` is installed, and a suite writes under
    /// `com.foo` while `com.foo.App` is what sits in `/Applications`. Treating either as
    /// live costs the user nothing; treating either as dead deletes a running app's data.
    public func claims(_ identifier: String) -> Bool {
        let candidate = identifier.lowercased()
        if bundleIdentifiers.contains(candidate) { return true }
        return bundleIdentifiers.contains { installed in
            candidate.hasPrefix(installed + ".") || installed.hasPrefix(candidate + ".")
        }
    }

    /// Reads the identifiers of every application currently on this Mac.
    public static func current(fileManager: FileManager = .default) -> InstalledApplicationIndex {
        var identifiers = Set<String>()

        for bundleURL in spotlightApplicationURLs() + directoryApplicationURLs(fileManager: fileManager) {
            if let identifier = bundleIdentifier(at: bundleURL) {
                identifiers.insert(identifier)
            }
        }

        // A process can be running from a path neither sweep reached (a disk image, a
        // build directory). Its data is emphatically not a leftover.
        for identifier in NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) {
            identifiers.insert(identifier)
        }

        return InstalledApplicationIndex(bundleIdentifiers: identifiers)
    }

    private static let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "orphanscan")

    /// Asks Spotlight for every application bundle it knows about, anywhere on the machine.
    private static func spotlightApplicationURLs() -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            logger.debug("mdfind unavailable: \(error.localizedDescription, privacy: .public)")
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) else {
            return []
        }

        return output
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
    }

    /// The directories an app is expected to live in, walked one level deep (plus the
    /// `Utilities`-style nesting Apple and several vendors use).
    private static func directoryApplicationURLs(fileManager: FileManager) -> [URL] {
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            "/System/Library/CoreServices/Applications",
            "/Library/Application Support",
            NSHomeDirectory() + "/Applications"
        ].map { URL(fileURLWithPath: $0) }

        var found: [URL] = []
        for root in roots {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                if entry.pathExtension == "app" {
                    found.append(entry)
                } else if root.lastPathComponent == "Application Support" {
                    // Vendors park updaters and agents one level down here.
                    let nested = (try? fileManager.contentsOfDirectory(
                        at: entry,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    found.append(contentsOf: nested.filter { $0.pathExtension == "app" })
                }
            }
        }
        return found
    }

    /// Reads `CFBundleIdentifier` without loading the bundle, which is faster and does not
    /// register the app with LaunchServices as a side effect.
    private static func bundleIdentifier(at bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String,
              !identifier.isEmpty else {
            return nil
        }
        return identifier
    }
}

/// Finds data belonging to applications that are no longer installed.
///
/// Uninstalling on macOS means dragging a bundle to the Trash, which leaves everything the
/// app ever wrote under `~/Library` behind forever. This scan finds that residue.
///
/// Three rules keep it from proposing a live app's data, in decreasing order of importance:
///
/// 1. **Only bundle-identifier-shaped names are considered.** `~/Library/Caches/com.acme.Widget`
///    names its owner and can be checked. `~/Library/Application Support/Adobe` does not, and
///    is never touched — no guessing from product names.
/// 2. **The installed index has to disown it**, including prefix relationships in both
///    directions, so helpers and suites stay with their parent app.
/// 3. **Recently written paths are skipped.** Something writing to a folder this month is
///    not a leftover, whatever the index says.
public struct OrphanedAppDataScanner {
    public typealias Kind = OrphanedDataKind

    let sizer: DirectorySizer
    let homeDir: String
    let installed: InstalledApplicationIndex
    let fileManager: FileManager
    private let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "orphanscan")

    public init(
        sizer: DirectorySizer,
        installed: InstalledApplicationIndex,
        homeDir: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) {
        self.sizer = sizer
        self.installed = installed
        self.homeDir = homeDir
        self.fileManager = fileManager
    }

    /// Where leftovers accumulate, and the filename shape each location uses.
    ///
    /// `Group Containers` is absent on purpose: a group identifier is shared by a family of
    /// apps and by system extensions, so no single bundle identifier owns it and the
    /// "is it installed" question has no honest answer.
    struct Location {
        let subPath: String
        /// Suffix to strip before the remainder is read as a bundle identifier.
        let suffix: String
        let kind: Kind
    }

    static let locations: [Location] = [
        Location(subPath: "Library/Preferences", suffix: ".plist", kind: .preferences),
        Location(subPath: "Library/Caches", suffix: "", kind: .caches),
        Location(subPath: "Library/Containers", suffix: "", kind: .container),
        Location(subPath: "Library/Application Support", suffix: "", kind: .applicationSupport),
        Location(subPath: "Library/Saved Application State", suffix: ".savedState", kind: .savedState),
        Location(subPath: "Library/HTTPStorages", suffix: "", kind: .httpStorage),
        Location(subPath: "Library/WebKit", suffix: "", kind: .webKit),
        Location(subPath: "Library/Logs", suffix: "", kind: .logs),
        Location(subPath: "Library/Cookies", suffix: ".binarycookies", kind: .cookies)
    ]

    /// Identifier prefixes that are never offered, whatever the index says.
    ///
    /// Apple's own identifiers appear under `~/Library` for frameworks and daemons that own
    /// no `.app` at all, so "no bundle found" means nothing for them. Our own identifiers
    /// are excluded so the app cannot propose deleting its own state.
    static let protectedPrefixes: [String] = [
        "com.apple.",
        "group.",
        "com.tomerglick.macstoragecleanup"
    ]

    /// How long a path must sit untouched before it counts as abandoned.
    public static let defaultMinimumAge: TimeInterval = 30 * 24 * 60 * 60

    /// Finds every leftover under the user's Library.
    /// - Parameters:
    ///   - minimumAge: how long a path must have gone unwritten to be considered abandoned.
    ///   - now: injected for tests.
    public func scan(
        minimumAge: TimeInterval = OrphanedAppDataScanner.defaultMinimumAge,
        now: Date = Date()
    ) -> [OrphanedAppData] {
        let start = Date()
        var results: [OrphanedAppData] = []

        for location in Self.locations {
            let root = URL(fileURLWithPath: homeDir).appendingPathComponent(location.subPath)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: []
            ) else { continue }

            for entry in entries {
                guard let identifier = Self.bundleIdentifier(from: entry.lastPathComponent, suffix: location.suffix) else {
                    continue
                }
                guard !Self.isProtected(identifier) else { continue }
                guard !installed.claims(identifier) else { continue }

                let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
                let modified = values?.contentModificationDate ?? Date.distantPast
                guard now.timeIntervalSince(modified) >= minimumAge else { continue }

                let isDirectory = values?.isDirectory ?? false
                let measured: DirectorySize
                if isDirectory {
                    measured = sizer.allocatedSize(of: entry)
                } else {
                    measured = DirectorySize(
                        bytes: sizer.allocatedSize(ofFile: entry),
                        measurement: .enumerated
                    )
                }

                results.append(OrphanedAppData(
                    bundleIdentifier: identifier,
                    displayName: Self.displayName(for: identifier),
                    location: entry,
                    kind: location.kind,
                    size: measured.bytes,
                    lastModified: modified,
                    needsFullDiskAccess: measured.needsFullDiskAccess,
                    isPartialSize: measured.measurement == .partial
                ))
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        logger.debug("orphan scan: \(results.count, privacy: .public) rows in \(String(format: "%.2f", elapsed), privacy: .public)s")

        return results.sorted { $0.size > $1.size }
    }

    // MARK: - Naming

    /// Reads a filename as a bundle identifier, or refuses.
    ///
    /// Three dotted components is the bar. It admits `com.acme.Widget` and rejects both
    /// plain product folders (`Adobe`) and two-part names that are far more often a
    /// versioned folder than an identifier (`Backups.backupdb`). Missing a real two-part
    /// identifier costs the user some unreclaimed bytes; misreading a folder costs them data.
    static func bundleIdentifier(from filename: String, suffix: String) -> String? {
        var name = filename
        if !suffix.isEmpty {
            guard name.hasSuffix(suffix) else { return nil }
            name.removeLast(suffix.count)
        }

        guard !name.hasPrefix(".") else { return nil }

        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3 else { return nil }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        for component in components {
            guard !component.isEmpty else { return nil }
            guard component.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        }

        return name
    }

    static func isProtected(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        return Self.protectedPrefixes.contains { lowered.hasPrefix($0) }
    }

    /// Turns `com.acme.MenuWidget` into "MenuWidget". The identifier is shown beside it in
    /// the UI, so this only has to be readable, not authoritative.
    static func displayName(for identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        return last.isEmpty ? identifier : last
    }
}
