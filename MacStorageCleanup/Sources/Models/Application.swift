import Foundation

/// Represents an installed macOS application
public struct Application: Equatable, Hashable {
    public let bundleURL: URL
    public let name: String
    public let version: String
    public let bundleIdentifier: String
    public let size: Int64
    public let lastUsedDate: Date?
    public let isRunning: Bool
    
    public init(
        bundleURL: URL,
        name: String,
        version: String,
        bundleIdentifier: String,
        size: Int64,
        lastUsedDate: Date? = nil,
        isRunning: Bool = false
    ) {
        self.bundleURL = bundleURL
        self.name = name
        self.version = version
        self.bundleIdentifier = bundleIdentifier
        self.size = size
        self.lastUsedDate = lastUsedDate
        self.isRunning = isRunning
    }
}

/// Result of an application uninstallation operation
public struct UninstallResult: Equatable {
    public let applicationRemoved: Bool
    public let associatedFilesRemoved: Int
    public let totalSpaceFreed: Int64
    public let errors: [UninstallError]
    
    public init(applicationRemoved: Bool, associatedFilesRemoved: Int, totalSpaceFreed: Int64, errors: [UninstallError]) {
        self.applicationRemoved = applicationRemoved
        self.associatedFilesRemoved = associatedFilesRemoved
        self.totalSpaceFreed = totalSpaceFreed
        self.errors = errors
    }
    
    public static func == (lhs: UninstallResult, rhs: UninstallResult) -> Bool {
        return lhs.applicationRemoved == rhs.applicationRemoved &&
               lhs.associatedFilesRemoved == rhs.associatedFilesRemoved &&
               lhs.totalSpaceFreed == rhs.totalSpaceFreed &&
               lhs.errors == rhs.errors
    }
}
