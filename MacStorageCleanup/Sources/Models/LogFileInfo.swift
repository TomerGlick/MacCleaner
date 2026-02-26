import Foundation

/// Represents detailed information about a log file
public struct LogFileInfo: Equatable, Hashable {
    /// The underlying file metadata
    public let fileMetadata: FileMetadata
    
    /// The application or service that created this log
    public let application: String
    
    /// Age of the log file in days
    public let ageDays: Int
    
    public init(fileMetadata: FileMetadata, application: String, ageDays: Int) {
        self.fileMetadata = fileMetadata
        self.application = application
        self.ageDays = ageDays
    }
    
    /// Convenience accessors
    public var url: URL { fileMetadata.url }
    public var size: Int64 { fileMetadata.size }
    public var modifiedDate: Date { fileMetadata.modifiedDate }
}

/// Extension to categorize log files by application and age
extension LogFileInfo {
    /// Extract application name from log file path
    /// - Parameter url: The URL of the log file
    /// - Returns: The application name or "System" if it's a system log
    static func extractApplicationName(from url: URL) -> String {
        let path = url.path
        let pathLower = path.lowercased()
        
        // System logs in /var/log
        if pathLower.hasPrefix("/var/log/") || pathLower.hasPrefix("/private/var/log/") {
            // Extract log name from /var/log/[name].log
            let components = url.lastPathComponent.components(separatedBy: ".")
            if let firstComponent = components.first, !firstComponent.isEmpty {
                return "System (\(firstComponent))"
            }
            return "System"
        }
        
        // User logs in ~/Library/Logs
        if pathLower.contains("/library/logs/") {
            // Extract application name from ~/Library/Logs/[AppName]/...
            let logsIndex = path.range(of: "/Library/Logs/", options: .caseInsensitive)
            if let logsIndex = logsIndex {
                let afterLogs = String(path[logsIndex.upperBound...])
                let components = afterLogs.components(separatedBy: "/")
                if let appName = components.first, !appName.isEmpty {
                    return appName
                }
            }
        }
        
        // Application-specific logs in ~/Library/Application Support/[AppName]/logs
        if pathLower.contains("/application support/") {
            let supportIndex = path.range(of: "/Application Support/", options: .caseInsensitive)
            if let supportIndex = supportIndex {
                let afterSupport = String(path[supportIndex.upperBound...])
                let components = afterSupport.components(separatedBy: "/")
                if let appName = components.first, !appName.isEmpty {
                    return appName
                }
            }
        }
        
        // Default to "Unknown"
        return "Unknown"
    }
    
    /// Calculate age in days from a date
    /// - Parameter date: The date to calculate age from
    /// - Returns: Age in days
    static func calculateAgeDays(from date: Date) -> Int {
        let ageSeconds = Date().timeIntervalSince(date)
        return Int(ageSeconds / (24 * 60 * 60))
    }
    
    /// Create LogFileInfo from FileMetadata
    /// - Parameter fileMetadata: The file metadata
    /// - Returns: LogFileInfo with extracted application and calculated age
    static func from(fileMetadata: FileMetadata) -> LogFileInfo {
        let application = extractApplicationName(from: fileMetadata.url)
        let ageDays = calculateAgeDays(from: fileMetadata.modifiedDate)
        
        return LogFileInfo(
            fileMetadata: fileMetadata,
            application: application,
            ageDays: ageDays
        )
    }
}
