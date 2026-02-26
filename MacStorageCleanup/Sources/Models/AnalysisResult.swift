import Foundation

/// Result of storage analysis
public struct AnalysisResult: Equatable {
    public let categorizedFiles: [CleanupCategory: [FileMetadata]]
    public let totalSize: Int64
    public let potentialSavings: Int64
    public let duplicateGroups: [DuplicateGroup]
    
    public init(
        categorizedFiles: [CleanupCategory: [FileMetadata]] = [:],
        totalSize: Int64 = 0,
        potentialSavings: Int64 = 0,
        duplicateGroups: [DuplicateGroup] = []
    ) {
        self.categorizedFiles = categorizedFiles
        self.totalSize = totalSize
        self.potentialSavings = potentialSavings
        self.duplicateGroups = duplicateGroups
    }
}

/// Group of duplicate files
public struct DuplicateGroup: Equatable, Hashable {
    public let hash: String
    public let files: [FileMetadata]
    public let totalSize: Int64
    public let wastedSpace: Int64  // size * (count - 1)
    
    public init(hash: String, files: [FileMetadata], totalSize: Int64, wastedSpace: Int64) {
        self.hash = hash
        self.files = files
        self.totalSize = totalSize
        self.wastedSpace = wastedSpace
    }
}
