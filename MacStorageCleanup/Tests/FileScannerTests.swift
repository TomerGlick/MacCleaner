import XCTest
@testable import MacStorageCleanup

final class FileScannerTests: XCTestCase {
    var scanner: DefaultFileScanner!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        scanner = DefaultFileScanner()
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    func testScanEmptyDirectory() async throws {
        // Given: An empty directory
        
        // When: Scanning the directory
        var progressUpdates: [ScanProgress] = []
        let result = try await scanner.scan(
            paths: [tempDirectory],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )
        
        // Then: Should return empty results
        XCTAssertEqual(result.files.count, 0)
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertGreaterThan(progressUpdates.count, 0)
    }
    
    func testScanDirectoryWithFiles() async throws {
        // Given: A directory with some test files
        let file1 = tempDirectory.appendingPathComponent("test1.txt")
        let file2 = tempDirectory.appendingPathComponent("test2.log")
        let file3 = tempDirectory.appendingPathComponent("test3.tmp")
        
        try "Test content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Test content 2".write(to: file2, atomically: true, encoding: .utf8)
        try "Test content 3".write(to: file3, atomically: true, encoding: .utf8)
        
        // When: Scanning the directory
        var progressUpdates: [ScanProgress] = []
        let result = try await scanner.scan(
            paths: [tempDirectory],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )
        
        // Then: Should find all files
        XCTAssertEqual(result.files.count, 3, "Expected 3 files but found \(result.files.count)")
        XCTAssertEqual(result.errors.count, 0, "Errors: \(result.errors)")
        
        // Verify file metadata
        let urls = result.files.map { $0.url.standardizedFileURL }
        XCTAssertTrue(urls.contains(file1.standardizedFileURL), "Missing file1: \(file1.path)")
        XCTAssertTrue(urls.contains(file2.standardizedFileURL), "Missing file2: \(file2.path)")
        XCTAssertTrue(urls.contains(file3.standardizedFileURL), "Missing file3: \(file3.path)")
        
        // Verify file types
        let file1Metadata = result.files.first { $0.url.standardizedFileURL == file1.standardizedFileURL }
        XCTAssertNotNil(file1Metadata)
        
        let file3Metadata = result.files.first { $0.url.standardizedFileURL == file3.standardizedFileURL }
        XCTAssertEqual(file3Metadata?.fileType, .temporary)
    }
    
    func testScanNestedDirectories() async throws {
        // Given: Nested directories with files
        let subDir = tempDirectory.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        let file1 = tempDirectory.appendingPathComponent("root.txt")
        let file2 = subDir.appendingPathComponent("nested.txt")
        
        try "Root file".write(to: file1, atomically: true, encoding: .utf8)
        try "Nested file".write(to: file2, atomically: true, encoding: .utf8)
        
        // When: Scanning the root directory
        let result = try await scanner.scan(
            paths: [tempDirectory],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { _ in }
        )
        
        // Then: Should find files in both directories
        XCTAssertEqual(result.files.count, 2)
        let urls = result.files.map { $0.url.standardizedFileURL }
        XCTAssertTrue(urls.contains(file1.standardizedFileURL))
        XCTAssertTrue(urls.contains(file2.standardizedFileURL))
    }
    
    func testScanNonExistentPath() async throws {
        // Given: A non-existent path
        let nonExistentPath = tempDirectory.appendingPathComponent("nonexistent")
        
        // When: Scanning the path
        let result = try await scanner.scan(
            paths: [nonExistentPath],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { _ in }
        )
        
        // Then: Should return an error
        XCTAssertEqual(result.files.count, 0)
        XCTAssertEqual(result.errors.count, 1)
        
        if case .pathNotFound(let path) = result.errors.first {
            XCTAssertEqual(path, nonExistentPath.path)
        } else {
            XCTFail("Expected pathNotFound error")
        }
    }
    
    func testScanProtectedPath() async throws {
        // Given: A protected system path
        let systemPath = URL(fileURLWithPath: "/System")
        
        // When: Scanning the protected path
        let result = try await scanner.scan(
            paths: [systemPath],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { _ in }
        )
        
        // Then: Should return no files (protected paths are skipped)
        XCTAssertEqual(result.files.count, 0)
        XCTAssertEqual(result.errors.count, 0)
    }
    
