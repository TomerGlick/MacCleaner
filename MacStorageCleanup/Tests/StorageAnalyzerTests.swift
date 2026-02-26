import XCTest
@testable import MacStorageCleanup

final class StorageAnalyzerTests: XCTestCase {
    var analyzer: DefaultStorageAnalyzer!
    var safeListManager: SafeListManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        safeListManager = DefaultSafeListManager()
        analyzer = DefaultStorageAnalyzer(safeListManager: safeListManager)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        analyzer = nil
        safeListManager = nil
        super.tearDown()
    }
    
    // MARK: - Categorization Tests
    
    func testCategorizeCacheFile() {
        let cacheFile = createFileMetadata(
            path: "/Users/test/Library/Caches/com.example.app/cache.db",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: cacheFile)
        
        XCTAssertTrue(categories.contains(.applicationCaches))
    }
    
    func testCategorizeBrowserCache() {
        let safariCache = createFileMetadata(
            path: "/Users/test/Library/Caches/com.apple.Safari/cache.db",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: safariCache)
        
        XCTAssertTrue(categories.contains(.browserCaches))
    }
    
    func testCategorizeTemporaryFileByPath() {
        let tempFile = createFileMetadata(
            path: "/tmp/tempfile.dat",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: tempFile)
        
        XCTAssertTrue(categories.contains(.temporaryFiles))
    }
    
    func testCategorizeTemporaryFileByExtension() {
        let tempFile = createFileMetadata(
            path: "/Users/test/Documents/file.tmp",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: tempFile)
        
        XCTAssertTrue(categories.contains(.temporaryFiles))
    }
    
    func testCategorizeLogFile() {
        let logFile = createFileMetadata(
            path: "/Users/test/Library/Logs/app.log",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: logFile)
        
        XCTAssertTrue(categories.contains(.logFiles))
    }
    
    func testCategorizeDownloadsFile() {
        let downloadFile = createFileMetadata(
            path: "/Users/test/Downloads/document.pdf",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: downloadFile)
        
        XCTAssertTrue(categories.contains(.downloads))
    }
    
    func testCategorizeLargeFile() {
        let largeFile = createFileMetadata(
            path: "/Users/test/Documents/video.mp4",
            size: 150 * 1024 * 1024 // 150MB
        )
        
        let categories = analyzer.categorize(file: largeFile)
        
        XCTAssertTrue(categories.contains(.largeFiles))
    }
    
    func testCategorizeOldFile() {
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let oldFile = createFileMetadata(
            path: "/Users/test/Documents/old.txt",
            size: 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: oldFile)
        
        XCTAssertTrue(categories.contains(.oldFiles))
    }
    
    func testCategorizeMultipleCategories() {
        // Large old file in downloads
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60)
        let file = createFileMetadata(
            path: "/Users/test/Downloads/large-archive.zip",
            size: 150 * 1024 * 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: file)
        
        XCTAssertTrue(categories.contains(.downloads))
        XCTAssertTrue(categories.contains(.largeFiles))
        XCTAssertTrue(categories.contains(.oldFiles))
        XCTAssertEqual(categories.count, 3)
    }
    
    // MARK: - Calculate Savings Tests
    
    func testCalculateSavingsEmptyArray() {
        let savings = analyzer.calculateSavings(files: [])
        XCTAssertEqual(savings, 0)
    }
    
    func testCalculateSavingsSingleFile() {
        let file = createFileMetadata(path: "/test/file.txt", size: 1024)
        let savings = analyzer.calculateSavings(files: [file])
        XCTAssertEqual(savings, 1024)
    }
    
    func testCalculateSavingsMultipleFiles() {
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1024),
            createFileMetadata(path: "/test/file2.txt", size: 2048),
            createFileMetadata(path: "/test/file3.txt", size: 512)
        ]
        
        let savings = analyzer.calculateSavings(files: files)
        XCTAssertEqual(savings, 3584)
    }
    
    // MARK: - Analysis Tests
    
    func testAnalyzeEmptyScanResult() {
        let scanResult = ScanResult(files: [], errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.totalSize, 0)
        XCTAssertEqual(result.potentialSavings, 0)
        XCTAssertEqual(result.duplicateGroups.count, 0)
        
        // All categories should exist but be empty
        for category in CleanupCategory.allCases {
            XCTAssertNotNil(result.categorizedFiles[category])
            XCTAssertEqual(result.categorizedFiles[category]?.count, 0)
        }
    }
    
    func testAnalyzeCategorizeFiles() {
        let files = [
            createFileMetadata(path: "/Users/test/Library/Caches/app/cache.db", size: 1024),
            createFileMetadata(path: "/tmp/temp.dat", size: 512),
            createFileMetadata(path: "/Users/test/Downloads/file.pdf", size: 2048)
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.totalSize, 3584)
        XCTAssertEqual(result.categorizedFiles[.applicationCaches]?.count, 1)
        XCTAssertEqual(result.categorizedFiles[.temporaryFiles]?.count, 1)
        XCTAssertEqual(result.categorizedFiles[.downloads]?.count, 1)
    }
    
    func testAnalyzeTotalSizeCalculation() {
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1000),
            createFileMetadata(path: "/test/file2.txt", size: 2000),
            createFileMetadata(path: "/test/file3.txt", size: 3000)
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.totalSize, 6000)
    }
    
    // MARK: - Duplicate Detection Tests
    
    func testDuplicateDetectionWithIdenticalFiles() throws {
        // Create two identical files > 1MB
        let content = Data(repeating: 0x42, count: 2 * 1024 * 1024) // 2MB
        
        let file1URL = tempDirectory.appendingPathComponent("file1.dat")
        let file2URL = tempDirectory.appendingPathComponent("file2.dat")
        
        try content.write(to: file1URL)
        try content.write(to: file2URL)
        
        let file1 = createFileMetadata(path: file1URL.path, size: Int64(content.count))
        let file2 = createFileMetadata(path: file2URL.path, size: Int64(content.count))
        
        let scanResult = ScanResult(files: [file1, file2], errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.duplicateGroups.count, 1)
        
        let group = result.duplicateGroups[0]
        XCTAssertEqual(group.files.count, 2)
        XCTAssertEqual(group.totalSize, Int64(content.count) * 2)
        XCTAssertEqual(group.wastedSpace, Int64(content.count))
    }
    
    func testDuplicateDetectionIgnoresSmallFiles() throws {
        // Create two identical files < 1MB
        let content = Data(repeating: 0x42, count: 512 * 1024) // 512KB
        
        let file1URL = tempDirectory.appendingPathComponent("small1.dat")
        let file2URL = tempDirectory.appendingPathComponent("small2.dat")
        
        try content.write(to: file1URL)
        try content.write(to: file2URL)
        
        let file1 = createFileMetadata(path: file1URL.path, size: Int64(content.count))
        let file2 = createFileMetadata(path: file2URL.path, size: Int64(content.count))
        
        let scanResult = ScanResult(files: [file1, file2], errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        // Should not detect duplicates for files < 1MB
        XCTAssertEqual(result.duplicateGroups.count, 0)
    }
    
    func testDuplicateDetectionWithDifferentFiles() throws {
        // Create two different files > 1MB
        let content1 = Data(repeating: 0x42, count: 2 * 1024 * 1024)
        let content2 = Data(repeating: 0x43, count: 2 * 1024 * 1024)
        
        let file1URL = tempDirectory.appendingPathComponent("file1.dat")
        let file2URL = tempDirectory.appendingPathComponent("file2.dat")
        
        try content1.write(to: file1URL)
        try content2.write(to: file2URL)
        
        let file1 = createFileMetadata(path: file1URL.path, size: Int64(content1.count))
        let file2 = createFileMetadata(path: file2URL.path, size: Int64(content2.count))
        
        let scanResult = ScanResult(files: [file1, file2], errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        // Should not detect duplicates for different files
        XCTAssertEqual(result.duplicateGroups.count, 0)
    }
    
    func testDuplicateDetectionWithMultipleGroups() throws {
        // Create two groups of duplicates
        let content1 = Data(repeating: 0x42, count: 2 * 1024 * 1024)
        let content2 = Data(repeating: 0x43, count: 2 * 1024 * 1024)
        
        let file1aURL = tempDirectory.appendingPathComponent("file1a.dat")
        let file1bURL = tempDirectory.appendingPathComponent("file1b.dat")
        let file2aURL = tempDirectory.appendingPathComponent("file2a.dat")
        let file2bURL = tempDirectory.appendingPathComponent("file2b.dat")
        
        try content1.write(to: file1aURL)
        try content1.write(to: file1bURL)
        try content2.write(to: file2aURL)
        try content2.write(to: file2bURL)
        
        let files = [
            createFileMetadata(path: file1aURL.path, size: Int64(content1.count)),
            createFileMetadata(path: file1bURL.path, size: Int64(content1.count)),
            createFileMetadata(path: file2aURL.path, size: Int64(content2.count)),
            createFileMetadata(path: file2bURL.path, size: Int64(content2.count))
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.duplicateGroups.count, 2)
        
        for group in result.duplicateGroups {
            XCTAssertEqual(group.files.count, 2)
            XCTAssertEqual(group.wastedSpace, Int64(content1.count))
        }
    }
    
    func testDuplicateWastedSpaceCalculation() throws {
        // Create 3 identical files
        let content = Data(repeating: 0x42, count: 2 * 1024 * 1024) // 2MB
        
        let file1URL = tempDirectory.appendingPathComponent("file1.dat")
        let file2URL = tempDirectory.appendingPathComponent("file2.dat")
        let file3URL = tempDirectory.appendingPathComponent("file3.dat")
        
        try content.write(to: file1URL)
        try content.write(to: file2URL)
        try content.write(to: file3URL)
        
        let files = [
            createFileMetadata(path: file1URL.path, size: Int64(content.count)),
            createFileMetadata(path: file2URL.path, size: Int64(content.count)),
            createFileMetadata(path: file3URL.path, size: Int64(content.count))
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        XCTAssertEqual(result.duplicateGroups.count, 1)
        
        let group = result.duplicateGroups[0]
        XCTAssertEqual(group.files.count, 3)
        XCTAssertEqual(group.totalSize, Int64(content.count) * 3)
        // Wasted space = size * (count - 1) = 2MB * 2 = 4MB
        XCTAssertEqual(group.wastedSpace, Int64(content.count) * 2)
    }
    
    // MARK: - Edge Cases
    
    func testCategorizeFileWithNoMatchingCategories() {
        // A recent, small file in a non-special location
        let file = createFileMetadata(
            path: "/Users/test/Documents/normal.txt",
            size: 1024
        )
        
        let categories = analyzer.categorize(file: file)
        
        // Should return empty set if no categories match
        XCTAssertTrue(categories.isEmpty)
    }
    
    func testAnalyzeWithMixedFileSizes() {
        let files = [
            createFileMetadata(path: "/test/tiny.txt", size: 1),
            createFileMetadata(path: "/test/small.txt", size: 1024),
            createFileMetadata(path: "/test/medium.txt", size: 1024 * 1024),
            createFileMetadata(path: "/test/large.txt", size: 100 * 1024 * 1024)
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        let megabyte: Int64 = 1024 * 1024
        let expectedTotal: Int64 = 1 + 1024 + megabyte + (100 * megabyte)
        XCTAssertEqual(result.totalSize, expectedTotal)
    }
    
    // MARK: - Filtering Tests
    
    func testFilterByAgeIncludesOldFiles() {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        
        let files = [
            createFileMetadata(path: "/test/old.txt", size: 1024, accessedDate: oldDate),
            createFileMetadata(path: "/test/recent.txt", size: 1024, accessedDate: recentDate)
        ]
        
        let filtered = analyzer.filterByAge(files: files, thresholdDays: 30)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "old.txt")
    }
    
    func testFilterByAgeExcludesRecentFiles() {
        let recentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        
        let files = [
            createFileMetadata(path: "/test/recent.txt", size: 1024, accessedDate: recentDate)
        ]
        
        let filtered = analyzer.filterByAge(files: files, thresholdDays: 30)
        
        XCTAssertEqual(filtered.count, 0)
    }
    
    func testFilterByAgeWithZeroThreshold() {
        // Create a file accessed 1 second ago to ensure age > 0
        let oneSecondAgo = Date().addingTimeInterval(-1)
        let files = [
            createFileMetadata(path: "/test/file.txt", size: 1024, accessedDate: oneSecondAgo)
        ]
        
        let filtered = analyzer.filterByAge(files: files, thresholdDays: 0)
        
        // Threshold of 0 should be clamped to 30 days minimum, so recent files should not be included
        XCTAssertEqual(filtered.count, 0)
    }
    
    func testFilterBySizeIncludesLargeFiles() {
        let files = [
            createFileMetadata(path: "/test/small.txt", size: 1024),
            createFileMetadata(path: "/test/large.txt", size: 100 * 1024 * 1024)
        ]
        
        let threshold: Int64 = 10 * 1024 * 1024 // 10MB
        let filtered = analyzer.filterBySize(files: files, thresholdBytes: threshold)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "large.txt")
    }
    
    func testFilterBySizeIncludesExactThreshold() {
        let threshold: Int64 = 1024
        let files = [
            createFileMetadata(path: "/test/exact.txt", size: threshold),
            createFileMetadata(path: "/test/smaller.txt", size: threshold - 1)
        ]
        
        let filtered = analyzer.filterBySize(files: files, thresholdBytes: threshold)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "exact.txt")
    }
    
    func testFilterBySizeWithZeroThreshold() {
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 0),
            createFileMetadata(path: "/test/file2.txt", size: 1024)
        ]
        
        let filtered = analyzer.filterBySize(files: files, thresholdBytes: 0)
        
        // Should include all files (size >= 0)
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterByTypeMatchesCacheFiles() {
        let files = [
            createFileMetadata(path: "/test/cache.db", size: 1024, fileType: .cache),
            createFileMetadata(path: "/test/log.txt", size: 1024, fileType: .log),
            createFileMetadata(path: "/test/doc.pdf", size: 1024, fileType: .document)
        ]
        
        let filtered = analyzer.filterByType(files: files, fileType: .cache)
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "cache.db")
    }
    
    func testFilterByTypeMatchesOtherWithSameExtension() {
        let files = [
            createFileMetadata(path: "/test/file1.xyz", size: 1024, fileType: .other("xyz")),
            createFileMetadata(path: "/test/file2.xyz", size: 1024, fileType: .other("xyz")),
            createFileMetadata(path: "/test/file3.abc", size: 1024, fileType: .other("abc"))
        ]
        
        let filtered = analyzer.filterByType(files: files, fileType: .other("xyz"))
        
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testFilterByTypeNoMatches() {
        let files = [
            createFileMetadata(path: "/test/log.txt", size: 1024, fileType: .log),
            createFileMetadata(path: "/test/doc.pdf", size: 1024, fileType: .document)
        ]
        
        let filtered = analyzer.filterByType(files: files, fileType: .cache)
        
        XCTAssertEqual(filtered.count, 0)
    }
    
    func testSortBySizeDescending() {
        let files = [
            createFileMetadata(path: "/test/small.txt", size: 1024),
            createFileMetadata(path: "/test/large.txt", size: 100 * 1024 * 1024),
            createFileMetadata(path: "/test/medium.txt", size: 10 * 1024 * 1024)
        ]
        
        let sorted = analyzer.sortBySize(files: files)
        
        XCTAssertEqual(sorted.count, 3)
        XCTAssertEqual(sorted[0].url.lastPathComponent, "large.txt")
        XCTAssertEqual(sorted[1].url.lastPathComponent, "medium.txt")
        XCTAssertEqual(sorted[2].url.lastPathComponent, "small.txt")
        
        // Verify descending order
        for i in 0..<sorted.count - 1 {
            XCTAssertGreaterThanOrEqual(sorted[i].size, sorted[i + 1].size)
        }
    }
    
    func testSortBySizeWithEqualSizes() {
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1024),
            createFileMetadata(path: "/test/file2.txt", size: 1024),
            createFileMetadata(path: "/test/file3.txt", size: 1024)
        ]
        
        let sorted = analyzer.sortBySize(files: files)
        
        XCTAssertEqual(sorted.count, 3)
        // All files have same size, order should be stable
        for i in 0..<sorted.count - 1 {
            XCTAssertEqual(sorted[i].size, sorted[i + 1].size)
        }
    }
    
    func testSortBySizeEmptyArray() {
        let sorted = analyzer.sortBySize(files: [])
        XCTAssertEqual(sorted.count, 0)
    }
    
    func testApplyFiltersWithSingleFilter() {
        let files = [
            createFileMetadata(path: "/test/small.txt", size: 1024),
            createFileMetadata(path: "/test/large.txt", size: 100 * 1024 * 1024)
        ]
        
        let sizeFilter: (FileMetadata) -> Bool = { $0.size >= 10 * 1024 * 1024 }
        let filtered = analyzer.applyFilters(files: files, filters: [sizeFilter])
        
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "large.txt")
    }
    
    func testApplyFiltersWithMultipleFilters() {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        
        let files = [
            createFileMetadata(path: "/test/old-large.txt", size: 100 * 1024 * 1024, accessedDate: oldDate),
            createFileMetadata(path: "/test/old-small.txt", size: 1024, accessedDate: oldDate),
            createFileMetadata(path: "/test/recent-large.txt", size: 100 * 1024 * 1024, accessedDate: recentDate),
            createFileMetadata(path: "/test/recent-small.txt", size: 1024, accessedDate: recentDate)
        ]
        
        let sizeFilter: (FileMetadata) -> Bool = { $0.size >= 10 * 1024 * 1024 }
        let ageFilter: (FileMetadata) -> Bool = {
            let age = Date().timeIntervalSince($0.accessedDate)
            return age > 30 * 24 * 60 * 60
        }
        
        let filtered = analyzer.applyFilters(files: files, filters: [sizeFilter, ageFilter])
        
        // Should only include old AND large files
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "old-large.txt")
    }
    
    func testApplyFiltersWithNoFilters() {
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1024),
            createFileMetadata(path: "/test/file2.txt", size: 2048)
        ]
        
        let filtered = analyzer.applyFilters(files: files, filters: [])
        
        // With no filters, all files should pass
        XCTAssertEqual(filtered.count, 2)
    }
    
    func testApplyFiltersNoMatches() {
        let files = [
            createFileMetadata(path: "/test/small.txt", size: 1024)
        ]
        
        let sizeFilter: (FileMetadata) -> Bool = { $0.size >= 100 * 1024 * 1024 }
        let filtered = analyzer.applyFilters(files: files, filters: [sizeFilter])
        
        XCTAssertEqual(filtered.count, 0)
    }
    
    func testFilterCompositionWithTypeAndAge() {
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60)
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        
        let files = [
            createFileMetadata(path: "/test/old-cache.db", size: 1024, accessedDate: oldDate, fileType: .cache),
            createFileMetadata(path: "/test/recent-cache.db", size: 1024, accessedDate: recentDate, fileType: .cache),
            createFileMetadata(path: "/test/old-log.txt", size: 1024, accessedDate: oldDate, fileType: .log)
        ]
        
        let typeFilter: (FileMetadata) -> Bool = { $0.fileType == .cache }
        let ageFilter: (FileMetadata) -> Bool = {
            let age = Date().timeIntervalSince($0.accessedDate)
            return age > 30 * 24 * 60 * 60
        }
        
        let filtered = analyzer.applyFilters(files: files, filters: [typeFilter, ageFilter])
        
        // Should only include old cache files
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "old-cache.db")
    }
    
    // MARK: - Age Threshold Clamping Tests
    
    func testClampAgeThresholdWithinRange() {
        // Test values within valid range [30, 1095]
        XCTAssertEqual(analyzer.clampAgeThreshold(30), 30)
        XCTAssertEqual(analyzer.clampAgeThreshold(365), 365)
        XCTAssertEqual(analyzer.clampAgeThreshold(1095), 1095)
    }
    
    func testClampAgeThresholdBelowMinimum() {
        // Test values below minimum (30 days)
        XCTAssertEqual(analyzer.clampAgeThreshold(0), 30)
        XCTAssertEqual(analyzer.clampAgeThreshold(10), 30)
        XCTAssertEqual(analyzer.clampAgeThreshold(29), 30)
        XCTAssertEqual(analyzer.clampAgeThreshold(-100), 30)
    }
    
    func testClampAgeThresholdAboveMaximum() {
        // Test values above maximum (1095 days)
        XCTAssertEqual(analyzer.clampAgeThreshold(1096), 1095)
        XCTAssertEqual(analyzer.clampAgeThreshold(2000), 1095)
        XCTAssertEqual(analyzer.clampAgeThreshold(10000), 1095)
    }
    
    func testFilterByAgeAppliesClamping() {
        // Create files with various ages
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1024, accessedDate: Date().addingTimeInterval(-20 * 24 * 60 * 60)), // 20 days old
            createFileMetadata(path: "/test/file2.txt", size: 1024, accessedDate: Date().addingTimeInterval(-40 * 24 * 60 * 60)), // 40 days old
            createFileMetadata(path: "/test/file3.txt", size: 1024, accessedDate: Date().addingTimeInterval(-100 * 24 * 60 * 60)) // 100 days old
        ]
        
        // Try to filter with threshold below minimum (should be clamped to 30)
        let filtered = analyzer.filterByAge(files: files, thresholdDays: 10)
        
        // Should only include files older than 30 days (the clamped value)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "file2.txt")
        XCTAssertEqual(filtered[1].url.lastPathComponent, "file3.txt")
    }
    
    func testFilterByAgeWithExtremelyHighThreshold() {
        // Create files with various ages
        let files = [
            createFileMetadata(path: "/test/file1.txt", size: 1024, accessedDate: Date().addingTimeInterval(-1000 * 24 * 60 * 60)), // 1000 days old
            createFileMetadata(path: "/test/file2.txt", size: 1024, accessedDate: Date().addingTimeInterval(-1100 * 24 * 60 * 60)), // 1100 days old
            createFileMetadata(path: "/test/file3.txt", size: 1024, accessedDate: Date().addingTimeInterval(-2000 * 24 * 60 * 60)) // 2000 days old
        ]
        
        // Try to filter with threshold above maximum (should be clamped to 1095)
        let filtered = analyzer.filterByAge(files: files, thresholdDays: 5000)
        
        // Should only include files older than 1095 days (the clamped value)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered[0].url.lastPathComponent, "file2.txt")
        XCTAssertEqual(filtered[1].url.lastPathComponent, "file3.txt")
    }
    
    // MARK: - System File Exclusion Tests
    
    func testOldSystemFileNotCategorizedAsOld() {
        // Create an old file in a protected system directory
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let systemFile = createFileMetadata(
            path: "/System/Library/CoreServices/old-system-file.dat",
            size: 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: systemFile)
        
        // Should NOT be categorized as old file even though it's old
        XCTAssertFalse(categories.contains(.oldFiles), "System files should not be categorized as old files")
    }
    
    func testOldApplicationBundleNotCategorizedAsOld() {
        // Create an old application bundle
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let appBundle = createFileMetadata(
            path: "/Applications/Safari.app/Contents/MacOS/Safari",
            size: 10 * 1024 * 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: appBundle)
        
        // Should NOT be categorized as old file even though it's old
        XCTAssertFalse(categories.contains(.oldFiles), "Application bundles should not be categorized as old files")
    }
    
    func testOldAppBundleWithExtensionNotCategorizedAsOld() {
        // Create an old .app file
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let appFile = createFileMetadata(
            path: "/Applications/MyApp.app",
            size: 50 * 1024 * 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: appFile)
        
        // Should NOT be categorized as old file
        XCTAssertFalse(categories.contains(.oldFiles), ".app files should not be categorized as old files")
    }
    
    func testOldProtectedUserFileNotCategorizedAsOld() {
        // Create an old file in a protected user directory
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let protectedFile = createFileMetadata(
            path: NSString(string: "~/Library/Keychains/login.keychain").expandingTildeInPath,
            size: 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: protectedFile)
        
        // Should NOT be categorized as old file
        XCTAssertFalse(categories.contains(.oldFiles), "Protected user files should not be categorized as old files")
    }
    
    func testOldNonSystemFileIsCategorizedAsOld() {
        // Create an old file in a non-protected location
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let userFile = createFileMetadata(
            path: "/Users/test/Documents/old-document.txt",
            size: 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: userFile)
        
        // Should be categorized as old file
        XCTAssertTrue(categories.contains(.oldFiles), "Non-system old files should be categorized as old files")
    }
    
    func testRecentSystemFileNotCategorizedAsOld() {
        // Create a recent file in a protected system directory
        let recentDate = Date().addingTimeInterval(-10 * 24 * 60 * 60) // 10 days ago
        let systemFile = createFileMetadata(
            path: "/System/Library/CoreServices/recent-system-file.dat",
            size: 1024,
            accessedDate: recentDate
        )
        
        let categories = analyzer.categorize(file: systemFile)
        
        // Should NOT be categorized as old file (not old enough)
        XCTAssertFalse(categories.contains(.oldFiles))
    }
    
    func testOldFileInApplicationsDirectoryNotCategorizedAsOld() {
        // Create an old file inside an application bundle
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let appFile = createFileMetadata(
            path: "/Applications/TextEdit.app/Contents/Resources/icon.icns",
            size: 1024,
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: appFile)
        
        // Should NOT be categorized as old file (inside .app bundle)
        XCTAssertFalse(categories.contains(.oldFiles), "Files inside .app bundles should not be categorized as old files")
    }
    
    func testOldLargeSystemFileCanBeCategorizesAsLarge() {
        // Create an old, large file in a protected system directory
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        let systemFile = createFileMetadata(
            path: "/System/Library/CoreServices/large-system-file.dat",
            size: 150 * 1024 * 1024, // 150MB
            accessedDate: oldDate
        )
        
        let categories = analyzer.categorize(file: systemFile)
        
        // Should be categorized as large file but NOT as old file
        XCTAssertTrue(categories.contains(.largeFiles), "Large system files can be categorized as large")
        XCTAssertFalse(categories.contains(.oldFiles), "System files should not be categorized as old files")
    }
    
    func testAnalyzeExcludesSystemFilesFromOldFiles() {
        let oldDate = Date().addingTimeInterval(-400 * 24 * 60 * 60) // 400 days ago
        
        let files = [
            createFileMetadata(path: "/System/Library/old-system.dat", size: 1024, accessedDate: oldDate),
            createFileMetadata(path: "/Applications/Safari.app/Contents/MacOS/Safari", size: 1024, accessedDate: oldDate),
            createFileMetadata(path: "/Users/test/Documents/old-user-file.txt", size: 1024, accessedDate: oldDate)
        ]
        
        let scanResult = ScanResult(files: files, errors: [], duration: 0)
        let result = analyzer.analyze(scanResult: scanResult)
        
        // Only the user file should be in old files category
        XCTAssertEqual(result.categorizedFiles[.oldFiles]?.count, 1)
        XCTAssertEqual(result.categorizedFiles[.oldFiles]?[0].url.lastPathComponent, "old-user-file.txt")
    }
    
    // MARK: - Log File Categorization Tests
    
    func testCategorizeLogsByApplication() {
        // Given: Log files from different applications
        let logs = [
            createFileMetadata(path: "/var/log/system.log", size: 1024, fileType: .log),
            createFileMetadata(path: "/Users/test/Library/Logs/MyApp/debug.log", size: 2048, fileType: .log),
            createFileMetadata(path: "/Users/test/Library/Logs/MyApp/error.log", size: 512, fileType: .log),
            createFileMetadata(path: "/Users/test/Library/Logs/AnotherApp/app.log", size: 4096, fileType: .log)
        ]
        
        // When: Categorizing logs by application
        let categorized = analyzer.categorizeLogsByApplication(files: logs)
        
        // Then: Should group logs by application
        XCTAssertEqual(categorized.keys.count, 3, "Should have 3 different applications")
        XCTAssertTrue(categorized.keys.contains { $0.hasPrefix("System") }, "Should have System logs")
        XCTAssertEqual(categorized["MyApp"]?.count, 2, "MyApp should have 2 logs")
        XCTAssertEqual(categorized["AnotherApp"]?.count, 1, "AnotherApp should have 1 log")
    }
    
    func testGetLogFileInfo() {
        // Given: Log files with different ages
        let recentDate = Date().addingTimeInterval(-5 * 24 * 60 * 60) // 5 days ago
        let oldDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        
        let logs = [
            createFileMetadata(
                path: "/Users/test/Library/Logs/TestApp/recent.log",
                size: 1024,
                modifiedDate: recentDate,
                fileType: .log
            ),
            createFileMetadata(
                path: "/Users/test/Library/Logs/TestApp/old.log",
                size: 2048,
                modifiedDate: oldDate,
                fileType: .log
            )
        ]
        
        // When: Getting log file info
        let logInfos = analyzer.getLogFileInfo(files: logs)
        
        // Then: Should have correct application and age information
        XCTAssertEqual(logInfos.count, 2)
        
        let recentLog = logInfos.first { $0.url.lastPathComponent == "recent.log" }
        XCTAssertNotNil(recentLog)
        XCTAssertEqual(recentLog?.application, "TestApp")
        XCTAssertEqual(recentLog?.ageDays, 5)
        XCTAssertEqual(recentLog?.size, 1024)
        
        let oldLog = logInfos.first { $0.url.lastPathComponent == "old.log" }
        XCTAssertNotNil(oldLog)
        XCTAssertEqual(oldLog?.application, "TestApp")
        XCTAssertEqual(oldLog?.ageDays, 30)
        XCTAssertEqual(oldLog?.size, 2048)
    }
    
    func testCategorizeLogsByApplicationWithSystemLogs() {
        // Given: Various system logs
        let logs = [
            createFileMetadata(path: "/var/log/system.log", size: 1024, fileType: .log),
            createFileMetadata(path: "/var/log/install.log", size: 2048, fileType: .log),
            createFileMetadata(path: "/private/var/log/wifi.log", size: 512, fileType: .log)
        ]
        
        // When: Categorizing logs by application
        let categorized = analyzer.categorizeLogsByApplication(files: logs)
        
        // Then: Should identify all as system logs with specific names
        for (appName, logFiles) in categorized {
            XCTAssertTrue(appName.hasPrefix("System"), "All should be system logs: \(appName)")
            XCTAssertGreaterThan(logFiles.count, 0)
        }
    }
    
    func testCategorizeLogsByApplicationWithApplicationSupportLogs() {
        // Given: Logs in Application Support directory
        let logs = [
            createFileMetadata(
                path: "/Users/test/Library/Application Support/MyApp/logs/debug.log",
                size: 1024,
                fileType: .log
            ),
            createFileMetadata(
                path: "/Users/test/Library/Application Support/MyApp/logs/error.log",
                size: 2048,
                fileType: .log
            )
        ]
        
        // When: Categorizing logs by application
        let categorized = analyzer.categorizeLogsByApplication(files: logs)
        
        // Then: Should extract application name from Application Support path
        XCTAssertEqual(categorized["MyApp"]?.count, 2, "Should group both logs under MyApp")
    }
    
    func testLogFileInfoCalculatesAgeFromModifiedDate() {
        // Given: A log file with a specific modified date
        let modifiedDate = Date().addingTimeInterval(-15 * 24 * 60 * 60) // 15 days ago
        let log = FileMetadata(
            url: URL(fileURLWithPath: "/var/log/test.log"),
            size: 1024,
            createdDate: Date(),
            modifiedDate: modifiedDate,
            accessedDate: Date(),
            fileType: .log,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
        
        // When: Creating LogFileInfo
        let logInfo = LogFileInfo.from(fileMetadata: log)
        
        // Then: Should calculate age from modified date
        XCTAssertEqual(logInfo.ageDays, 15)
    }
    
    func testCategorizeLogsByApplicationEmptyArray() {
        // Given: Empty array of files
        let logs: [FileMetadata] = []
        
        // When: Categorizing logs by application
        let categorized = analyzer.categorizeLogsByApplication(files: logs)
        
        // Then: Should return empty dictionary
        XCTAssertEqual(categorized.count, 0)
    }
    
    func testGetLogFileInfoEmptyArray() {
        // Given: Empty array of files
        let logs: [FileMetadata] = []
        
        // When: Getting log file info
        let logInfos = analyzer.getLogFileInfo(files: logs)
        
        // Then: Should return empty array
        XCTAssertEqual(logInfos.count, 0)
    }
    
    // MARK: - Downloads File Categorization Tests
    
    func testCategorizeDownloadsByType() {
        // Given: Files in Downloads folder with different types
        let downloads = [
            createFileMetadata(path: "/Users/test/Downloads/document.pdf", size: 1024),
            createFileMetadata(path: "/Users/test/Downloads/photo.jpg", size: 2048),
            createFileMetadata(path: "/Users/test/Downloads/archive.zip", size: 4096),
            createFileMetadata(path: "/Users/test/Downloads/installer.dmg", size: 8192),
            createFileMetadata(path: "/Users/test/Downloads/other.xyz", size: 512)
        ]
        
        // When: Categorizing downloads by type
        let categorized = analyzer.categorizeDownloadsByType(files: downloads)
        
        // Then: Should group by DownloadsFileType
        XCTAssertEqual(categorized[.document]?.count, 1)
        XCTAssertEqual(categorized[.image]?.count, 1)
        XCTAssertEqual(categorized[.archive]?.count, 1)
        XCTAssertEqual(categorized[.installer]?.count, 1)
        XCTAssertEqual(categorized[.other]?.count, 1)
    }
    
    func testGetDownloadsFileInfo() {
        // Given: Downloads files with different ages
        let recentDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        
        let downloads = [
            createFileMetadata(
                path: "/Users/test/Downloads/recent.pdf",
                size: 1024,
                accessedDate: recentDate
            ),
            createFileMetadata(
                path: "/Users/test/Downloads/old.pdf",
                size: 2048,
                accessedDate: oldDate
            )
        ]
        
        // When: Getting downloads file info
        let downloadInfos = analyzer.getDownloadsFileInfo(files: downloads)
        
        // Then: Should have correct type and age information
        XCTAssertEqual(downloadInfos.count, 2)
        
        let recentDownload = downloadInfos.first { $0.metadata.url.lastPathComponent == "recent.pdf" }
        XCTAssertNotNil(recentDownload)
        XCTAssertEqual(recentDownload?.downloadsType, .document)
        XCTAssertFalse(recentDownload?.isOldDownload ?? true, "30 days is not old enough")
        
        let oldDownload = downloadInfos.first { $0.metadata.url.lastPathComponent == "old.pdf" }
        XCTAssertNotNil(oldDownload)
        XCTAssertEqual(oldDownload?.downloadsType, .document)
        XCTAssertTrue(oldDownload?.isOldDownload ?? false, "100 days should be flagged as old")
    }
    
    func testFilterOldDownloads() {
        // Given: Downloads with various ages
        let recentDate = Date().addingTimeInterval(-30 * 24 * 60 * 60) // 30 days ago
        let borderlineDate = Date().addingTimeInterval(-90 * 24 * 60 * 60) // Exactly 90 days ago
        let oldDate = Date().addingTimeInterval(-100 * 24 * 60 * 60) // 100 days ago
        
        let downloads = [
            createFileMetadata(path: "/Users/test/Downloads/recent.pdf", size: 1024, accessedDate: recentDate),
            createFileMetadata(path: "/Users/test/Downloads/borderline.pdf", size: 1024, accessedDate: borderlineDate),
            createFileMetadata(path: "/Users/test/Downloads/old.pdf", size: 1024, accessedDate: oldDate)
        ]
        
        // When: Filtering old downloads
        let filtered = analyzer.filterOldDownloads(files: downloads)
        
        // Then: Should only include files older than 90 days
        XCTAssertEqual(filtered.count, 2, "Should include borderline and old files")
        XCTAssertTrue(filtered.contains { $0.url.lastPathComponent == "borderline.pdf" })
        XCTAssertTrue(filtered.contains { $0.url.lastPathComponent == "old.pdf" })
        XCTAssertFalse(filtered.contains { $0.url.lastPathComponent == "recent.pdf" })
    }
    
    func testDownloadsFileTypeCategorizationByExtension() {
        // Given: Various file types in Downloads
        let testCases: [(String, DownloadsFileType)] = [
            // Documents
            ("document.pdf", .document),
            ("spreadsheet.xlsx", .document),
            ("presentation.pptx", .document),
            ("text.txt", .document),
            ("notes.rtf", .document),
            // Images
            ("photo.jpg", .image),
            ("screenshot.png", .image),
            ("graphic.svg", .image),
            ("picture.heic", .image),
            // Archives
            ("backup.zip", .archive),
            ("source.tar.gz", .archive),
            ("compressed.7z", .archive),
            ("disk.iso", .archive),
            // Installers
            ("app.dmg", .installer),
            ("package.pkg", .installer),
            ("windows.exe", .installer),
            // Other
            ("unknown.xyz", .other)
        ]
        
        for (filename, expectedType) in testCases {
            let file = createFileMetadata(path: "/Users/test/Downloads/\(filename)", size: 1024)
            let downloadInfo = DownloadsFileInfo.from(fileMetadata: file)
            
            XCTAssertEqual(
                downloadInfo.downloadsType,
                expectedType,
                "File \(filename) should be categorized as \(expectedType)"
            )
        }
    }
    
    func testCategorizeDownloadsByTypeGroupsCorrectly() {
        // Given: Multiple files of each type
        let downloads = [
            createFileMetadata(path: "/Users/test/Downloads/doc1.pdf", size: 1024),
            createFileMetadata(path: "/Users/test/Downloads/doc2.docx", size: 2048),
            createFileMetadata(path: "/Users/test/Downloads/img1.jpg", size: 3072),
            createFileMetadata(path: "/Users/test/Downloads/img2.png", size: 4096),
            createFileMetadata(path: "/Users/test/Downloads/archive1.zip", size: 5120),
            createFileMetadata(path: "/Users/test/Downloads/archive2.tar.gz", size: 6144)
        ]
        
        // When: Categorizing downloads by type
        let categorized = analyzer.categorizeDownloadsByType(files: downloads)
        
        // Then: Should have correct counts for each type
        XCTAssertEqual(categorized[.document]?.count, 2, "Should have 2 documents")
        XCTAssertEqual(categorized[.image]?.count, 2, "Should have 2 images")
        XCTAssertEqual(categorized[.archive]?.count, 2, "Should have 2 archives")
        
        // Verify sizes are preserved
        let docSizes = categorized[.document]?.map { $0.metadata.size }.sorted() ?? []
        XCTAssertEqual(docSizes, [1024, 2048])
    }
    
    func testFilterOldDownloadsExactly90Days() {
        // Given: A file accessed exactly 90 days ago (to the second)
        let exactlyNinetyDays = Date().addingTimeInterval(-90 * 24 * 60 * 60)
        let file = createFileMetadata(
            path: "/Users/test/Downloads/file.pdf",
            size: 1024,
            accessedDate: exactlyNinetyDays
        )
        
        // When: Filtering old downloads
        let filtered = analyzer.filterOldDownloads(files: [file])
        
        // Then: Should be included (age > 90 days threshold)
        XCTAssertEqual(filtered.count, 1, "File exactly 90 days old should be included")
    }
    
    func testCategorizeDownloadsByTypeEmptyArray() {
        // Given: Empty array
        let downloads: [FileMetadata] = []
        
        // When: Categorizing downloads by type
        let categorized = analyzer.categorizeDownloadsByType(files: downloads)
        
        // Then: Should return empty dictionary
        XCTAssertEqual(categorized.count, 0)
    }
    
    func testGetDownloadsFileInfoEmptyArray() {
        // Given: Empty array
        let downloads: [FileMetadata] = []
        
        // When: Getting downloads file info
        let downloadInfos = analyzer.getDownloadsFileInfo(files: downloads)
        
        // Then: Should return empty array
        XCTAssertEqual(downloadInfos.count, 0)
    }
    
    func testFilterOldDownloadsEmptyArray() {
        // Given: Empty array
        let downloads: [FileMetadata] = []
        
        // When: Filtering old downloads
        let filtered = analyzer.filterOldDownloads(files: downloads)
        
        // Then: Should return empty array
        XCTAssertEqual(filtered.count, 0)
    }
    
    func testDownloadsOldFlagThreshold() {
        // Given: Files at various ages around the 90-day threshold
        let ninetyDaysInSeconds: TimeInterval = 90 * 24 * 60 * 60
        
        let testCases: [(description: String, ageSeconds: TimeInterval, shouldBeOld: Bool)] = [
            ("89 days", 89 * 24 * 60 * 60, false),   // Just under threshold
            ("90 days - 1 second", ninetyDaysInSeconds - 1, false),   // Just under threshold
            ("90 days + 1 second", ninetyDaysInSeconds + 1, true),    // Just over threshold
            ("100 days", 100 * 24 * 60 * 60, true),   // Well over threshold
            ("30 days", 30 * 24 * 60 * 60, false),   // Well under threshold
            ("365 days", 365 * 24 * 60 * 60, true)    // Very old
        ]
        
        for testCase in testCases {
            let date = Date().addingTimeInterval(-testCase.ageSeconds)
            let file = createFileMetadata(
                path: "/Users/test/Downloads/file.pdf",
                size: 1024,
                accessedDate: date
            )
            
            let downloadInfo = DownloadsFileInfo.from(fileMetadata: file)
            
            XCTAssertEqual(
                downloadInfo.isOldDownload,
                testCase.shouldBeOld,
                "File \(testCase.description) old should \(testCase.shouldBeOld ? "" : "not ")be flagged as old"
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func createFileMetadata(
        path: String,
        size: Int64,
        accessedDate: Date = Date(),
        modifiedDate: Date? = nil,
        fileType: FileType = .other("")
    ) -> FileMetadata {
        let url = URL(fileURLWithPath: path)
        return FileMetadata(
            url: url,
            size: size,
            createdDate: Date(),
            modifiedDate: modifiedDate ?? Date(),
            accessedDate: accessedDate,
            fileType: fileType,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
}
