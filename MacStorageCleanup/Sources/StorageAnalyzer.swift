import Foundation
import CryptoKit

/// Protocol for analyzing scanned files and categorizing them for cleanup
public protocol StorageAnalyzer {
    /// Analyze scan results and categorize files
    /// - Parameter scanResult: The result from a file scan operation
    /// - Returns: Analysis result with categorized files and duplicate detection
    func analyze(scanResult: ScanResult) -> AnalysisResult
    
    /// Categorize a file into cleanup categories
    /// - Parameter file: The file metadata to categorize
    /// - Returns: Set of cleanup categories the file belongs to
    func categorize(file: FileMetadata) -> Set<CleanupCategory>
    
    /// Calculate total size for a collection of files
    /// - Parameter files: Array of file metadata
    /// - Returns: Total size in bytes
    func calculateSavings(files: [FileMetadata]) -> Int64
    
    /// Filter files by age threshold
    /// - Parameters:
    ///   - files: Array of file metadata to filter
    ///   - thresholdDays: Minimum age in days (files older than this are included). Will be clamped to [30, 1095] days.
    /// - Returns: Filtered array of files
    func filterByAge(files: [FileMetadata], thresholdDays: Int) -> [FileMetadata]
    
    /// Clamp age threshold to valid range [30, 1095] days
    /// - Parameter thresholdDays: The threshold value to clamp
    /// - Returns: Clamped threshold value
    func clampAgeThreshold(_ thresholdDays: Int) -> Int
    
    /// Filter files by size threshold
    /// - Parameters:
    ///   - files: Array of file metadata to filter
    ///   - thresholdBytes: Minimum size in bytes (files >= this size are included)
    /// - Returns: Filtered array of files
    func filterBySize(files: [FileMetadata], thresholdBytes: Int64) -> [FileMetadata]
    
    /// Filter files by file type
    /// - Parameters:
    ///   - files: Array of file metadata to filter
    ///   - fileType: The file type to filter for
    /// - Returns: Filtered array of files
    func filterByType(files: [FileMetadata], fileType: FileType) -> [FileMetadata]
    
    /// Sort files by size in descending order
    /// - Parameter files: Array of file metadata to sort
    /// - Returns: Sorted array of files (largest first)
    func sortBySize(files: [FileMetadata]) -> [FileMetadata]
    
    /// Apply multiple filters to a collection of files
    /// - Parameters:
    ///   - files: Array of file metadata to filter
    ///   - filters: Array of filter functions to apply
    /// - Returns: Filtered array of files that satisfy all filters
    func applyFilters(files: [FileMetadata], filters: [(FileMetadata) -> Bool]) -> [FileMetadata]
    
    /// Categorize log files by application and age
    /// - Parameter files: Array of file metadata (should be log files)
    /// - Returns: Dictionary mapping application names to their log files
    func categorizeLogsByApplication(files: [FileMetadata]) -> [String: [LogFileInfo]]
    
    /// Get log file information with application and age details
    /// - Parameter files: Array of file metadata (should be log files)
    /// - Returns: Array of LogFileInfo with categorization details
    func getLogFileInfo(files: [FileMetadata]) -> [LogFileInfo]
    
    /// Categorize Downloads files by type (documents, images, archives, installers)
    /// - Parameter files: Array of file metadata (should be from Downloads folder)
    /// - Returns: Dictionary mapping DownloadsFileType to their files
    func categorizeDownloadsByType(files: [FileMetadata]) -> [DownloadsFileType: [DownloadsFileInfo]]
    
    /// Get Downloads file information with type and age details
    /// - Parameter files: Array of file metadata (should be from Downloads folder)
    /// - Returns: Array of DownloadsFileInfo with categorization details
    func getDownloadsFileInfo(files: [FileMetadata]) -> [DownloadsFileInfo]
    
    /// Filter Downloads files that are cleanup candidates (older than 90 days)
    /// - Parameter files: Array of file metadata (should be from Downloads folder)
    /// - Returns: Array of files older than 90 days
    func filterOldDownloads(files: [FileMetadata]) -> [FileMetadata]
}

/// Default implementation of StorageAnalyzer
public final class DefaultStorageAnalyzer: StorageAnalyzer {
    private let fileManager = FileManager.default
    private let duplicateThreshold: Int64 = 1024 * 1024 // 1MB
    private let safeListManager: SafeListManager
    
    public init(safeListManager: SafeListManager = DefaultSafeListManager()) {
        self.safeListManager = safeListManager
    }
    
    public func analyze(scanResult: ScanResult) -> AnalysisResult {
        var categorizedFiles: [CleanupCategory: [FileMetadata]] = [:]
        
        // Initialize all categories with empty arrays
        for category in CleanupCategory.allCases {
            categorizedFiles[category] = []
        }
        
        // Categorize each file
        for file in scanResult.files {
            let categories = categorize(file: file)
            for category in categories {
                categorizedFiles[category, default: []].append(file)
            }
        }
        
        // Calculate total size
        let totalSize = calculateSavings(files: scanResult.files)
        
        // Detect duplicates (only for files > 1MB)
        let duplicateGroups = detectDuplicates(files: scanResult.files)
        
        // Calculate potential savings (sum of all categorized files)
        let potentialSavings = totalSize
        
        return AnalysisResult(
            categorizedFiles: categorizedFiles,
            totalSize: totalSize,
            potentialSavings: potentialSavings,
            duplicateGroups: duplicateGroups
        )
    }
    
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
        // Exclude system files and application bundles from old files
        let oldFileThreshold: TimeInterval = 365 * 24 * 60 * 60 // 365 days in seconds
        let fileAge = Date().timeIntervalSince(file.accessedDate)
        if fileAge >= oldFileThreshold {
            // Check if file is a system file or application bundle
            let isSystemFile = safeListManager.isProtected(url: file.url)
            let isApplicationBundle = ext == "app" || pathLower.contains(".app/")
            
            // Only categorize as old file if it's not protected
            if !isSystemFile && !isApplicationBundle {
                categories.insert(.oldFiles)
            }
        }
        
