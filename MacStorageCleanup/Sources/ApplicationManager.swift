import Foundation
import AppKit

/// Protocol for managing application discovery and uninstallation
public protocol ApplicationManager {
    func discoverApplications() async -> [Application]
    func findAssociatedFiles(for application: Application) async -> [FileMetadata]
    func uninstall(application: Application, removeAssociatedFiles: Bool) async throws -> UninstallResult
}

/// Default implementation of ApplicationManager
public class DefaultApplicationManager: ApplicationManager {
    private let fileManager = FileManager.default
    
    public init() {
        // Default initializer
    }
    
    /// Discovers all installed applications in /Applications and ~/Applications
    /// - Returns: Array of discovered applications with metadata
    public func discoverApplications() async -> [Application] {
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        
        var applications: [Application] = []
        
        for searchPath in searchPaths {
            guard fileManager.fileExists(atPath: searchPath.path) else {
                continue
            }
            
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: searchPath,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                
                for url in contents where url.pathExtension == "app" {
                    if let app = await createApplication(from: url) {
                        applications.append(app)
                    }
                }
            } catch {
                // Continue scanning other directories if one fails
                continue
            }
        }
        
        return applications
    }
    
    /// Finds all associated files for an application
    /// - Parameter application: The application to find associated files for
    /// - Returns: Array of file metadata for associated files
    public func findAssociatedFiles(for application: Application) async -> [FileMetadata] {
        var associatedFiles: [FileMetadata] = []
        let homeDir = fileManager.homeDirectoryForCurrentUser
        
        // Search locations for associated files
        let searchLocations: [(path: String, pattern: String)] = [
            // Preferences
            ("Library/Preferences", "\(application.bundleIdentifier).plist"),
            // Caches
            ("Library/Caches", application.bundleIdentifier),
            // Application Support
            ("Library/Application Support", application.name),
            // Logs
            ("Library/Logs", application.name)
        ]
        
        for (subPath, pattern) in searchLocations {
            let searchURL = homeDir.appendingPathComponent(subPath).appendingPathComponent(pattern)
            
            if fileManager.fileExists(atPath: searchURL.path) {
                // If it's a directory, enumerate its contents
                if let isDirectory = try? searchURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                   isDirectory {
                    if let files = await enumerateDirectory(searchURL) {
                        associatedFiles.append(contentsOf: files)
                    }
                } else {
                    // It's a file
                    if let metadata = createFileMetadata(from: searchURL) {
                        associatedFiles.append(metadata)
                    }
                }
            }
        }
        
        return associatedFiles
    }
    
    /// Uninstalls an application and optionally its associated files
    /// - Parameters:
    ///   - application: The application to uninstall
    ///   - removeAssociatedFiles: Whether to remove associated files
    /// - Returns: Result of the uninstallation operation
    public func uninstall(application: Application, removeAssociatedFiles: Bool) async throws -> UninstallResult {
        var errors: [UninstallError] = []
        var totalSpaceFreed: Int64 = 0
        var associatedFilesRemoved = 0
        var applicationRemoved = false
        
        // Check if application is running
        if application.isRunning {
            throw UninstallError.applicationRunning(name: application.name)
        }
        
        // Remove associated files first if requested
        if removeAssociatedFiles {
            let associatedFiles = await findAssociatedFiles(for: application)
            
            for file in associatedFiles {
                do {
                    try fileManager.removeItem(at: file.url)
                    totalSpaceFreed += file.size
                    associatedFilesRemoved += 1
                } catch {
                    errors.append(.unknown("Failed to remove \(file.url.path): \(error.localizedDescription)"))
                }
            }
        }
        
        // Remove the application bundle
        do {
            if !fileManager.fileExists(atPath: application.bundleURL.path) {
                throw UninstallError.applicationNotFound(path: application.bundleURL.path)
            }
            
            try fileManager.removeItem(at: application.bundleURL)
            totalSpaceFreed += application.size
            applicationRemoved = true
        } catch let error as UninstallError {
            throw error
        } catch {
            if (error as NSError).code == NSFileWriteNoPermissionError {
                throw UninstallError.permissionDenied
            }
            throw UninstallError.unknown("Failed to remove application: \(error.localizedDescription)")
        }
        
        return UninstallResult(
            applicationRemoved: applicationRemoved,
            associatedFilesRemoved: associatedFilesRemoved,
            totalSpaceFreed: totalSpaceFreed,
            errors: errors
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Creates an Application instance from a .app bundle URL
    private func createApplication(from bundleURL: URL) async -> Application? {
        guard let bundle = Bundle(url: bundleURL) else {
            return nil
        }
        
        // Get application metadata from bundle
        let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundleURL.deletingPathExtension().lastPathComponent
        
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "Unknown"
        
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle.id"
        
        // Calculate bundle size
        let size = calculateDirectorySize(bundleURL)
        
        // Get last used date from launch services
        let lastUsedDate = getLastUsedDate(for: bundleURL)
        
        // Check if application is running
        let isRunning = isApplicationRunning(bundleIdentifier: bundleIdentifier)
        
        return Application(
            bundleURL: bundleURL,
            name: name,
            version: version,
            bundleIdentifier: bundleIdentifier,
            size: size,
            lastUsedDate: lastUsedDate,
            isRunning: isRunning
        )
    }
    
    /// Calculates the total size of a directory
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDirectory = resourceValues.isDirectory,
                  !isDirectory,
                  let fileSize = resourceValues.fileSize else {
                continue
            }
            
            totalSize += Int64(fileSize)
        }
        
        return totalSize
    }
    
    /// Gets the last used date for an application from launch services
    private func getLastUsedDate(for bundleURL: URL) -> Date? {
        // Try to get last used date from extended attributes
        let xattrName = "com.apple.lastuseddate#PS"
        let path = bundleURL.path
        
        let bufferSize = getxattr(path, xattrName, nil, 0, 0, 0)
        guard bufferSize > 0 else {
            return nil
        }
        
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let result = getxattr(path, xattrName, &buffer, bufferSize, 0, 0)
        
        guard result > 0 else {
            return nil
        }
        
        // Parse the binary plist data
        let data = Data(buffer)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let timestamp = plist["_kMDItemLastUsedDate"] as? TimeInterval else {
            return nil
        }
        
        return Date(timeIntervalSinceReferenceDate: timestamp)
    }
    
    /// Checks if an application is currently running
    private func isApplicationRunning(bundleIdentifier: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    /// Enumerates all files in a directory
    private func enumerateDirectory(_ url: URL) async -> [FileMetadata]? {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey],
            options: []
        ) else {
            return nil
        }
        
        var files: [FileMetadata] = []
        
        for case let fileURL as URL in enumerator {
            if let metadata = createFileMetadata(from: fileURL) {
                files.append(metadata)
            }
        }
        
        return files
    }
    
    /// Creates FileMetadata from a file URL
    private func createFileMetadata(from url: URL) -> FileMetadata? {
        guard let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .contentAccessDateKey,
            .isDirectoryKey
        ]) else {
            return nil
        }
        
        // Skip directories
        if let isDirectory = resourceValues.isDirectory, isDirectory {
            return nil
        }
        
        let size = Int64(resourceValues.fileSize ?? 0)
        let createdDate = resourceValues.creationDate ?? Date()
        let modifiedDate = resourceValues.contentModificationDate ?? Date()
        let accessedDate = resourceValues.contentAccessDate ?? Date()
        
        // Determine file type based on extension
        let fileType: FileType
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cache":
            fileType = .cache
        case "log":
            fileType = .log
        case "tmp", "temp":
            fileType = .temporary
        case "plist":
            fileType = .other("plist")
        default:
            fileType = .other(ext)
        }
        
        return FileMetadata(
            url: url,
            size: size,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            accessedDate: accessedDate,
            fileType: fileType,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
}
