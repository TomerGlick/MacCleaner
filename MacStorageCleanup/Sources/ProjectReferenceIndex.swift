import Foundation
import os.log

/// The kind of toolchain version a project file pins.
public enum ProjectReferenceKind: String, CaseIterable, Sendable {
    case gradleDistribution
    case androidNDK
    case androidBuildTools
    case javaToolchain
}

/// An index of toolchain versions pinned by the user's own projects.
///
/// Multi-version caches cannot be pruned by modification date: a project can pin an
/// old NDK or an old Gradle wrapper and never touch it for a year. Before offering a
/// version for deletion we ask this index whether anything references it. Versions with
/// references are kept and the referencing files are shown — that is the reassurance
/// that makes a user comfortable clicking delete on the rest.
public struct ProjectReferenceIndex: Sendable {
    private var storage: [ProjectReferenceKind: [String: Set<URL>]]

    public init(storage: [ProjectReferenceKind: [String: Set<URL>]] = [:]) {
        self.storage = storage
    }

    /// Project files pinning `version` for `kind`. Empty means nothing references it.
    public func references(kind: ProjectReferenceKind, version: String) -> [URL] {
        guard let versions = storage[kind] else { return [] }

        // Exact match first, then prefix match so `27.0.12077973` also satisfies a
        // `ndkVersion "27.0"` style declaration.
        if let exact = versions[version] {
            return exact.sorted { $0.path < $1.path }
        }
        var matches: Set<URL> = []
        for (declared, urls) in versions where version.hasPrefix(declared) || declared.hasPrefix(version) {
            matches.formUnion(urls)
        }
        return matches.sorted { $0.path < $1.path }
    }

    public var isEmpty: Bool {
        storage.values.allSatisfy { $0.isEmpty }
    }

    public var totalReferenceCount: Int {
        storage.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } }
    }

    // MARK: - Building

    /// Default places to look for the user's source tree.
    public static func defaultRoots(homeDir: String = NSHomeDirectory()) -> [URL] {
        ["Develop", "Developer", "Projects", "Documents", "src", "Code", "code", "repos", "work", "git"]
            .map { URL(fileURLWithPath: homeDir).appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Directory names never worth descending into when hunting for project metadata.
    /// These are build output, not source, and they dominate the entry count.
    static let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", "build", "DerivedData", "Pods",
        ".build", ".gradle", ".idea", "Carthage", "vendor", ".venv", "venv",
        "__pycache__", ".next", "target", "out", ".dart_tool", ".kotlin"
    ]

    /// Walk `roots` and index every toolchain version pinned by a project file.
    public static func build(
        roots: [URL] = ProjectReferenceIndex.defaultRoots(),
        maxDepth: Int = 5,
        budget: TimeInterval = 20,
        fileManager: FileManager = .default
    ) -> ProjectReferenceIndex {
        let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "references")
        var storage: [ProjectReferenceKind: [String: Set<URL>]] = [:]
        let deadline = Date().addingTimeInterval(budget)

        func record(_ kind: ProjectReferenceKind, _ version: String, _ url: URL) {
            let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            storage[kind, default: [:]][trimmed, default: []].insert(url)
        }

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let entry = enumerator.nextObject() as? URL {
                if Date() > deadline {
                    logger.debug("Reference indexing budget exceeded under \(root.path, privacy: .public)")
                    break
                }

                let name = entry.lastPathComponent
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

                if isDirectory {
                    // `.github` is shallow and holds CI files worth reading, so it is not
                    // skipped despite being hidden.
                    if skippedDirectoryNames.contains(name) || enumerator.level > maxDepth {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                for (kind, version) in parse(file: entry, named: name) {
                    record(kind, version, entry)
                }
            }
        }

        let index = ProjectReferenceIndex(storage: storage)
        logger.debug("Indexed \(index.totalReferenceCount, privacy: .public) toolchain references across \(roots.count, privacy: .public) roots")
        return index
    }

    // MARK: - Parsing

    private static let maxFileBytes = 1_000_000

    /// Extract every toolchain pin from one file. Returns nothing for files we don't parse.
    static func parse(file url: URL, named name: String) -> [(ProjectReferenceKind, String)] {
        let isInterestingName =
            name == "gradle-wrapper.properties" ||
            name == "build.gradle" || name == "build.gradle.kts" ||
            name == "local.properties" || name == "gradle.properties" ||
            name == ".env" ||
            name.hasSuffix(".yml") || name.hasSuffix(".yaml")

        guard isInterestingName else { return [] }

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64, size <= maxFileBytes,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var found: [(ProjectReferenceKind, String)] = []

        if name == "gradle-wrapper.properties" {
            // distributionUrl=https\://services.gradle.org/distributions/gradle-9.7.1-bin.zip
            for version in matches(of: #"gradle-([0-9]+(?:\.[0-9]+)*)-(?:bin|all)"#, in: contents) {
                found.append((.gradleDistribution, version))
            }
            return found
        }

        for version in matches(of: #"ndkVersion\s*(?:=|\s)\s*["']([^"']+)["']"#, in: contents) {
            found.append((.androidNDK, version))
        }
        for version in matches(of: #"buildToolsVersion\s*(?:=|\s)\s*["']([^"']+)["']"#, in: contents) {
            found.append((.androidBuildTools, version))
        }
        // ndk.dir / ANDROID_NDK_HOME point at a directory; its last component is the version.
        for path in matches(of: #"(?:ndk\.dir|ANDROID_NDK_HOME)\s*[:=]\s*["']?([^"'\n\r]+)"#, in: contents) {
            found.append((.androidNDK, (path as NSString).lastPathComponent))
        }
        for version in matches(of: #"ANDROID_NDK_VERSION\s*[:=]\s*["']?([^"'\s]+)"#, in: contents) {
            found.append((.androidNDK, version))
        }
        for version in matches(of: #"languageVersion\s*(?:=|\.set\()\s*JavaLanguageVersion\.of\(([0-9]+)\)"#, in: contents) {
            found.append((.javaToolchain, version))
        }

        return found
    }

    /// First capture group of every match, in order.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }
}