        return categories
    }
    
    public func calculateSavings(files: [FileMetadata]) -> Int64 {
        return files.reduce(0) { $0 + $1.size }
    }
    
    public func filterByAge(files: [FileMetadata], thresholdDays: Int) -> [FileMetadata] {
        // Clamp threshold to valid range [30, 1095] days
        let clampedThreshold = clampAgeThreshold(thresholdDays)
        let thresholdSeconds = TimeInterval(clampedThreshold) * 24 * 60 * 60
        let currentDate = Date()
        
        return files.filter { file in
            let fileAge = currentDate.timeIntervalSince(file.accessedDate)
            return fileAge > thresholdSeconds
        }
    }
    
    public func clampAgeThreshold(_ thresholdDays: Int) -> Int {
        // Clamp to range [30, 1095] days as per requirement 5.4
        let minThreshold = 30
        let maxThreshold = 1095
        
        if thresholdDays < minThreshold {
            return minThreshold
        } else if thresholdDays > maxThreshold {
            return maxThreshold
        } else {
            return thresholdDays
        }
    }
    
    public func filterBySize(files: [FileMetadata], thresholdBytes: Int64) -> [FileMetadata] {
        return files.filter { file in
            file.size >= thresholdBytes
        }
    }
    
    public func filterByType(files: [FileMetadata], fileType: FileType) -> [FileMetadata] {
        return files.filter { file in
            switch (file.fileType, fileType) {
            case (.cache, .cache),
                 (.log, .log),
                 (.temporary, .temporary),
                 (.document, .document),
                 (.application, .application),
                 (.archive, .archive),
                 (.media, .media):
                return true
            case (.other(let ext1), .other(let ext2)):
                return ext1 == ext2
            default:
                return false
            }
        }
    }
    
    public func sortBySize(files: [FileMetadata]) -> [FileMetadata] {
        return files.sorted { $0.size > $1.size }
    }
    
    public func applyFilters(files: [FileMetadata], filters: [(FileMetadata) -> Bool]) -> [FileMetadata] {
        return files.filter { file in
            filters.allSatisfy { filter in
                filter(file)
            }
        }
    }
    
    public func categorizeLogsByApplication(files: [FileMetadata]) -> [String: [LogFileInfo]] {
        var logsByApp: [String: [LogFileInfo]] = [:]
        
        // Convert files to LogFileInfo and group by application
        for file in files {
            let logInfo = LogFileInfo.from(fileMetadata: file)
            logsByApp[logInfo.application, default: []].append(logInfo)
        }
        
        return logsByApp
    }
    
    public func getLogFileInfo(files: [FileMetadata]) -> [LogFileInfo] {
        return files.map { LogFileInfo.from(fileMetadata: $0) }
    }
    
    public func categorizeDownloadsByType(files: [FileMetadata]) -> [DownloadsFileType: [DownloadsFileInfo]] {
        var downloadsByType: [DownloadsFileType: [DownloadsFileInfo]] = [:]
        
        // Convert files to DownloadsFileInfo and group by type
        for file in files {
            let downloadInfo = DownloadsFileInfo.from(fileMetadata: file)
            downloadsByType[downloadInfo.downloadsType, default: []].append(downloadInfo)
        }
        
        return downloadsByType
    }
    
    public func getDownloadsFileInfo(files: [FileMetadata]) -> [DownloadsFileInfo] {
        return files.map { DownloadsFileInfo.from(fileMetadata: $0) }
    }
    
    public func filterOldDownloads(files: [FileMetadata]) -> [FileMetadata] {
        let ninetyDaysInSeconds: TimeInterval = 90 * 24 * 60 * 60
        let currentDate = Date()
        
        return files.filter { file in
            let fileAge = currentDate.timeIntervalSince(file.accessedDate)
            return fileAge > ninetyDaysInSeconds
        }
    }
    
    // MARK: - Private Methods
    
    /// Detect duplicate files using SHA-256 hashing
    /// Only processes files larger than 1MB for performance
    private func detectDuplicates(files: [FileMetadata]) -> [DuplicateGroup] {
        // Filter files larger than threshold
        let eligibleFiles = files.filter { $0.size >= duplicateThreshold }
        
        // Group files by hash
        var hashToFiles: [String: [FileMetadata]] = [:]
        
        for file in eligibleFiles {
            // Compute hash for file
            if let hash = computeFileHash(url: file.url) {
                hashToFiles[hash, default: []].append(file)
            }
        }
        
        // Create duplicate groups (only for groups with 2+ files)
        var duplicateGroups: [DuplicateGroup] = []
        
        for (hash, groupFiles) in hashToFiles {
            if groupFiles.count > 1 {
                // All files in the group have the same size (same content)
                let fileSize = groupFiles[0].size
                let totalSize = fileSize * Int64(groupFiles.count)
                let wastedSpace = fileSize * Int64(groupFiles.count - 1)
                
                let group = DuplicateGroup(
                    hash: hash,
                    files: groupFiles,
                    totalSize: totalSize,
                    wastedSpace: wastedSpace
                )
                duplicateGroups.append(group)
            }
        }
        
        return duplicateGroups
    }
    
    /// Compute SHA-256 hash for a file
    private func computeFileHash(url: URL) -> String? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        
        defer {
            try? fileHandle.close()
        }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1MB buffer
        
        while autoreleasepool(invoking: {
            guard let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
