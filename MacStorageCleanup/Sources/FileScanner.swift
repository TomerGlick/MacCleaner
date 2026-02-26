import Foundation

/// Protocol for scanning the file system and collecting file metadata
public protocol FileScanner {
    /// Scan specified paths for files matching the given categories
    /// - Parameters:
    ///   - paths: Array of URLs to scan
    ///   - categories: Set of cleanup categories to filter for
    ///   - progressHandler: Closure called periodically with scan progress
    /// - Returns: ScanResult containing found files and any errors
    func scan(
        paths: [URL],
        categories: Set<CleanupCategory>,
        progressHandler: @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult
    
    /// Cancel the current scan operation
    func cancelScan()
    
    /// Categorize a file into cleanup categories
    /// - Parameter file: The file metadata to categorize
    /// - Returns: Set of cleanup categories the file belongs to
    func categorize(file: FileMetadata) -> Set<CleanupCategory>
}

/// Default implementation of FileScanner with directory traversal
public final class DefaultFileScanner: FileScanner {
    private let fileManager = FileManager.default
    private let safeListManager: SafeListManager
    private let batchSize = 1000
    
    private var isCancelled = false
    private let cancelQueue = DispatchQueue(label: "com.macstoragecleanup.filescanner.cancel")
    
    public init(safeListManager: SafeListManager = DefaultSafeListManager()) {
        self.safeListManager = safeListManager
    }
    
    public func scan(
        paths: [URL],
        categories: Set<CleanupCategory>,
        progressHandler: @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult {
        // Reset cancellation flag
        cancelQueue.sync {
            isCancelled = false
        }
        
        let startTime = Date()
        var allFiles: [FileMetadata] = []
        var allErrors: [ScanError] = []
        var filesScanned = 0
        
        // Estimate total files for progress calculation (rough estimate)
        let totalPaths = paths.count
        var currentPathIndex = 0
        
        for path in paths {
            // Check for cancellation
            if checkCancelled() {
                throw ScanError.cancelled
            }
            
            // Scan this path
            let (files, errors) = await scanPath(
                path,
                categories: categories,
                filesScanned: &filesScanned,
                currentPathIndex: currentPathIndex,
                totalPaths: totalPaths,
                progressHandler: progressHandler
            )
            
            allFiles.append(contentsOf: files)
            allErrors.append(contentsOf: errors)
            
            currentPathIndex += 1
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        return ScanResult(
            files: allFiles,
            errors: allErrors,
            duration: duration
        )
    }
    
    public func cancelScan() {
        cancelQueue.sync {
            isCancelled = true
        }
    }
    
    // MARK: - Private Methods
    
    private func checkCancelled() -> Bool {
        return cancelQueue.sync { isCancelled }
    }
    
    private func scanPath(
        _ path: URL,
        categories: Set<CleanupCategory>,
        filesScanned: inout Int,
        currentPathIndex: Int,
        totalPaths: Int,
        progressHandler: @escaping (ScanProgress) -> Void
    ) async -> ([FileMetadata], [ScanError]) {
        var files: [FileMetadata] = []
        var errors: [ScanError] = []
        var batch: [FileMetadata] = []
        
        // Check if path is protected
        if safeListManager.isProtected(url: path) {
            return ([], [])
        }
        
        // Check if path exists
        guard fileManager.fileExists(atPath: path.path) else {
            errors.append(.pathNotFound(path: path.path))
            return ([], errors)
        }
        
        // Create enumerator for recursive traversal
        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey,
                .isDirectoryKey
            ],
            options: [],
            errorHandler: { url, error in
                // Handle permission errors gracefully
                if (error as NSError).code == NSFileReadNoPermissionError {
                    errors.append(.permissionDenied(path: url.path))
                    return true // Continue enumeration
                }
                return true
            }
        ) else {
            errors.append(.permissionDenied(path: path.path))
            return ([], errors)
        }
        
        for case let fileURL as URL in enumerator {
            // Check for cancellation
            if checkCancelled() {
                break
            }
            
            // Skip if protected
            if safeListManager.isProtected(url: fileURL) {
                enumerator.skipDescendants()
                continue
            }
            
            // Get resource values
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .contentAccessDateKey
            ]) else {
                continue
            }
            
            // Skip directories
            if resourceValues.isDirectory == true {
                continue
            }
            
            // Extract metadata
            guard let size = resourceValues.fileSize,
                  let createdDate = resourceValues.creationDate,
                  let modifiedDate = resourceValues.contentModificationDate else {
                continue
            }
            
            let accessedDate = resourceValues.contentAccessDate ?? modifiedDate
            
            // Check file permissions
            let isReadable = fileManager.isReadableFile(atPath: fileURL.path)
            let isWritable = fileManager.isWritableFile(atPath: fileURL.path)
            let isDeletable = fileManager.isDeletableFile(atPath: fileURL.path)
            
