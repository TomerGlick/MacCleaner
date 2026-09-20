import Foundation
import os.log

/// How a reported size was obtained. Recursive enumeration is accurate but slow;
/// `statfs` is instant but only valid for a mount point; `toolReported` comes from
/// a developer tool's own listing command.
public enum SizeMeasurement: String, Equatable, Hashable, Sendable {
    case enumerated
    case statfs
    case toolReported
    /// Enumeration hit its deadline — the size is a lower bound.
    case partial
}

/// Result of measuring a directory.
///
/// `needsFullDiskAccess` is deliberately distinct from a zero size: a TCC-protected
/// path silently yields `EPERM` per entry, and reporting "0 B" for it is worse than
/// reporting that permission is missing.
public struct DirectorySize: Equatable, Hashable, Sendable {
    public let bytes: Int64
    public let measurement: SizeMeasurement
    public let needsFullDiskAccess: Bool

    public init(bytes: Int64, measurement: SizeMeasurement, needsFullDiskAccess: Bool = false) {
        self.bytes = bytes
        self.measurement = measurement
        self.needsFullDiskAccess = needsFullDiskAccess
    }

    public static let zero = DirectorySize(bytes: 0, measurement: .enumerated)

    /// True when the reported number understates what is actually on disk.
    public var isUnderstated: Bool {
        measurement == .partial || needsFullDiskAccess
    }
}

/// Measures on-disk usage of directories.
///
/// Two things this does that a naive `du`-style walk does not:
///
/// 1. Reports **allocated** size (`.totalFileAllocatedSizeKey`), not logical size. APFS
///    clones and sparse files — simulator disk images above all — make logical sizes
///    overstate reclaimable space by a wide margin.
/// 2. Detects mount points and answers from `statfs` instead of walking them. Recursive
///    sizing of `/Library/Developer/CoreSimulator/Volumes/*` takes minutes; `statfs`
///    returns in under a millisecond.
public struct DirectorySizer {
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "sizer")

    /// Wall-clock budget for a single recursive measurement. Exceeding it returns a
    /// `.partial` size rather than blocking the scan.
    public let budget: TimeInterval

    public init(fileManager: FileManager = .default, budget: TimeInterval = 20) {
        self.fileManager = fileManager
        self.budget = budget
    }

    // MARK: - Public API

    /// Measure a directory, picking the cheapest strategy that is correct for it.
    public func size(of url: URL) -> DirectorySize {
        if isMountPoint(url), let used = mountUsedBytes(at: url) {
            return DirectorySize(bytes: used, measurement: .statfs)
        }
        return allocatedSize(of: url)
    }

    /// Recursively sum allocated size. Hidden files are included — `~/.gradle`,
    /// `.build` and dotfiles inside caches are exactly what we are trying to measure.
    public func allocatedSize(of url: URL) -> DirectorySize {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .zero
        }

        if !isDirectory.boolValue {
            return DirectorySize(bytes: allocatedSize(ofFile: url), measurement: .enumerated)
        }

        // A directory we cannot even list is a permissions problem, not an empty directory.
        if !fileManager.isReadableFile(atPath: url.path) {
            return DirectorySize(bytes: 0, measurement: .enumerated, needsFullDiskAccess: true)
        }

        var total: Int64 = 0
        var permissionDenied = false
        var timedOut = false
        let deadline = Date().addingTimeInterval(budget)

        // `options: []` — no `.skipsHiddenFiles`. Symlinked directories are not traversed
        // by NSDirectoryEnumerator, so a symlink loop cannot hang this.
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(Self.sizeKeys),
            options: [],
            errorHandler: { _, error in
                if Self.isPermissionError(error) {
                    permissionDenied = true
                }
                return true  // keep going; one unreadable subtree is not a failed scan
            }
        ) else {
            return DirectorySize(bytes: 0, measurement: .enumerated, needsFullDiskAccess: true)
        }

        var checked = 0
        while let entry = enumerator.nextObject() as? URL {
            checked += 1
            if checked & 0x3FF == 0, Date() > deadline {
                timedOut = true
                break
            }

            guard let values = try? entry.resourceValues(forKeys: Self.sizeKeys) else { continue }

            // Do not descend into a nested mount point: its contents belong to another
            // volume and would be double-counted against this directory.
            if values.isDirectory == true, values.isVolume == true {
                enumerator.skipDescendants()
                continue
            }

            if let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize {
                total += Int64(allocated)
            }
        }

        if timedOut {
            logger.debug("Sizing budget exceeded for \(url.path, privacy: .public) after \(checked, privacy: .public) entries")
        }

        return DirectorySize(
            bytes: total,
            measurement: timedOut ? .partial : .enumerated,
            needsFullDiskAccess: permissionDenied
        )
    }

    /// Allocated size of a single file, including resource forks.
    public func allocatedSize(ofFile url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Self.sizeKeys),
              let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize else {
            return 0
        }
        return Int64(allocated)
    }

    // MARK: - Mount points

    /// True when `url` is the root of its own mounted volume.
    public func isMountPoint(_ url: URL) -> Bool {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return false }

        let mountPoint = withUnsafePointer(to: &info.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }

        return URL(fileURLWithPath: mountPoint).standardizedFileURL.path
            == url.standardizedFileURL.path
    }

    /// Used bytes on the volume mounted at `url`, straight from `statfs`.
    public func mountUsedBytes(at url: URL) -> Int64? {
        var info = statfs()
        guard statfs(url.path, &info) == 0 else { return nil }

        let blockSize = Int64(info.f_bsize)
        let usedBlocks = Int64(info.f_blocks) - Int64(info.f_bfree)
        guard usedBlocks > 0 else { return 0 }
        return usedBlocks * blockSize
    }

    // MARK: - Private

    private static let sizeKeys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .isDirectoryKey,
        .isVolumeKey
    ]

    private static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileReadNoPermissionError
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EPERM) || nsError.code == Int(EACCES)
        }
        return false
    }
}
