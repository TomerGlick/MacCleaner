import Foundation

/// Result of a file system scan operation
public struct ScanResult: Equatable {
    public let files: [FileMetadata]
    public let errors: [ScanError]
    public let duration: TimeInterval
    
    public init(files: [FileMetadata], errors: [ScanError] = [], duration: TimeInterval = 0) {
        self.files = files
        self.errors = errors
        self.duration = duration
    }
}

/// Progress information during scanning
public struct ScanProgress: Equatable {
    public let currentPath: String
    public let filesScanned: Int
    public let percentComplete: Double
    
    public init(currentPath: String, filesScanned: Int, percentComplete: Double) {
        self.currentPath = currentPath
        self.filesScanned = filesScanned
        self.percentComplete = percentComplete
    }
}