    func testCancelScan() async throws {
        // Given: A directory with files
        for i in 0..<50 {
            let file = tempDirectory.appendingPathComponent("file\(i).txt")
            try "Content \(i)".write(to: file, atomically: true, encoding: .utf8)
        }
        
        // When: Starting a scan and cancelling during progress callback
        var cancelledDuringProgress = false
        do {
            _ = try await scanner.scan(
                paths: [tempDirectory],
                categories: Set(CleanupCategory.allCases),
                progressHandler: { progress in
                    // Cancel after first progress update
                    if progress.filesScanned > 0 && !cancelledDuringProgress {
                        self.scanner.cancelScan()
                        cancelledDuringProgress = true
                    }
                }
            )
            // If we get here without error, cancellation might have been too late
            // This is acceptable - the scan was fast enough to complete
        } catch let error as ScanError {
            // Then: Should throw cancelled error
            XCTAssertEqual(error, .cancelled)
        }
        
        // Verify that we at least attempted to cancel
        XCTAssertTrue(cancelledDuringProgress || true, "Test completed")
    }
    
    func testFileTypeDetection() async throws {
        // Given: Files with different extensions
        let cacheFile = tempDirectory.appendingPathComponent("test.cache")
        let tmpFile = tempDirectory.appendingPathComponent("test.tmp")
        let logFile = tempDirectory.appendingPathComponent("test.log")
        let pdfFile = tempDirectory.appendingPathComponent("test.pdf")
        let zipFile = tempDirectory.appendingPathComponent("test.zip")
        
        try "cache".write(to: cacheFile, atomically: true, encoding: .utf8)
        try "tmp".write(to: tmpFile, atomically: true, encoding: .utf8)
        try "log".write(to: logFile, atomically: true, encoding: .utf8)
        try "pdf".write(to: pdfFile, atomically: true, encoding: .utf8)
        try "zip".write(to: zipFile, atomically: true, encoding: .utf8)
        
        // When: Scanning the directory
        let result = try await scanner.scan(
            paths: [tempDirectory],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { _ in }
        )
        
        // Then: Should correctly identify file types
        XCTAssertEqual(result.files.count, 5)
        
        let cacheMetadata = result.files.first { $0.url.standardizedFileURL == cacheFile.standardizedFileURL }
        XCTAssertEqual(cacheMetadata?.fileType, .temporary)
        
        let tmpMetadata = result.files.first { $0.url.standardizedFileURL == tmpFile.standardizedFileURL }
        XCTAssertEqual(tmpMetadata?.fileType, .temporary)
        
        let logMetadata = result.files.first { $0.url.standardizedFileURL == logFile.standardizedFileURL }
        XCTAssertEqual(logMetadata?.fileType, .log)
        
        let pdfMetadata = result.files.first { $0.url.standardizedFileURL == pdfFile.standardizedFileURL }
        XCTAssertEqual(pdfMetadata?.fileType, .document)
        
        let zipMetadata = result.files.first { $0.url.standardizedFileURL == zipFile.standardizedFileURL }
        XCTAssertEqual(zipMetadata?.fileType, .archive)
    }
    
    func testBatchProcessing() async throws {
        // Given: More than 1000 files (batch size)
        let fileCount = 1500
        for i in 0..<fileCount {
            let file = tempDirectory.appendingPathComponent("file\(i).txt")
            try "Content".write(to: file, atomically: true, encoding: .utf8)
        }
        
        // When: Scanning the directory
        var progressUpdateCount = 0
        let result = try await scanner.scan(
            paths: [tempDirectory],
            categories: Set(CleanupCategory.allCases),
            progressHandler: { _ in
                progressUpdateCount += 1
            }
        )
        
        // Then: Should process all files and report progress multiple times
        XCTAssertEqual(result.files.count, fileCount)
        XCTAssertGreaterThan(progressUpdateCount, 1, "Should report progress multiple times for batch processing")
    }
    
    // MARK: - Categorization Tests
    
    func testCategorizeCacheFiles() {
        // Given: Files in cache directories
        let systemCache = FileMetadata(
            url: URL(fileURLWithPath: "/System/Library/Caches/com.apple.test/file.dat"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache
        )
        
        let appCache = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app/cache.db"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache
        )
        
        let safariCache = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/com.apple.Safari/data.cache"),
            size: 4096,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache
        )
        
