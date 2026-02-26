import Foundation

/// Represents a backup archive
public struct Backup: Equatable, Codable {
    public let id: UUID
    public let createdDate: Date
    public let fileCount: Int
    public let originalSize: Int64
    public let compressedSize: Int64
    public let location: URL
    
    public init(
        id: UUID = UUID(),
        createdDate: Date,
        fileCount: Int,
        originalSize: Int64,
        compressedSize: Int64,
        location: URL
    ) {
        self.id = id
        self.createdDate = createdDate
        self.fileCount = fileCount
        self.originalSize = originalSize
        self.compressedSize = compressedSize
        self.location = location
    }
}

/// Result of a backup operation
public struct BackupResult: Equatable {
    public let backupURL: URL
    public let filesBackedUp: Int
    public let compressedSize: Int64
    public let duration: TimeInterval
    
    public init(backupURL: URL, filesBackedUp: Int, compressedSize: Int64, duration: TimeInterval) {
        self.backupURL = backupURL
        self.filesBackedUp = filesBackedUp
        self.compressedSize = compressedSize
        self.duration = duration
    }
}

/// Result of a restore operation
public struct RestoreResult: Equatable {
    public let filesRestored: Int
    public let totalSize: Int64
    public let duration: TimeInterval
    public let errors: [RestoreError]
    
    public init(filesRestored: Int, totalSize: Int64 = 0, duration: TimeInterval = 0, errors: [RestoreError] = []) {
        self.filesRestored = filesRestored
        self.totalSize = totalSize
        self.duration = duration
        self.errors = errors
    }
}

/// Manifest entry for a backed up file
struct BackupManifestEntry: Codable {
    let originalPath: String
    let size: Int64
    let modifiedDate: Date
    let fileType: String
    let checksum: String  // SHA-256 hash for integrity verification
}

/// Manifest for a backup archive
struct BackupManifest: Codable {
    let backupId: UUID
    let createdDate: Date
    let entries: [BackupManifestEntry]
}
