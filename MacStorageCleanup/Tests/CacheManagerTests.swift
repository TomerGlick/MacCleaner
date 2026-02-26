import XCTest
@testable import MacStorageCleanup

final class CacheManagerTests: XCTestCase {
    var cacheManager: DefaultCacheManager!
    var safeListManager: SafeListManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        safeListManager = DefaultSafeListManager()
        cacheManager = DefaultCacheManager(safeListManager: safeListManager)
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    // MARK: - Browser Cache Path Tests
    
    func testBrowserCachePathMapping() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        XCTAssertEqual(Browser.safari.cachePath, "\(homeDir)/Library/Caches/com.apple.Safari")
        XCTAssertEqual(Browser.chrome.cachePath, "\(homeDir)/Library/Caches/Google/Chrome")
        XCTAssertEqual(Browser.firefox.cachePath, "\(homeDir)/Library/Caches/Firefox")
        XCTAssertEqual(Browser.edge.cachePath, "\(homeDir)/Library/Caches/Microsoft Edge")
    }
    
    func testAllBrowsersHaveCachePaths() {
        for browser in Browser.allCases {
            let cachePath = browser.cachePath
            XCTAssertFalse(cachePath.isEmpty, "Browser \(browser.rawValue) should have a cache path")
            XCTAssertTrue(cachePath.contains("Library/Caches"), "Cache path should be in Library/Caches")
        }
    }
    
    // MARK: - System Cache Tests
    
    func testFindSystemCachesReturnsArray() async {
        let caches = await cacheManager.findSystemCaches()
        
        // Should return an array (may be empty if no caches exist)
        XCTAssertNotNil(caches)
    }
    
    func testFindSystemCachesExcludesProtectedFiles() async {
        let caches = await cacheManager.findSystemCaches()
        
        // Verify no protected files are included
        for cache in caches {
            XCTAssertFalse(safeListManager.isProtected(url: cache.url),
                          "Protected file should not be in cache results: \(cache.url.path)")
        }
    }
    
    // MARK: - Application Cache Tests
    
    func testFindApplicationCachesReturnsArray() async {
        let caches = await cacheManager.findApplicationCaches()
        
        // Should return an array (may be empty if no caches exist)
        XCTAssertNotNil(caches)
    }
    
    func testFindApplicationCachesExcludesProtectedFiles() async {
        let caches = await cacheManager.findApplicationCaches()
        
        // Verify no protected files are included
        for cache in caches {
            XCTAssertFalse(safeListManager.isProtected(url: cache.url),
                          "Protected file should not be in cache results: \(cache.url.path)")
        }
    }
    
    // MARK: - Browser Cache Tests
    
    func testFindBrowserCachesReturnsArray() async {
        let browserCaches = await cacheManager.findBrowserCaches()
        
        // Should return an array (may be empty if browsers not installed)
        XCTAssertNotNil(browserCaches)
    }
    
    func testFindBrowserCachesOnlyIncludesExistingBrowsers() async {
        let browserCaches = await cacheManager.findBrowserCaches()
        
        // Verify each returned browser cache has a valid directory
        for browserCache in browserCaches {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: browserCache.cacheLocation.path,
                isDirectory: &isDirectory
            )
            XCTAssertTrue(exists && isDirectory.boolValue,
                         "Browser cache location should exist and be a directory: \(browserCache.cacheLocation.path)")
        }
    }
    
    func testBrowserCacheSizeIsNonNegative() async {
        let browserCaches = await cacheManager.findBrowserCaches()
        
        for browserCache in browserCaches {
            XCTAssertGreaterThanOrEqual(browserCache.size, 0,
                                       "Browser cache size should be non-negative")
        }
    }
    
    // MARK: - Clear Cache Tests
    
    func testClearCachesWithEmptyArray() async throws {
        let result = try await cacheManager.clearCaches(caches: [])
        
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertEqual(result.spaceFreed, 0)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertNil(result.backupLocation)
    }
    
    func testClearCachesSkipsProtectedFiles() async throws {
        // Create a mock protected file
        let protectedPath = "/System/Library/test.cache"
        let protectedFile = FileMetadata(
            url: URL(fileURLWithPath: protectedPath),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache,
            isInUse: false
        )
        
        let result = try await cacheManager.clearCaches(caches: [protectedFile])
        
        XCTAssertEqual(result.filesRemoved, 0, "Protected files should not be removed")
        XCTAssertEqual(result.errors.count, 1, "Should have one error for protected file")
        
        if case .fileProtected(let path) = result.errors.first {
            XCTAssertEqual(path, protectedPath)
        } else {
            XCTFail("Expected fileProtected error")
        }
    }
    
    func testClearCachesSkipsInUseFiles() async throws {
        // Create a mock in-use file
        let inUsePath = tempDirectory.appendingPathComponent("inuse.cache").path
        let inUseFile = FileMetadata(
            url: URL(fileURLWithPath: inUsePath),
            size: 1024,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache,
            isInUse: true
        )
        
        let result = try await cacheManager.clearCaches(caches: [inUseFile])
        
        XCTAssertEqual(result.filesRemoved, 0, "In-use files should not be removed")
        XCTAssertEqual(result.errors.count, 1, "Should have one error for in-use file")
        
        if case .fileInUse(let path) = result.errors.first {
            XCTAssertEqual(path, inUsePath)
        } else {
            XCTFail("Expected fileInUse error")
        }
    }
    
    func testClearCachesRemovesValidFiles() async throws {
        // Create a test cache file
        let testFile = tempDirectory.appendingPathComponent("test.cache")
        let testData = "test cache data".data(using: .utf8)!
        try testData.write(to: testFile)
        
        let fileSize = Int64(testData.count)
        let cacheFile = FileMetadata(
            url: testFile,
            size: fileSize,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache,
            isInUse: false
        )
        
        let result = try await cacheManager.clearCaches(caches: [cacheFile])
        
        XCTAssertEqual(result.filesRemoved, 1, "Should remove one file")
        XCTAssertEqual(result.spaceFreed, fileSize, "Should free correct amount of space")
        XCTAssertTrue(result.errors.isEmpty, "Should have no errors")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path),
                      "File should be deleted")
    }
    
    func testClearCachesHandlesMultipleFiles() async throws {
        // Create multiple test cache files
        var cacheFiles: [FileMetadata] = []
        var totalSize: Int64 = 0
        
        for i in 0..<3 {
            let testFile = tempDirectory.appendingPathComponent("test\(i).cache")
            let testData = "test cache data \(i)".data(using: .utf8)!
            try testData.write(to: testFile)
            
            let fileSize = Int64(testData.count)
            totalSize += fileSize
            
            let cacheFile = FileMetadata(
                url: testFile,
                size: fileSize,
                createdDate: Date(),
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                isInUse: false
            )
            cacheFiles.append(cacheFile)
        }
        
        let result = try await cacheManager.clearCaches(caches: cacheFiles)
        
        XCTAssertEqual(result.filesRemoved, 3, "Should remove all three files")
        XCTAssertEqual(result.spaceFreed, totalSize, "Should free correct total space")
        XCTAssertTrue(result.errors.isEmpty, "Should have no errors")
    }
    
    // MARK: - Directory Structure Preservation Tests
    
    func testClearCachesPreservesDirectoryStructure() async throws {
        // Create a cache directory structure with files
        let cacheDir = tempDirectory.appendingPathComponent("TestApp.cache")
        let subDir = cacheDir.appendingPathComponent("subdirectory")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        
        // Create files in the directory structure
        let file1 = cacheDir.appendingPathComponent("cache1.dat")
        let file2 = subDir.appendingPathComponent("cache2.dat")
        
        let testData = "cache data".data(using: .utf8)!
        try testData.write(to: file1)
        try testData.write(to: file2)
        
        let fileSize = Int64(testData.count)
        
        // Create metadata for the files
        let cacheFiles = [
            FileMetadata(
                url: file1,
                size: fileSize,
                createdDate: Date(),
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                isInUse: false
            ),
            FileMetadata(
                url: file2,
                size: fileSize,
                createdDate: Date(),
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                isInUse: false
            )
        ]
        
        // Clear the caches
        let result = try await cacheManager.clearCaches(caches: cacheFiles)
        
        // Verify files were removed
        XCTAssertEqual(result.filesRemoved, 2, "Should remove both files")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path),
                      "File 1 should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path),
                      "File 2 should be deleted")
        
        // Verify directory structure is preserved
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory),
                     "Parent cache directory should still exist")
        XCTAssertTrue(isDirectory.boolValue, "Parent cache directory should be a directory")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: subDir.path, isDirectory: &isDirectory),
                     "Subdirectory should still exist")
        XCTAssertTrue(isDirectory.boolValue, "Subdirectory should be a directory")
    }
    
    func testClearCachesSelectiveRemoval() async throws {
        // Create multiple cache files in a directory
        let cacheDir = tempDirectory.appendingPathComponent("SelectiveTest.cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let file1 = cacheDir.appendingPathComponent("keep.dat")
        let file2 = cacheDir.appendingPathComponent("remove.dat")
        
        let testData = "cache data".data(using: .utf8)!
        try testData.write(to: file1)
        try testData.write(to: file2)
        
        let fileSize = Int64(testData.count)
        
        // Only select file2 for removal
        let cacheFiles = [
            FileMetadata(
                url: file2,
                size: fileSize,
                createdDate: Date(),
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                isInUse: false
            )
        ]
        
        // Clear only the selected cache
        let result = try await cacheManager.clearCaches(caches: cacheFiles)
        
        // Verify only selected file was removed
        XCTAssertEqual(result.filesRemoved, 1, "Should remove only one file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1.path),
                     "Non-selected file should still exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path),
                      "Selected file should be deleted")
        
        // Verify directory structure is preserved
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDirectory),
                     "Cache directory should still exist")
        XCTAssertTrue(isDirectory.boolValue, "Cache directory should be a directory")
    }
}