            // Determine file type
            let fileType = determineFileType(url: fileURL)
            
            // Create file metadata
            let metadata = FileMetadata(
                url: fileURL,
                size: Int64(size),
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                accessedDate: accessedDate,
                fileType: fileType,
                isInUse: false, // Will be checked later if needed
                permissions: FilePermissions(
                    isReadable: isReadable,
                    isWritable: isWritable,
                    isDeletable: isDeletable
                )
            )
            
            // Add to batch
            batch.append(metadata)
            filesScanned += 1
            
            // Process batch when it reaches the batch size
            if batch.count >= batchSize {
                files.append(contentsOf: batch)
                batch.removeAll(keepingCapacity: true)
                
                // Report progress
                let percentComplete = Double(currentPathIndex) / Double(totalPaths)
                let progress = ScanProgress(
                    currentPath: fileURL.path,
                    filesScanned: filesScanned,
                    percentComplete: percentComplete
                )
                progressHandler(progress)
            }
        }
        
        // Add remaining files from batch
        if !batch.isEmpty {
            files.append(contentsOf: batch)
        }
        
        // Final progress update for this path
        let percentComplete = Double(currentPathIndex + 1) / Double(totalPaths)
        let progress = ScanProgress(
            currentPath: path.path,
            filesScanned: filesScanned,
            percentComplete: percentComplete
        )
        progressHandler(progress)
        
        return (files, errors)
    }
    
    private func determineFileType(url: URL) -> FileType {
        let path = url.path
        let pathLower = path.lowercased()
        let ext = url.pathExtension.lowercased()
        
        // Check path-based types first
        if pathLower.contains("/caches/") || pathLower.contains("/cache/") {
            return .cache
        }
        
        if pathLower.contains("/logs/") || pathLower.contains("/log/") {
            return .log
        }
        
        if pathLower.contains("/tmp") || pathLower.contains("/temp") {
            return .temporary
        }
        
        // Check extension-based types
        if ["tmp", "temp", "cache"].contains(ext) {
            return .temporary
        }
        
        if ["log", "txt"].contains(ext) {
            return .log
        }
        
        if url.pathExtension == "app" {
            return .application
        }
        
        if ["zip", "tar", "gz", "bz2", "7z", "rar", "dmg", "pkg"].contains(ext) {
            return .archive
        }
        
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "mp4", "mov", "avi", "mkv", "mp3", "m4a", "wav", "aac"].contains(ext) {
            return .media
        }
        
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf"].contains(ext) {
            return .document
        }
        
        return .other(ext)
    }
    
    // MARK: - Public Categorization
    
    public func categorize(file: FileMetadata) -> Set<CleanupCategory> {
        var categories = Set<CleanupCategory>()
        
        let path = file.url.path
        let pathLower = path.lowercased()
        let ext = file.url.pathExtension.lowercased()
        
        // Path-based categorization for caches
        if pathLower.contains("/library/caches/") {
            // Determine if system or application cache
            if pathLower.contains("/system/library/caches/") {
                categories.insert(.systemCaches)
            } else if pathLower.contains("/library/caches/com.apple.safari") ||
                      pathLower.contains("/library/caches/google/chrome") ||
                      pathLower.contains("/library/caches/firefox") ||
                      pathLower.contains("/library/caches/microsoft edge") {
                categories.insert(.browserCaches)
            } else {
                categories.insert(.applicationCaches)
            }
        }
        
        // Path-based categorization for logs
        if pathLower.contains("/logs/") || pathLower.contains("/log/") ||
           pathLower.contains("/var/log/") {
            categories.insert(.logFiles)
        }
        
        // Path-based categorization for temporary files
        if pathLower.contains("/tmp") || pathLower.contains("/temp") ||
           pathLower.hasPrefix("/tmp/") || pathLower.hasPrefix("/var/tmp/") ||
           pathLower.contains("/application support/") && pathLower.contains("/tmp") {
            categories.insert(.temporaryFiles)
        }
        
        // Extension-based categorization for temporary files
        if ["tmp", "temp", "cache"].contains(ext) {
            categories.insert(.temporaryFiles)
        }
        
        // Path-based categorization for downloads
        if pathLower.contains("/downloads/") {
            categories.insert(.downloads)
        }
        
        // Size-based categorization for large files (>100MB)
        let largeFileThreshold: Int64 = 100 * 1024 * 1024 // 100MB in bytes
        if file.size >= largeFileThreshold {
            categories.insert(.largeFiles)
        }
        
        // Age-based categorization for old files (>365 days)
        let oldFileThreshold: TimeInterval = 365 * 24 * 60 * 60 // 365 days in seconds
        let fileAge = Date().timeIntervalSince(file.accessedDate)
        if fileAge >= oldFileThreshold {
            categories.insert(.oldFiles)
        }
        
        return categories
    }
}
