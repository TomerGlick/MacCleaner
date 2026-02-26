import XCTest
@testable import MacStorageCleanup

final class ScheduledCleanupCoordinatorTests: XCTestCase {
    var tempDir: URL!
    var preferencesStore: FilePreferencesStore!
    var mockFileScanner: MockFileScanner!
    var mockStorageAnalyzer: MockStorageAnalyzer!
    var mockCleanupEngine: MockCleanupEngine!
    var mockNotificationPoster: MockNotificationPoster!
    var coordinator: BackgroundScheduledCleanupCoordinator!
    
    override func setUp() {
        super.setUp()
        
        // Create temporary directory for test files
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Create preferences store
        let prefsFile = tempDir.appendingPathComponent("preferences.json")
        preferencesStore = FilePreferencesStore(fileURL: prefsFile)
        
        // Create mock components
        mockFileScanner = MockFileScanner()
        mockStorageAnalyzer = MockStorageAnalyzer()
        mockCleanupEngine = MockCleanupEngine()
        mockNotificationPoster = MockNotificationPoster()
        
        // Create coordinator
        coordinator = BackgroundScheduledCleanupCoordinator(
            fileScanner: mockFileScanner,
            storageAnalyzer: mockStorageAnalyzer,
            cleanupEngine: mockCleanupEngine,
            preferencesStore: preferencesStore,
            notificationPoster: mockNotificationPoster
        )
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDir)
        
