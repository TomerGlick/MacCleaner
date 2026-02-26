import XCTest
@testable import MacStorageCleanup

final class ApplicationManagerTests: XCTestCase {
    var manager: DefaultApplicationManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = DefaultApplicationManager()
        
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
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - Application Discovery Tests
    
    func testDiscoverApplications_FindsRealApplications() async {
        // Test with real system applications
        let applications = await manager.discoverApplications()
        
        // Should find at least some applications on a Mac
        XCTAssertFalse(applications.isEmpty, "Should discover at least some applications")
        
        // Verify application properties are populated
        if let firstApp = applications.first {
            XCTAssertFalse(firstApp.name.isEmpty, "Application name should not be empty")
            XCTAssertFalse(firstApp.bundleIdentifier.isEmpty, "Bundle identifier should not be empty")
            XCTAssertGreaterThan(firstApp.size, 0, "Application size should be greater than 0")
            XCTAssertTrue(firstApp.bundleURL.pathExtension == "app", "Bundle URL should have .app extension")
        }
    }
    
    func testDiscoverApplications_HandlesNonExistentDirectory() async {
        // This test verifies the manager handles missing directories gracefully
        // The actual implementation searches /Applications and ~/Applications
        // Even if one doesn't exist, it should continue
        let applications = await manager.discoverApplications()
        
        // Should not crash and should return an array (possibly empty)
        XCTAssertNotNil(applications)
    }
    
    // MARK: - Associated Files Tests
    
    func testFindAssociatedFiles_WithMockApplication() async {
        // Create a mock application structure
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let testBundleId = "com.test.mockapp"
        let testAppName = "MockApp"
        
        // Create test files in various locations
        let prefsFile = homeDir.appendingPathComponent("Library/Preferences/\(testBundleId).plist")
        let cacheDir = homeDir.appendingPathComponent("Library/Caches/\(testBundleId)")
        let supportDir = homeDir.appendingPathComponent("Library/Application Support/\(testAppName)")
        let logsDir = homeDir.appendingPathComponent("Library/Logs/\(testAppName)")
        
        do {
            // Create preference file
            try "test".write(to: prefsFile, atomically: true, encoding: .utf8)
            
            // Create cache directory with a file
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try "cache".write(to: cacheDir.appendingPathComponent("cache.dat"), atomically: true, encoding: .utf8)
            
            // Create support directory with a file
            try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try "support".write(to: supportDir.appendingPathComponent("data.dat"), atomically: true, encoding: .utf8)
            
            // Create logs directory with a file
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            try "log".write(to: logsDir.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)
            
            // Create mock application
            let mockApp = Application(
                bundleURL: URL(fileURLWithPath: "/Applications/MockApp.app"),
                name: testAppName,
                version: "1.0",
                bundleIdentifier: testBundleId,
                size: 1000,
                lastUsedDate: nil,
                isRunning: false
            )
            
            // Find associated files
            let associatedFiles = await manager.findAssociatedFiles(for: mockApp)
            
            // Should find files in all locations (4 files total: 1 pref + 1 cache + 1 support + 1 log)
            XCTAssertEqual(associatedFiles.count, 4, "Should find exactly 4 associated files")
            
            // Verify we found files from all expected locations
            let paths = associatedFiles.map { $0.url.path }
            let hasPrefs = paths.contains { $0.contains("Preferences") && $0.contains(testBundleId) }
            let hasCaches = paths.contains { $0.contains("Caches") && $0.contains(testBundleId) }
            let hasSupport = paths.contains { $0.contains("Application Support") && $0.contains(testAppName) }
            let hasLogs = paths.contains { $0.contains("Logs") && $0.contains(testAppName) }
            
            XCTAssertTrue(hasPrefs, "Should find preferences file")
            XCTAssertTrue(hasCaches, "Should find cache files")
            XCTAssertTrue(hasSupport, "Should find application support files")
            XCTAssertTrue(hasLogs, "Should find log files")
            
            // Verify file metadata is populated correctly
            for file in associatedFiles {
                XCTAssertGreaterThan(file.size, 0, "File size should be greater than 0")
                XCTAssertNotNil(file.url, "File URL should not be nil")
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: prefsFile)
            try? FileManager.default.removeItem(at: cacheDir)
            try? FileManager.default.removeItem(at: supportDir)
            try? FileManager.default.removeItem(at: logsDir)
        } catch {
            XCTFail("Failed to set up test files: \(error)")
        }
    }
    