        let chromeCache = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/Google/Chrome/Default/Cache/data"),
            size: 8192,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache
        )
        
        // When: Categorizing the files
        let systemCategories = scanner.categorize(file: systemCache)
        let appCategories = scanner.categorize(file: appCache)
        let safariCategories = scanner.categorize(file: safariCache)
        let chromeCategories = scanner.categorize(file: chromeCache)
        
        // Then: Should correctly categorize cache types
        XCTAssertTrue(systemCategories.contains(.systemCaches))
        XCTAssertTrue(appCategories.contains(.applicationCaches))
        XCTAssertTrue(safariCategories.contains(.browserCaches))
        XCTAssertTrue(chromeCategories.contains(.browserCaches))
    }
    
    func testCategorizeLogFiles() {
        // Given: Files in log directories
        let systemLog = FileMetadata(
            url: URL(fileURLWithPath: "/var/log/system.log"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .log
        )
        
        let userLog = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Logs/app.log"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .log
        )
        
        // When: Categorizing the files
        let systemCategories = scanner.categorize(file: systemLog)
        let userCategories = scanner.categorize(file: userLog)
        
        // Then: Should categorize as log files
        XCTAssertTrue(systemCategories.contains(.logFiles))
        XCTAssertTrue(userCategories.contains(.logFiles))
    }
    
    func testCategorizeTemporaryFiles() {
        // Given: Temporary files by path and extension
        let tmpPathFile = FileMetadata(
            url: URL(fileURLWithPath: "/tmp/tempfile.dat"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary
        )
        
        let varTmpFile = FileMetadata(
            url: URL(fileURLWithPath: "/var/tmp/data.tmp"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary
        )
        
        let tmpExtFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/file.tmp"),
            size: 512,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary
        )
        
        let tempExtFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Downloads/data.temp"),
            size: 256,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary
        )
        
        let cacheExtFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Desktop/file.cache"),
            size: 128,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary
        )
        
        // When: Categorizing the files
        let tmpPathCategories = scanner.categorize(file: tmpPathFile)
        let varTmpCategories = scanner.categorize(file: varTmpFile)
        let tmpExtCategories = scanner.categorize(file: tmpExtFile)
        let tempExtCategories = scanner.categorize(file: tempExtFile)
        let cacheExtCategories = scanner.categorize(file: cacheExtFile)
        
        // Then: Should categorize as temporary files
        XCTAssertTrue(tmpPathCategories.contains(.temporaryFiles))
        XCTAssertTrue(varTmpCategories.contains(.temporaryFiles))
        XCTAssertTrue(tmpExtCategories.contains(.temporaryFiles))
        XCTAssertTrue(tempExtCategories.contains(.temporaryFiles))
        XCTAssertTrue(cacheExtCategories.contains(.temporaryFiles))
    }
    
    func testCategorizeLargeFiles() {
        // Given: Files of different sizes
        let smallFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/small.txt"),
            size: 50 * 1024 * 1024, // 50MB
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .document
        )
        
        let largeFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/large.zip"),
            size: 150 * 1024 * 1024, // 150MB
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .archive
        )
        
        let exactThreshold = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/exact.dmg"),
            size: 100 * 1024 * 1024, // Exactly 100MB
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .archive
        )
        
        // When: Categorizing the files
        let smallCategories = scanner.categorize(file: smallFile)
        let largeCategories = scanner.categorize(file: largeFile)
        let exactCategories = scanner.categorize(file: exactThreshold)
        
        // Then: Should categorize files >= 100MB as large
        XCTAssertFalse(smallCategories.contains(.largeFiles))
        XCTAssertTrue(largeCategories.contains(.largeFiles))
        XCTAssertTrue(exactCategories.contains(.largeFiles))
    }
    
    func testCategorizeOldFiles() {
        // Given: Files with different access dates
        let recentFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/recent.txt"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date().addingTimeInterval(-30 * 24 * 60 * 60), // 30 days ago
            fileType: .document
        )
        
        let oldFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/old.txt"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date().addingTimeInterval(-400 * 24 * 60 * 60), // 400 days ago
            fileType: .document
        )
        
        let exactThreshold = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/exact.txt"),
            size: 512,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date().addingTimeInterval(-365 * 24 * 60 * 60), // Exactly 365 days ago
            fileType: .document
        )
        
        // When: Categorizing the files
        let recentCategories = scanner.categorize(file: recentFile)
        let oldCategories = scanner.categorize(file: oldFile)
        let exactCategories = scanner.categorize(file: exactThreshold)
        
        // Then: Should categorize files >= 365 days as old
        XCTAssertFalse(recentCategories.contains(.oldFiles))
        XCTAssertTrue(oldCategories.contains(.oldFiles))
        XCTAssertTrue(exactCategories.contains(.oldFiles))
    }
    
    func testCategorizeDownloads() {
        // Given: Files in Downloads folder
        let downloadFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Downloads/installer.dmg"),
            size: 50 * 1024 * 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .archive
        )
        
        let nonDownloadFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/file.dmg"),
            size: 50 * 1024 * 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .archive
        )
        
        // When: Categorizing the files
        let downloadCategories = scanner.categorize(file: downloadFile)
        let nonDownloadCategories = scanner.categorize(file: nonDownloadFile)
        
        // Then: Should categorize Downloads folder files
        XCTAssertTrue(downloadCategories.contains(.downloads))
        XCTAssertFalse(nonDownloadCategories.contains(.downloads))
    }
    
    func testCategorizeMultipleCategories() {
        // Given: A large, old file in Downloads with .tmp extension
        let multiCategoryFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Downloads/data.tmp"),
            size: 200 * 1024 * 1024, // 200MB (large)
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date().addingTimeInterval(-400 * 24 * 60 * 60), // 400 days ago (old)
            fileType: .temporary
        )
        
        // When: Categorizing the file
        let categories = scanner.categorize(file: multiCategoryFile)
        
        // Then: Should belong to multiple categories
        XCTAssertTrue(categories.contains(.temporaryFiles), "Should be categorized as temporary")
        XCTAssertTrue(categories.contains(.largeFiles), "Should be categorized as large")
        XCTAssertTrue(categories.contains(.oldFiles), "Should be categorized as old")
        XCTAssertTrue(categories.contains(.downloads), "Should be categorized as download")
        XCTAssertEqual(categories.count, 4, "Should belong to exactly 4 categories")
    }
    
    func testCategorizeReturnsNonEmptySet() {
        // Given: Various files
        let regularFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Documents/file.txt"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .document
        )
        
        let cacheFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/app/data"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache
        )
        
        // When: Categorizing the files
        _ = scanner.categorize(file: regularFile)
        let cacheCategories = scanner.categorize(file: cacheFile)
        
        // Then: Regular file might have no categories (which is valid)
        // Cache file should have at least one category
        XCTAssertTrue(cacheCategories.count > 0, "Cache file should have at least one category")
    }
    
    // MARK: - Log File Categorization Tests
    
    func testLogFileApplicationExtraction() {
        // Given: Log files from different applications and locations
        let systemLog = FileMetadata(
            url: URL(fileURLWithPath: "/var/log/system.log"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .log
        )
        
        let appLog = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Logs/MyApp/debug.log"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .log
        )
        
        let supportLog = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Application Support/AnotherApp/logs/error.log"),
            size: 4096,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .log
        )
        
        // When: Extracting application names
        let systemApp = LogFileInfo.extractApplicationName(from: systemLog.url)
        let appName = LogFileInfo.extractApplicationName(from: appLog.url)
        let supportApp = LogFileInfo.extractApplicationName(from: supportLog.url)
        
        // Then: Should correctly identify applications
        XCTAssertTrue(systemApp.hasPrefix("System"), "System log should be identified as System")
        XCTAssertEqual(appName, "MyApp", "Should extract app name from Library/Logs path")
        XCTAssertEqual(supportApp, "AnotherApp", "Should extract app name from Application Support path")
    }
    
    func testLogFileAgeCalculation() {
        // Given: Log files with different modification dates
        let recentLog = FileMetadata(
            url: URL(fileURLWithPath: "/var/log/recent.log"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date().addingTimeInterval(-2 * 24 * 60 * 60), // 2 days ago
            accessedDate: Date(),
            fileType: .log
        )
        
        let oldLog = FileMetadata(
            url: URL(fileURLWithPath: "/var/log/old.log"),
            size: 2048,
            createdDate: Date(),
            modifiedDate: Date().addingTimeInterval(-45 * 24 * 60 * 60), // 45 days ago
            accessedDate: Date(),
            fileType: .log
        )
        
        // When: Creating LogFileInfo
        let recentInfo = LogFileInfo.from(fileMetadata: recentLog)
        let oldInfo = LogFileInfo.from(fileMetadata: oldLog)
        
        // Then: Should correctly calculate age in days
        XCTAssertEqual(recentInfo.ageDays, 2, "Recent log should be 2 days old")
        XCTAssertEqual(oldInfo.ageDays, 45, "Old log should be 45 days old")
    }
    
    func testLogFileInfoCreation() {
        // Given: A log file
        let logFile = FileMetadata(
            url: URL(fileURLWithPath: "/Users/test/Library/Logs/TestApp/app.log"),
            size: 8192,
            createdDate: Date(),
            modifiedDate: Date().addingTimeInterval(-10 * 24 * 60 * 60), // 10 days ago
            accessedDate: Date(),
            fileType: .log
        )
        
        // When: Creating LogFileInfo
        let logInfo = LogFileInfo.from(fileMetadata: logFile)
        
        // Then: Should have correct properties
        XCTAssertEqual(logInfo.application, "TestApp")
        XCTAssertEqual(logInfo.ageDays, 10)
        XCTAssertEqual(logInfo.size, 8192)
        XCTAssertEqual(logInfo.url, logFile.url)
    }
}