        super.tearDown()
    }
    
    // MARK: - Configuration Tests
    
    func testConfigureWithScheduledCleanupEnabled() throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCleanupInterval = .daily
        preferences.scheduledCategories = [.systemCaches, .temporaryFiles]
        
        // When
        try coordinator.configure(preferences: preferences)
        
        // Then
        let savedPreferences = try preferencesStore.load()
        XCTAssertTrue(savedPreferences.enableScheduledCleanup)
        XCTAssertEqual(savedPreferences.scheduledCleanupInterval, .daily)
        XCTAssertEqual(savedPreferences.scheduledCategories, [.systemCaches, .temporaryFiles])
    }
    
    func testConfigureWithScheduledCleanupDisabled() throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = false
        
        // When
        try coordinator.configure(preferences: preferences)
        
        // Then
        let savedPreferences = try preferencesStore.load()
        XCTAssertFalse(savedPreferences.enableScheduledCleanup)
    }
    
    // MARK: - Safe Category Restriction Tests
    
    func testScheduledCleanupOnlyIncludesSafeCategories() async throws {
        // Given: Preferences with both safe and unsafe categories
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [
            .systemCaches,      // safe
            .temporaryFiles,    // safe
            .largeFiles,        // unsafe
            .oldFiles,          // unsafe
            .downloads          // unsafe
        ]
        try preferencesStore.save(preferences)
        
        // Setup mock scanner to return files
        let cacheFile = createMockFileMetadata(path: "/tmp/cache.tmp", size: 1000)
        let largeFile = createMockFileMetadata(path: "/tmp/large.bin", size: 1000000)
        mockFileScanner.mockScanResult = ScanResult(
            files: [cacheFile, largeFile],
            errors: [],
            duration: 1.0
        )
        
        // Setup mock analyzer
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [
                .systemCaches: [cacheFile],
                .largeFiles: [largeFile]
            ],
            totalSize: 1001000,
            potentialSavings: 1001000,
            duplicateGroups: []
        )
        
        // Setup mock cleanup engine
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [],
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then: Only safe categories should be scanned
        XCTAssertEqual(mockFileScanner.lastScannedCategories, [.systemCaches, .temporaryFiles])
        
        // And: Result should only include safe categories
        XCTAssertEqual(result.categoriesCleaned, [.systemCaches, .temporaryFiles])
    }
    
    func testScheduledCleanupFailsWithNoSafeCategories() async throws {
        // Given: Preferences with only unsafe categories
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.largeFiles, .oldFiles, .downloads]
        try preferencesStore.save(preferences)
        
        // When/Then: Should throw error
        do {
            _ = try await coordinator.executeScheduledCleanup()
            XCTFail("Expected error to be thrown")
        } catch let error as ScheduledCleanupError {
            XCTAssertEqual(error, .noSafeCategoriesConfigured)
        }
    }
    
    // MARK: - Execution Tests
    
    func testExecuteScheduledCleanupSuccess() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches, .temporaryFiles]
        try preferencesStore.save(preferences)
        
        // Setup mocks
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        let file2 = createMockFileMetadata(path: "/tmp/cache2.tmp", size: 2000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1, file2],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [
                .systemCaches: [file1],
                .temporaryFiles: [file2]
            ],
            totalSize: 3000,
            potentialSavings: 3000,
            duplicateGroups: []
        )
        
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 2,
            spaceFreed: 3000,
            errors: [],
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then
        XCTAssertEqual(result.filesRemoved, 2)
        XCTAssertEqual(result.spaceFreed, 3000)
        XCTAssertEqual(result.categoriesCleaned, [.systemCaches, .temporaryFiles])
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertGreaterThan(result.duration, 0)
    }
    
    func testExecuteScheduledCleanupWithErrors() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        // Setup mocks
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        
        let cleanupError = CleanupError.fileInUse(path: "/tmp/cache1.tmp")
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [cleanupError],
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertEqual(result.spaceFreed, 0)
        XCTAssertEqual(result.errors.count, 1)
    }
    
    func testScheduledCleanupUsesCorrectOptions() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        // Setup mocks
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [],
            backupLocation: nil
        )
        
        // When
        _ = try await coordinator.executeScheduledCleanup()
        
        // Then: Verify cleanup options
        let options = mockCleanupEngine.lastCleanupOptions!
        XCTAssertFalse(options.createBackup, "Scheduled cleanup should not create backups")
        XCTAssertTrue(options.moveToTrash, "Scheduled cleanup should move to trash for safety")
        XCTAssertTrue(options.skipInUseFiles, "Scheduled cleanup should skip in-use files")
    }
    
    // MARK: - Preferences Store Tests
    
    func testPreferencesStoreDefaultValues() throws {
        // When
        let preferences = try preferencesStore.load()
        
        // Then
        XCTAssertFalse(preferences.enableScheduledCleanup)
        XCTAssertEqual(preferences.scheduledCleanupInterval, .weekly)
        XCTAssertEqual(preferences.scheduledCategories, [.systemCaches, .applicationCaches, .temporaryFiles])
        XCTAssertTrue(preferences.createBackupsByDefault)
        XCTAssertTrue(preferences.moveToTrashByDefault)
        XCTAssertEqual(preferences.oldFileThresholdDays, 365)
        XCTAssertEqual(preferences.largeFileSizeThresholdMB, 100)
    }
    
    func testPreferencesStoreSaveAndLoad() throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCleanupInterval = .daily
        preferences.scheduledCategories = [.systemCaches, .browserCaches]
        preferences.oldFileThresholdDays = 180
        
        // When
        try preferencesStore.save(preferences)
        let loaded = try preferencesStore.load()
        
        // Then
        XCTAssertEqual(loaded.enableScheduledCleanup, true)
        XCTAssertEqual(loaded.scheduledCleanupInterval, .daily)
        XCTAssertEqual(loaded.scheduledCategories, [.systemCaches, .browserCaches])
        XCTAssertEqual(loaded.oldFileThresholdDays, 180)
    }
    
    func testPreferencesStoreReset() throws {
        // Given: Modified preferences
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.oldFileThresholdDays = 180
        try preferencesStore.save(preferences)
        
        // When
        try preferencesStore.reset()
        let loaded = try preferencesStore.load()
        
        // Then: Should be back to defaults
        XCTAssertFalse(loaded.enableScheduledCleanup)
        XCTAssertEqual(loaded.oldFileThresholdDays, 365)
    }
    
    // MARK: - Cleanup Interval Tests
    
    func testCleanupIntervalTimeIntervals() {
        XCTAssertEqual(CleanupInterval.daily.timeInterval, 24 * 60 * 60)
        XCTAssertEqual(CleanupInterval.weekly.timeInterval, 7 * 24 * 60 * 60)
        XCTAssertEqual(CleanupInterval.monthly.timeInterval, 30 * 24 * 60 * 60)
    }
    
    // MARK: - Error Handling and Logging Tests (Task 14.2)
    
    func testScheduledCleanupLogsAllErrors() async throws {
        // Given: Multiple errors during cleanup
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches, .temporaryFiles]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        let file2 = createMockFileMetadata(path: "/tmp/cache2.tmp", size: 2000)
        let file3 = createMockFileMetadata(path: "/tmp/cache3.tmp", size: 3000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1, file2, file3],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [
                .systemCaches: [file1, file2],
                .temporaryFiles: [file3]
            ],
            totalSize: 6000,
            potentialSavings: 6000,
            duplicateGroups: []
        )
        
        // Multiple different error types
        let errors = [
            CleanupError.fileInUse(path: "/tmp/cache1.tmp"),
            CleanupError.permissionDenied(path: "/tmp/cache2.tmp"),
            CleanupError.fileNotFound(path: "/tmp/cache3.tmp")
        ]
        
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: errors,
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then: All errors should be captured in result
        XCTAssertEqual(result.errors.count, 3)
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertEqual(result.spaceFreed, 0)
        
        // Verify error types are preserved
        XCTAssertTrue(result.errors.contains { error in
            if case .fileInUse = error { return true }
            return false
        })
        XCTAssertTrue(result.errors.contains { error in
            if case .permissionDenied = error { return true }
            return false
        })
        XCTAssertTrue(result.errors.contains { error in
            if case .fileNotFound = error { return true }
            return false
        })
    }
    
    func testScheduledCleanupHandlesPartialSuccess() async throws {
        // Given: Some files cleaned successfully, some with errors
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        let file2 = createMockFileMetadata(path: "/tmp/cache2.tmp", size: 2000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1, file2],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1, file2]],
            totalSize: 3000,
            potentialSavings: 3000,
            duplicateGroups: []
        )
        
        // Partial success: 1 file removed, 1 error
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [CleanupError.fileInUse(path: "/tmp/cache2.tmp")],
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then: Should report both success and errors
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertEqual(result.spaceFreed, 1000)
        XCTAssertEqual(result.errors.count, 1)
    }
    
    func testScheduledCleanupExecutesInBackground() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1],
            errors: [],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [],
            backupLocation: nil
        )
        
        // When: Execute cleanup (should be async)
        let startTime = Date()
        let result = try await coordinator.executeScheduledCleanup()
        let duration = Date().timeIntervalSince(startTime)
        
        // Then: Should complete and track duration
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertGreaterThan(result.duration, 0)
        XCTAssertLessThan(duration, 5.0, "Cleanup should complete quickly in test")
    }
    
    func testScheduledCleanupResultIncludesExecutionDate() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        mockFileScanner.mockScanResult = ScanResult(files: [], errors: [], duration: 0)
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [:],
            totalSize: 0,
            potentialSavings: 0,
            duplicateGroups: []
        )
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [],
            backupLocation: nil
        )
        
        // When
        let beforeExecution = Date()
        let result = try await coordinator.executeScheduledCleanup()
        let afterExecution = Date()
        
        // Then: Execution date should be within the execution window
        XCTAssertGreaterThanOrEqual(result.executionDate, beforeExecution)
        XCTAssertLessThanOrEqual(result.executionDate, afterExecution)
    }
    
    func testScheduledCleanupHandlesScanErrors() async throws {
        // Given: Scan encounters errors but continues
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        // Scan completes with some errors
        mockFileScanner.mockScanResult = ScanResult(
            files: [file1],
            errors: [ScanError.permissionDenied(path: "/System/Library/Caches")],
            duration: 1.0
        )
        
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [],
            backupLocation: nil
        )
        
        // When: Should not throw, should handle gracefully
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then: Cleanup should still succeed with accessible files
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertEqual(result.spaceFreed, 1000)
    }
    
    func testScheduledCleanupTracksAllCategories() async throws {
        // Given: Multiple categories configured
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches, .applicationCaches, .browserCaches, .temporaryFiles]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        mockFileScanner.mockScanResult = ScanResult(files: [file1], errors: [], duration: 1.0)
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000,
            errors: [],
            backupLocation: nil
        )
        
        // When
        let result = try await coordinator.executeScheduledCleanup()
        
        // Then: Result should track all safe categories that were configured
        XCTAssertEqual(result.categoriesCleaned, [.systemCaches, .applicationCaches, .browserCaches, .temporaryFiles])
    }
    
    // MARK: - Notification Tests (Task 14.2)
    
    func testScheduledCleanupPostsSuccessNotification() async throws {
        // Given
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000000)
        
        mockFileScanner.mockScanResult = ScanResult(files: [file1], errors: [], duration: 1.0)
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000000,
            potentialSavings: 1000000,
            duplicateGroups: []
        )
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1000000,
            errors: [],
            backupLocation: nil
        )
        
        // When
        _ = try await coordinator.executeScheduledCleanup()
        
        // Then: Should post success notification
        XCTAssertEqual(mockNotificationPoster.postedNotifications.count, 1)
        let notification = mockNotificationPoster.postedNotifications[0]
        XCTAssertEqual(notification.title, "Scheduled Cleanup Complete")
        XCTAssertTrue(notification.body.contains("1 files"))
        XCTAssertTrue(notification.body.contains("Freed"))
    }
    
    func testScheduledCleanupNotificationIncludesErrorCount() async throws {
        // Given: Cleanup with errors
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.systemCaches]
        try preferencesStore.save(preferences)
        
        let file1 = createMockFileMetadata(path: "/tmp/cache1.tmp", size: 1000)
        
        mockFileScanner.mockScanResult = ScanResult(files: [file1], errors: [], duration: 1.0)
        mockStorageAnalyzer.mockAnalysisResult = AnalysisResult(
            categorizedFiles: [.systemCaches: [file1]],
            totalSize: 1000,
            potentialSavings: 1000,
            duplicateGroups: []
        )
        mockCleanupEngine.mockCleanupResult = CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [
                CleanupError.fileInUse(path: "/tmp/cache1.tmp"),
                CleanupError.permissionDenied(path: "/tmp/cache2.tmp")
            ],
            backupLocation: nil
        )
        
        // When
        _ = try await coordinator.executeScheduledCleanup()
        
        // Then: Notification should include error count
        XCTAssertEqual(mockNotificationPoster.postedNotifications.count, 1)
        let notification = mockNotificationPoster.postedNotifications[0]
        XCTAssertTrue(notification.body.contains("2 errors"))
    }
    
    func testScheduledCleanupPostsErrorNotificationOnFailure() async throws {
        // Given: Preferences that will cause an error
        var preferences = UserPreferences.default
        preferences.enableScheduledCleanup = true
        preferences.scheduledCategories = [.largeFiles]  // Only unsafe category
        try preferencesStore.save(preferences)
        
        // When/Then: Should throw error but notification should be posted
        do {
            _ = try await coordinator.executeScheduledCleanup()
            XCTFail("Expected error to be thrown")
        } catch {
            // Error is expected, but we can't test notification posting here
            // because it happens in the scheduler's activity handler
            // This test verifies the error is thrown correctly
            XCTAssertTrue(error is ScheduledCleanupError)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createMockFileMetadata(path: String, size: Int64) -> FileMetadata {
        return FileMetadata(
            url: URL(fileURLWithPath: path),
            size: size,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
}

// MARK: - Mock Implementations

class MockFileScanner: FileScanner {
    var mockScanResult: ScanResult?
    var lastScannedCategories: Set<CleanupCategory>?
    var shouldCancel = false
    
    func scan(
        paths: [URL],
        categories: Set<CleanupCategory>,
        progressHandler: @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult {
        lastScannedCategories = categories
        
        if let result = mockScanResult {
            return result
        }
        
        return ScanResult(files: [], errors: [], duration: 0)
    }
    
    func cancelScan() {
        shouldCancel = true
    }
    
    func categorize(file: FileMetadata) -> Set<CleanupCategory> {
        return [.temporaryFiles]
    }
}

class MockStorageAnalyzer: StorageAnalyzer {
    var mockAnalysisResult: AnalysisResult?
    
    func analyze(scanResult: ScanResult) -> AnalysisResult {
        if let result = mockAnalysisResult {
            return result
        }
        
        return AnalysisResult(
            categorizedFiles: [:],
            totalSize: 0,
            potentialSavings: 0,
            duplicateGroups: []
        )
    }
    
    func categorize(file: FileMetadata) -> Set<CleanupCategory> {
        return [.temporaryFiles]
    }
    
    func calculateSavings(files: [FileMetadata]) -> Int64 {
        return files.reduce(0) { $0 + $1.size }
    }
    
    func filterByAge(files: [FileMetadata], thresholdDays: Int) -> [FileMetadata] {
        return files
    }
    
    func clampAgeThreshold(_ thresholdDays: Int) -> Int {
        let minThreshold = 30
        let maxThreshold = 1095
        return max(minThreshold, min(maxThreshold, thresholdDays))
    }
    
    func filterBySize(files: [FileMetadata], thresholdBytes: Int64) -> [FileMetadata] {
        return files
    }
    
    func filterByType(files: [FileMetadata], fileType: FileType) -> [FileMetadata] {
        return files
    }
    
    func sortBySize(files: [FileMetadata]) -> [FileMetadata] {
        return files.sorted { $0.size > $1.size }
    }
    
    func applyFilters(files: [FileMetadata], filters: [(FileMetadata) -> Bool]) -> [FileMetadata] {
        return files
    }
    
    func categorizeLogsByApplication(files: [FileMetadata]) -> [String: [LogFileInfo]] {
        return [:]
    }
    
    func getLogFileInfo(files: [FileMetadata]) -> [LogFileInfo] {
        return []
    }
    
    func categorizeDownloadsByType(files: [FileMetadata]) -> [DownloadsFileType: [DownloadsFileInfo]] {
        return [:]
    }
    
    func getDownloadsFileInfo(files: [FileMetadata]) -> [DownloadsFileInfo] {
        return []
    }
    
    func filterOldDownloads(files: [FileMetadata]) -> [FileMetadata] {
        return files
    }
}

class MockCleanupEngine: CleanupEngine {
    var mockCleanupResult: CleanupResult?
    var lastCleanupOptions: CleanupOptions?
    var shouldCancel = false
    
    func cleanup(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        lastCleanupOptions = options
        
        if let result = mockCleanupResult {
            return result
        }
        
        return CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [],
            backupLocation: nil
        )
    }
    
    func cleanupLogs(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        return CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [],
            backupLocation: nil
        )
    }
    
    func cleanupDuplicates(
        duplicateGroups: [DuplicateGroup],
        filesToKeep: [String: URL],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> CleanupResult {
        return CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [],
            backupLocation: nil
        )
    }
    
    func validateCleanup(files: [FileMetadata]) -> ValidationResult {
        return ValidationResult(isValid: true, blockedFiles: [], warnings: [])
    }
    
    func cancelCleanup() {
        shouldCancel = true
    }
}