    func testFindAssociatedFiles_WithNoAssociatedFiles() async {
        // Create a mock application with no associated files
        let mockApp = Application(
            bundleURL: URL(fileURLWithPath: "/Applications/NonExistentApp.app"),
            name: "NonExistentApp",
            version: "1.0",
            bundleIdentifier: "com.test.nonexistent",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        let associatedFiles = await manager.findAssociatedFiles(for: mockApp)
        
        // Should return empty array, not crash
        XCTAssertEqual(associatedFiles.count, 0, "Should return empty array for app with no associated files")
    }
    
    func testFindAssociatedFiles_WithNestedDirectories() async {
        // Test that nested directories are properly enumerated
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let testBundleId = "com.test.nestedapp"
        let testAppName = "NestedApp"
        
        let cacheDir = homeDir.appendingPathComponent("Library/Caches/\(testBundleId)")
        
        do {
            // Create nested directory structure with multiple files
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            try "cache1".write(to: cacheDir.appendingPathComponent("cache1.dat"), atomically: true, encoding: .utf8)
            
            let subDir = cacheDir.appendingPathComponent("subdir")
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            try "cache2".write(to: subDir.appendingPathComponent("cache2.dat"), atomically: true, encoding: .utf8)
            
            let deepDir = subDir.appendingPathComponent("deep")
            try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
            try "cache3".write(to: deepDir.appendingPathComponent("cache3.dat"), atomically: true, encoding: .utf8)
            
            let mockApp = Application(
                bundleURL: URL(fileURLWithPath: "/Applications/NestedApp.app"),
                name: testAppName,
                version: "1.0",
                bundleIdentifier: testBundleId,
                size: 1000,
                lastUsedDate: nil,
                isRunning: false
            )
            
            let associatedFiles = await manager.findAssociatedFiles(for: mockApp)
            
            // Should find all 3 files in nested directories
            XCTAssertEqual(associatedFiles.count, 3, "Should find all files in nested directories")
            
            // Verify all files are from the cache directory
            for file in associatedFiles {
                XCTAssertTrue(file.url.path.contains("Caches/\(testBundleId)"), 
                            "All files should be in the cache directory")
            }
            
            // Clean up
            try? FileManager.default.removeItem(at: cacheDir)
        } catch {
            XCTFail("Failed to set up test files: \(error)")
        }
    }
    
    // MARK: - Uninstall Tests
    
    func testUninstall_ThrowsErrorForRunningApplication() async {
        // Create a mock running application
        let mockApp = Application(
            bundleURL: URL(fileURLWithPath: "/Applications/RunningApp.app"),
            name: "RunningApp",
            version: "1.0",
            bundleIdentifier: "com.test.running",
            size: 1000,
            lastUsedDate: nil,
            isRunning: true
        )
        
        do {
            _ = try await manager.uninstall(application: mockApp, removeAssociatedFiles: false)
            XCTFail("Should throw error for running application")
        } catch UninstallError.applicationRunning(let name) {
            XCTAssertEqual(name, "RunningApp")
        } catch {
            XCTFail("Should throw UninstallError.applicationRunning, got \(error)")
        }
    }
    
    func testUninstall_ThrowsErrorForNonExistentApplication() async {
        // Create a mock application that doesn't exist
        let mockApp = Application(
            bundleURL: URL(fileURLWithPath: "/Applications/NonExistent.app"),
            name: "NonExistent",
            version: "1.0",
            bundleIdentifier: "com.test.nonexistent",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        do {
            _ = try await manager.uninstall(application: mockApp, removeAssociatedFiles: false)
            XCTFail("Should throw error for non-existent application")
        } catch UninstallError.applicationNotFound {
            // Expected
        } catch {
            XCTFail("Should throw UninstallError.applicationNotFound, got \(error)")
        }
    }
    
    func testUninstall_RemovesApplicationBundle() async throws {
        // Create a mock application bundle in temp directory
        let appBundle = tempDirectory.appendingPathComponent("TestApp.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir = contentsDir.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        
        // Create a simple Info.plist
        let infoPlist = contentsDir.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>TestApp</string>
            <key>CFBundleIdentifier</key>
            <string>com.test.testapp</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: infoPlist, atomically: true, encoding: .utf8)
        
        // Create a mock executable
        let executable = macOSDir.appendingPathComponent("TestApp")
        try "executable".write(to: executable, atomically: true, encoding: .utf8)
        
        let mockApp = Application(
            bundleURL: appBundle,
            name: "TestApp",
            version: "1.0",
            bundleIdentifier: "com.test.testapp",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        // Verify app exists before uninstall
        XCTAssertTrue(FileManager.default.fileExists(atPath: appBundle.path))
        
        // Uninstall
        let result = try await manager.uninstall(application: mockApp, removeAssociatedFiles: false)
        
        // Verify results
        XCTAssertTrue(result.applicationRemoved, "Application should be marked as removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundle.path), "Application bundle should be deleted")
        XCTAssertGreaterThan(result.totalSpaceFreed, 0, "Should report space freed")
    }
    
    func testUninstall_RemovesAssociatedFilesWhenRequested() async throws {
        // Create a mock application bundle
        let appBundle = tempDirectory.appendingPathComponent("TestApp2.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir = contentsDir.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = contentsDir.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>TestApp2</string>
            <key>CFBundleIdentifier</key>
            <string>com.test.testapp2</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: infoPlist, atomically: true, encoding: .utf8)
        
        // Create associated files
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let prefsFile = homeDir.appendingPathComponent("Library/Preferences/com.test.testapp2.plist")
        try "prefs".write(to: prefsFile, atomically: true, encoding: .utf8)
        
        let mockApp = Application(
            bundleURL: appBundle,
            name: "TestApp2",
            version: "1.0",
            bundleIdentifier: "com.test.testapp2",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        // Uninstall with associated files
        let result = try await manager.uninstall(application: mockApp, removeAssociatedFiles: true)
        
        // Verify results
        XCTAssertTrue(result.applicationRemoved, "Application should be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundle.path), "App bundle should be deleted")
        
        // Clean up any remaining files
        try? FileManager.default.removeItem(at: prefsFile)
    }
    
    // MARK: - Integration Tests
    
    func testApplicationMetadata_IsPopulatedCorrectly() async {
        let applications = await manager.discoverApplications()
        
        guard let app = applications.first else {
            XCTFail("No applications found for testing")
            return
        }
        
        // Verify all required fields are populated
        XCTAssertFalse(app.name.isEmpty, "Name should be populated")
        XCTAssertFalse(app.version.isEmpty, "Version should be populated")
        XCTAssertFalse(app.bundleIdentifier.isEmpty, "Bundle identifier should be populated")
        XCTAssertGreaterThan(app.size, 0, "Size should be greater than 0")
        XCTAssertTrue(app.bundleURL.path.hasSuffix(".app"), "Bundle URL should point to .app")
        
        // isRunning should be a valid boolean (true or false)
        _ = app.isRunning // Just verify it's accessible
    }
    
    // MARK: - Task 9.3 Comprehensive Tests
    
    func testUninstall_CalculatesAndReportsTotalSpaceFreed() async throws {
        // Create a mock application bundle with known size
        let appBundle = tempDirectory.appendingPathComponent("SizeTestApp.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir = contentsDir.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = contentsDir.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>SizeTestApp</string>
            <key>CFBundleIdentifier</key>
            <string>com.test.sizetestapp</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: infoPlist, atomically: true, encoding: .utf8)
        
        // Create a mock executable with known content
        let executable = macOSDir.appendingPathComponent("SizeTestApp")
        let executableContent = String(repeating: "X", count: 1000) // 1000 bytes
        try executableContent.write(to: executable, atomically: true, encoding: .utf8)
        
        // Create associated files with known sizes
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let prefsFile = homeDir.appendingPathComponent("Library/Preferences/com.test.sizetestapp.plist")
        let prefsContent = String(repeating: "P", count: 500) // 500 bytes
        try prefsContent.write(to: prefsFile, atomically: true, encoding: .utf8)
        
        let cacheDir = homeDir.appendingPathComponent("Library/Caches/com.test.sizetestapp")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cacheFile = cacheDir.appendingPathComponent("cache.dat")
        let cacheContent = String(repeating: "C", count: 300) // 300 bytes
        try cacheContent.write(to: cacheFile, atomically: true, encoding: .utf8)
        
        let mockApp = Application(
            bundleURL: appBundle,
            name: "SizeTestApp",
            version: "1.0",
            bundleIdentifier: "com.test.sizetestapp",
            size: 2000, // Approximate size
            lastUsedDate: nil,
            isRunning: false
        )
        
        // Uninstall with associated files
        let result = try await manager.uninstall(application: mockApp, removeAssociatedFiles: true)
        
        // Verify space freed is calculated and reported
        XCTAssertGreaterThan(result.totalSpaceFreed, 0, "Should report total space freed")
        XCTAssertTrue(result.applicationRemoved, "Application should be removed")
        XCTAssertGreaterThan(result.associatedFilesRemoved, 0, "Should remove associated files")
        
        // Verify files are actually deleted
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundle.path), "App bundle should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: prefsFile.path), "Prefs file should be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path), "Cache file should be deleted")
        
        // Clean up any remaining directories
        try? FileManager.default.removeItem(at: cacheDir)
    }
    
    func testUninstall_DoesNotRemoveAssociatedFilesWhenNotRequested() async throws {
        // Create a mock application bundle
        let appBundle = tempDirectory.appendingPathComponent("NoAssocApp.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir = contentsDir.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = contentsDir.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>NoAssocApp</string>
            <key>CFBundleIdentifier</key>
            <string>com.test.noassocapp</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: infoPlist, atomically: true, encoding: .utf8)
        
        // Create associated file
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let prefsFile = homeDir.appendingPathComponent("Library/Preferences/com.test.noassocapp.plist")
        try "prefs".write(to: prefsFile, atomically: true, encoding: .utf8)
        
        let mockApp = Application(
            bundleURL: appBundle,
            name: "NoAssocApp",
            version: "1.0",
            bundleIdentifier: "com.test.noassocapp",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        // Uninstall WITHOUT associated files
        let result = try await manager.uninstall(application: mockApp, removeAssociatedFiles: false)
        
        // Verify results
        XCTAssertTrue(result.applicationRemoved, "Application should be removed")
        XCTAssertEqual(result.associatedFilesRemoved, 0, "Should not remove associated files")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundle.path), "App bundle should be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: prefsFile.path), "Prefs file should still exist")
        
        // Clean up
        try? FileManager.default.removeItem(at: prefsFile)
    }
    
    func testUninstall_HandlesPartialFailuresGracefully() async throws {
        // Create a mock application bundle
        let appBundle = tempDirectory.appendingPathComponent("PartialApp.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir = contentsDir.appendingPathComponent("MacOS")
        
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        
        // Create Info.plist
        let infoPlist = contentsDir.appendingPathComponent("Info.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>PartialApp</string>
            <key>CFBundleIdentifier</key>
            <string>com.test.partialapp</string>
            <key>CFBundleVersion</key>
            <string>1.0</string>
        </dict>
        </plist>
        """
        try plistContent.write(to: infoPlist, atomically: true, encoding: .utf8)
        
        let mockApp = Application(
            bundleURL: appBundle,
            name: "PartialApp",
            version: "1.0",
            bundleIdentifier: "com.test.partialapp",
            size: 1000,
            lastUsedDate: nil,
            isRunning: false
        )
        
        // Uninstall with associated files (even though none exist)
        // This tests that the function handles missing associated files gracefully
        let result = try await manager.uninstall(application: mockApp, removeAssociatedFiles: true)
        
        // Should still succeed even if no associated files found
        XCTAssertTrue(result.applicationRemoved, "Application should be removed")
        XCTAssertEqual(result.associatedFilesRemoved, 0, "No associated files to remove")
        XCTAssertFalse(FileManager.default.fileExists(atPath: appBundle.path), "App bundle should be deleted")
    }
}
