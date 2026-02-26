import Foundation

/// Categories for file cleanup operations
public enum CleanupCategory: String, CaseIterable, Equatable, Hashable, Codable {
    case systemCaches
    case applicationCaches
    case browserCaches
    case temporaryFiles
    case largeFiles
    case oldFiles
    case logFiles
    case downloads
    case duplicates
}
