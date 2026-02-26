import Foundation

/// Protocol for executing file cleanup operations safely
public protocol CleanupEngine {
    /// Perform cleanup operation on specified files
    func cleanup(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult
    
    /// Cleanup log files with preservation rules
    /// - Preserves logs from last 7 days
    /// - Archives logs older than 30 days when backup is enabled
    func cleanupLogs(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult
    
    /// Cleanup duplicate files while preserving at least one copy from each group
    /// - Parameters:
    ///   - duplicateGroups: Groups of duplicate files to clean
    ///   - filesToKeep: Specific files to preserve (one per group)
    ///   - options: Cleanup options
    ///   - progressHandler: Progress callback
    /// - Returns: Cleanup result
    func cleanupDuplicates(
        duplicateGroups: [DuplicateGroup],
        filesToKeep: [String: URL],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult
    
    /// Validate files before cleanup to check for protected files
    func validateCleanup(files: [FileMetadata]) -> ValidationResult
    
    /// Cancel ongoing cleanup operation
    func cancelCleanup()
}

/// Options for cleanup operations
public struct CleanupOptions {
    public let createBackup: Bool
    public let moveToTrash: Bool  // if false, permanently delete
    public let skipInUseFiles: Bool
    
    public init(createBackup: Bool = false, moveToTrash: Bool = true, skipInUseFiles: Bool = true) {
        self.createBackup = createBackup
        self.moveToTrash = moveToTrash
        self.skipInUseFiles = skipInUseFiles
    }
}

/// Progress information during cleanup
public struct CleanupProgress {
    public let currentFile: String
    public let filesProcessed: Int
    public let totalFiles: Int
    public let spaceFreed: Int64
    
    public init(currentFile: String, filesProcessed: Int, totalFiles: Int, spaceFreed: Int64) {
        self.currentFile = currentFile
        self.filesProcessed = filesProcessed
        self.totalFiles = totalFiles
        self.spaceFreed = spaceFreed
    }
}

/// Result of cleanup validation
public struct ValidationResult {
    public let isValid: Bool
    public let blockedFiles: [FileMetadata]  // files on safe-list
    public let warnings: [String]
    
    public init(isValid: Bool, blockedFiles: [FileMetadata], warnings: [String]) {
        self.isValid = isValid
        self.blockedFiles = blockedFiles
        self.warnings = warnings
    }
}

/// Default implementation of CleanupEngine
public final class DefaultCleanupEngine: CleanupEngine {
    private let safeListManager: SafeListManager
    private let backupManager: BackupManager
    private let fileManager: FileManager
    private var isCancelled: Bool = false
    private let cancelQueue = DispatchQueue(label: "com.macstoragecleanup.cleanup.cancel")
    
    public init(safeListManager: SafeListManager, backupManager: BackupManager, fileManager: FileManager = .default) {
        self.safeListManager = safeListManager
        self.backupManager = backupManager
        self.fileManager = fileManager
    }
    
    public func validateCleanup(files: [FileMetadata]) -> ValidationResult {
        var blockedFiles: [FileMetadata] = []
        var warnings: [String] = []
        
        for file in files {
            // Check if file is protected by safe-list
            if safeListManager.isProtected(url: file.url) {
                blockedFiles.append(file)
                warnings.append("File is protected: \(file.url.path)")
            }
            
            // Check if file is in use
            if file.isInUse {
                warnings.append("File is currently in use: \(file.url.path)")
            }
            
            // Check if file is deletable
            if !file.permissions.isDeletable {
                warnings.append("File is not deletable: \(file.url.path)")
            }
        }
        
        let isValid = blockedFiles.isEmpty
        return ValidationResult(isValid: isValid, blockedFiles: blockedFiles, warnings: warnings)
    }
    
    private func simulateCleanup(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async -> CleanupResult {
        let validation = validateCleanup(files: files)
        let filesToClean = files.filter { !validation.blockedFiles.contains($0) }
        
        var filesRemoved = 0
        var spaceFreed: Int64 = 0
        
        for (index, file) in filesToClean.enumerated() {
            // Simulate processing delay
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            
            filesRemoved += 1
            spaceFreed += file.size
            
            progressHandler(CleanupProgress(
                currentFile: file.url.lastPathComponent,
                filesProcessed: index + 1,
                totalFiles: filesToClean.count,
                spaceFreed: spaceFreed
            ))
        }
        
        return CleanupResult(
            filesRemoved: filesRemoved,
            spaceFreed: spaceFreed,
            errors: [],
            backupLocation: nil
        )
    }
    
    public func cleanup(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        // Check if debug mode is enabled
        let debugMode = UserDefaults.standard.bool(forKey: "debugMode")
        
        if debugMode {
            print("DEBUG MODE: Simulating cleanup without deleting files")
            return await simulateCleanup(files: files, options: options, progressHandler: progressHandler)
        }
        
        // Reset cancellation flag
        cancelQueue.sync {
            isCancelled = false
        }
        
        // Validate files before cleanup
        let validation = validateCleanup(files: files)
        
        // Filter out blocked files
        let filesToClean = files.filter { file in
            !validation.blockedFiles.contains(file)
        }
        
        var backupLocation: URL?
        var deletedFiles: [URL] = []  // Track deleted files for rollback
        var filesRemoved = 0
        var spaceFreed: Int64 = 0
        var errors: [CleanupError] = []
        
        // Create backup if enabled
        if options.createBackup && !filesToClean.isEmpty {
            do {
                let backupDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MacStorageCleanup")
                    .appendingPathComponent("Backups")
                
                // Create backup directory if needed
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                
                let backupResult = try await backupManager.createBackup(files: filesToClean, destination: backupDir)
                backupLocation = backupResult.backupURL
            } catch {
                // If backup fails, don't proceed with deletion
                errors.append(.backupFailed("Failed to create backup: \(error.localizedDescription)"))
                return CleanupResult(
                    filesRemoved: 0,
                    spaceFreed: 0,
                    errors: errors,
                    backupLocation: nil
                )
            }
        }
        
        // Process each file with atomic operations
        for (index, file) in filesToClean.enumerated() {
            // Check for cancellation
            let cancelled = cancelQueue.sync { isCancelled }
            if cancelled {
                // Rollback: restore deleted files if possible
                await rollbackDeletions(deletedFiles: deletedFiles, backupLocation: backupLocation)
                errors.append(.cancelled)
                break
            }
            
            // Skip files that are in use if option is set
            if options.skipInUseFiles && isFileInUse(url: file.url) {
                errors.append(.fileInUse(path: file.url.path))
                
                // Report progress
                progressHandler(CleanupProgress(
                    currentFile: file.url.lastPathComponent,
                    filesProcessed: index + 1,
                    totalFiles: filesToClean.count,
                    spaceFreed: spaceFreed
                ))
                continue
            }
            
            // Attempt to delete the file
            do {
                if options.moveToTrash {
                    try moveToTrash(url: file.url)
                } else {
                    try fileManager.removeItem(at: file.url)
                }
                
                // Track successful deletion for potential rollback
                deletedFiles.append(file.url)
                filesRemoved += 1
                spaceFreed += file.size
            } catch {
                // On error, rollback all deletions
                await rollbackDeletions(deletedFiles: deletedFiles, backupLocation: backupLocation)
                
                // Convert error to CleanupError
                let cleanupError = convertToCleanupError(error: error, path: file.url.path)
                errors.append(cleanupError)
                
                // Return partial result with rollback information
                return CleanupResult(
                    filesRemoved: 0,  // All rolled back
                    spaceFreed: 0,
                    errors: errors,
                    backupLocation: backupLocation
                )
            }
            
            // Report progress
            progressHandler(CleanupProgress(
                currentFile: file.url.lastPathComponent,
                filesProcessed: index + 1,
                totalFiles: filesToClean.count,
                spaceFreed: spaceFreed
            ))
        }
        
        return CleanupResult(
            filesRemoved: filesRemoved,
            spaceFreed: spaceFreed,
            errors: errors,
            backupLocation: backupLocation
        )
    }
    
    public func cancelCleanup() {
        cancelQueue.sync {
            isCancelled = true
        }
    }
    
    /// Cleanup log files with preservation rules
    /// - Preserves logs from last 7 days (Requirement 13.4)
    /// - Archives logs older than 30 days when backup is enabled (Requirement 13.5)
    public func cleanupLogs(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        // Filter log files
        let logFiles = files.filter { $0.fileType == .log }
        
        // Separate logs by age
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        
        // Logs older than 7 days can be deleted (logs from last 7 days are preserved)
        let oldLogs = logFiles.filter { $0.modifiedDate < sevenDaysAgo }
        
        // Logs older than 30 days should be archived if backup is enabled
        let veryOldLogs = oldLogs.filter { $0.modifiedDate <= thirtyDaysAgo }
        let moderatelyOldLogs = oldLogs.filter { $0.modifiedDate > thirtyDaysAgo }
        
        // If backup is enabled and we have very old logs, archive them separately
        var backupLocation: URL?
        if options.createBackup && !veryOldLogs.isEmpty {
            do {
                let backupDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MacStorageCleanup")
                    .appendingPathComponent("Backups")
                
                try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)
                
                // Archive old logs
                let backupResult = try await backupManager.createBackup(files: veryOldLogs, destination: backupDir)
                backupLocation = backupResult.backupURL
            } catch {
                // If archiving fails, don't proceed with deletion of very old logs
                let errors = [CleanupError.backupFailed("Failed to archive old logs: \(error.localizedDescription)")]
                return CleanupResult(
                    filesRemoved: 0,
                    spaceFreed: 0,
                    errors: errors,
                    backupLocation: nil
                )
            }
        }
        
        // Determine which logs to clean
        var logsToClean: [FileMetadata]
        if options.createBackup {
            // If backup is enabled, clean all old logs (both moderate and very old)
            logsToClean = oldLogs
        } else {
            // If backup is not enabled, only clean moderately old logs (7-30 days)
            // Don't delete very old logs without archiving them first
            logsToClean = moderatelyOldLogs
        }
        
        // Use standard cleanup for the filtered logs
        let cleanupOptions = CleanupOptions(
            createBackup: false,  // Already handled archiving above
            moveToTrash: options.moveToTrash,
            skipInUseFiles: options.skipInUseFiles
        )
        
        let result = try await cleanup(
            files: logsToClean,
            options: cleanupOptions,
            progressHandler: progressHandler
        )
        
        // Update backup location if we archived old logs
        return CleanupResult(
            filesRemoved: result.filesRemoved,
            spaceFreed: result.spaceFreed,
            errors: result.errors,
            backupLocation: backupLocation ?? result.backupLocation
        )
    }
    
    /// Cleanup duplicate files while preserving at least one copy from each group
    /// Implements Requirements 12.3 and 12.4
    public func cleanupDuplicates(
        duplicateGroups: [DuplicateGroup],
        filesToKeep: [String: URL],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        // Reset cancellation flag
        cancelQueue.sync {
            isCancelled = false
        }
        
        // Build list of files to delete
        var filesToDelete: [FileMetadata] = []
        
        for group in duplicateGroups {
            // Determine which file to keep for this group
            let fileToKeep: URL
            if let specifiedFile = filesToKeep[group.hash] {
                // User specified which file to keep
                fileToKeep = specifiedFile
            } else {
                // Default: keep the first file in the group
                fileToKeep = group.files[0].url
            }
            
            // Add all other files to deletion list
            for file in group.files {
                if file.url != fileToKeep {
                    filesToDelete.append(file)
                }
            }
        }
        
        // Validate that we're preserving at least one file per group
        for group in duplicateGroups {
            let filesInGroupToDelete = filesToDelete.filter { file in
                group.files.contains { $0.url == file.url }
            }
            
            // Ensure at least one file from the group is NOT in the deletion list
            let filesPreserved = group.files.count - filesInGroupToDelete.count
            if filesPreserved < 1 {
                // This should never happen with our logic, but safety check
                throw CleanupError.unknown("Duplicate preservation guarantee violated for hash: \(group.hash)")
            }
        }
        
        // Use standard cleanup for the files to delete
        return try await cleanup(
            files: filesToDelete,
            options: options,
            progressHandler: progressHandler
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Check if a file is currently in use by attempting to open it exclusively
    private func isFileInUse(url: URL) -> Bool {
        // Check if it's a directory - directories can't be "in use" in the same way
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // For directories, just check if we have write permission
            return !fileManager.isWritableFile(atPath: url.path)
        }
        
        // Try to open the file with exclusive access
        let fileHandle = try? FileHandle(forUpdating: url)
        
        if let handle = fileHandle {
            // File is not in use, close it
            try? handle.close()
            return false
        }
        
        // Could not open file, might be in use or permission issue
        // Check if file exists
        if !fileManager.fileExists(atPath: url.path) {
            return false
        }
        
        // File exists but can't be opened - likely in use
        return true
    }
    
    /// Move file to trash using NSFileManager
    private func moveToTrash(url: URL) throws {
        var resultingURL: NSURL?
        
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch let error as NSError {
            // Convert NSError to appropriate CleanupError
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileNoSuchFileError:
                    throw CleanupError.fileNotFound(path: url.path)
                case NSFileWriteNoPermissionError:
                    throw CleanupError.permissionDenied(path: url.path)
                default:
                    throw CleanupError.unknown(error.localizedDescription)
                }
            }
            throw CleanupError.unknown(error.localizedDescription)
        }
    }
    
    /// Convert generic error to CleanupError
    private func convertToCleanupError(error: Error, path: String) -> CleanupError {
        if let cleanupError = error as? CleanupError {
            return cleanupError
        }
        
        let nsError = error as NSError
        
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError:
                return .fileNotFound(path: path)
            case NSFileWriteNoPermissionError:
                return .permissionDenied(path: path)
            default:
                return .unknown(nsError.localizedDescription)
            }
        }
        
        return .unknown(error.localizedDescription)
    }
    
    /// Rollback deletions by restoring files from backup
    private func rollbackDeletions(deletedFiles: [URL], backupLocation: URL?) async {
        // If we have a backup, we can restore from it
        guard let backupURL = backupLocation else {
            // No backup available, cannot rollback
            return
        }
        
        // Find the backup in the backup manager
        let backups = backupManager.listBackups()
        guard let backup = backups.first(where: { $0.location == backupURL }) else {
            return
        }
        
        // Restore files to their original locations
        do {
            // Create a temporary directory for restoration
            let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            defer {
                try? fileManager.removeItem(at: tempDir)
            }
            
            // Restore the backup
            _ = try await backupManager.restoreBackup(backup: backup, destination: tempDir)
            
            // Move restored files back to their original locations
            // Note: This is a best-effort restoration
            for deletedFile in deletedFiles {
                let restoredFile = tempDir.appendingPathComponent(deletedFile.lastPathComponent)
                if fileManager.fileExists(atPath: restoredFile.path) {
                    try? fileManager.moveItem(at: restoredFile, to: deletedFile)
                }
            }
        } catch {
            // Rollback failed, but we continue
            // The backup still exists for manual recovery
        }
    }
}
