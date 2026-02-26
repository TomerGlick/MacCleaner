import XCTest
@testable import MacStorageCleanup

final class CleanupEngineTests: XCTestCase {
    var tempDirectory: URL!
    var safeListManager: MockSafeListManager!
    var backupManager: MockBackupManager!
    var cleanupEngine: DefaultCleanupEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for tests
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Initialize mock safe list manager
        safeListManager = MockSafeListManager()
        
        // Initialize mock backup manager
        backupManager = MockBackupManager()
        
        // Initialize cleanup engine
        cleanupEngine = DefaultCleanupEngine(safeListManager: safeListManager, backupManager: backupManager)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Validation Tests
    
    func testValidateCleanup_WithProtectedFiles_ReturnsInvalid() {
        // Given: Files including protected ones
        let protectedFile = createTestFileMetadata(path: "/System/test.txt")
        let normalFile = createTestFileMetadata(path: tempDirectory.appendingPathComponent("normal.txt").path)
        
        safeListManager.protectedPaths = ["/System"]
        
        // When: Validating cleanup
        let result = cleanupEngine.validateCleanup(files: [protectedFile, normalFile])
        
        // Then: Validation should fail
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.blockedFiles.count, 1)
        XCTAssertEqual(result.blockedFiles.first?.url.path, "/System/test.txt")
        XCTAssertTrue(result.warnings.contains { $0.contains("protected") })
    }
    
    func testValidateCleanup_WithOnlyNormalFiles_ReturnsValid() {
        // Given: Only normal files
        let file1 = createTestFileMetadata(path: tempDirectory.appendingPathComponent("file1.txt").path)
        let file2 = createTestFileMetadata(path: tempDirectory.appendingPathComponent("file2.txt").path)
        
        // When: Validating cleanup
        let result = cleanupEngine.validateCleanup(files: [file1, file2])
        
        // Then: Validation should pass
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.blockedFiles.count, 0)
    }
    
    func testValidateCleanup_WithInUseFiles_AddsWarning() {
        // Given: File marked as in use
        let inUseFile = createTestFileMetadata(
            path: tempDirectory.appendingPathComponent("inuse.txt").path,
            isInUse: true
        )
        
        // When: Validating cleanup
        let result = cleanupEngine.validateCleanup(files: [inUseFile])
        
        // Then: Should have warning about in-use file
        XCTAssertTrue(result.isValid)  // Not blocked, just warned
        XCTAssertTrue(result.warnings.contains { $0.contains("in use") })
    }
    
    func testValidateCleanup_WithNonDeletableFiles_AddsWarning() {
        // Given: File marked as not deletable
        let nonDeletableFile = createTestFileMetadata(
            path: tempDirectory.appendingPathComponent("readonly.txt").path,
            permissions: FilePermissions(isReadable: true, isWritable: false, isDeletable: false)
        )
        
        // When: Validating cleanup
        let result = cleanupEngine.validateCleanup(files: [nonDeletableFile])
        
        // Then: Should have warning about non-deletable file
        XCTAssertTrue(result.isValid)  // Not blocked, just warned
        XCTAssertTrue(result.warnings.contains { $0.contains("not deletable") })
    }
    
    // MARK: - Cleanup Tests
    
    func testCleanup_WithNormalFiles_RemovesFiles() async throws {
        // Given: Create actual test files
        let file1URL = tempDirectory.appendingPathComponent("test1.txt")
        let file2URL = tempDirectory.appendingPathComponent("test2.txt")
        
        try "Test content 1".write(to: file1URL, atomically: true, encoding: .utf8)
        try "Test content 2".write(to: file2URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        var progressUpdates: [CleanupProgress] = []
        
        // When: Performing cleanup
        let result = try await cleanupEngine.cleanup(
            files: [file1, file2],
            options: options,
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )
        
        // Then: Files should be removed
        XCTAssertEqual(result.filesRemoved, 2)
        XCTAssertGreaterThan(result.spaceFreed, 0)
        XCTAssertEqual(result.errors.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2URL.path))
        XCTAssertEqual(progressUpdates.count, 2)
    }
    
    func testCleanup_WithProtectedFiles_SkipsProtectedFiles() async throws {
        // Given: Mix of protected and normal files
        let normalFileURL = tempDirectory.appendingPathComponent("normal.txt")
        try "Normal content".write(to: normalFileURL, atomically: true, encoding: .utf8)
        
        let normalFile = try createFileMetadata(from: normalFileURL)
        let protectedFile = createTestFileMetadata(path: "/System/protected.txt")
        
        safeListManager.protectedPaths = ["/System"]
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup
        let result = try await cleanupEngine.cleanup(
            files: [normalFile, protectedFile],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Only normal file should be removed
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalFileURL.path))
    }
    
    func testCleanup_WithMoveToTrash_MovesFilesToTrash() async throws {
        // Given: Create test file
        let fileURL = tempDirectory.appendingPathComponent("trash_test.txt")
        try "Trash me".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let file = try createFileMetadata(from: fileURL)
        let options = CleanupOptions(createBackup: false, moveToTrash: true, skipInUseFiles: true)
        
        // When: Performing cleanup with trash option
        let result = try await cleanupEngine.cleanup(
            files: [file],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: File should be moved to trash (not at original location)
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    func testCleanup_WithNonExistentFile_ReportsError() async throws {
        // Given: File metadata for non-existent file
        let nonExistentURL = tempDirectory.appendingPathComponent("nonexistent.txt")
        let file = createTestFileMetadata(path: nonExistentURL.path)
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup
        let result = try await cleanupEngine.cleanup(
            files: [file],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should report error
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertEqual(result.errors.count, 1)
        
        if case .fileNotFound(let path) = result.errors.first {
            XCTAssertEqual(path, nonExistentURL.path)
        } else {
            XCTFail("Expected fileNotFound error")
        }
    }
    
    func testCleanup_WithProgressHandler_ReportsProgress() async throws {
        // Given: Multiple test files
        let files = try (1...5).map { i -> FileMetadata in
            let fileURL = tempDirectory.appendingPathComponent("file\(i).txt")
            try "Content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            return try createFileMetadata(from: fileURL)
        }
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        var progressUpdates: [CleanupProgress] = []
        
        // When: Performing cleanup
        _ = try await cleanupEngine.cleanup(
            files: files,
            options: options,
            progressHandler: { progress in
                progressUpdates.append(progress)
            }
        )
        
        // Then: Should receive progress updates
        XCTAssertEqual(progressUpdates.count, 5)
        XCTAssertEqual(progressUpdates.last?.filesProcessed, 5)
        XCTAssertEqual(progressUpdates.last?.totalFiles, 5)
        
        // Verify progress is increasing
        for i in 0..<progressUpdates.count {
            XCTAssertEqual(progressUpdates[i].filesProcessed, i + 1)
        }
    }
    
    // MARK: - Cancellation Tests
    
    func testCancelCleanup_DuringOperation_StopsCleanup() async throws {
        // Given: Many test files
        let files = try (1...10).map { i -> FileMetadata in
            let fileURL = tempDirectory.appendingPathComponent("cancel_test\(i).txt")
            try "Content \(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            return try createFileMetadata(from: fileURL)
        }
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        var progressCount = 0
        
        // When: Starting cleanup and cancelling after first file
        let cleanupTask = Task {
            return try await cleanupEngine.cleanup(
                files: files,
                options: options,
                progressHandler: { _ in
                    progressCount += 1
                    if progressCount == 1 {
                        // Cancel after first file
                        self.cleanupEngine.cancelCleanup()
                    }
                }
            )
        }
        
        let result = try await cleanupTask.value
        
        // Then: Should have cancelled error and not all files removed
        XCTAssertLessThan(result.filesRemoved, files.count)
        XCTAssertTrue(result.errors.contains { error in
            if case .cancelled = error {
                return true
            }
            return false
        })
    }
    
    // MARK: - Backup Integration Tests
    
    func testCleanup_WithBackupEnabled_CreatesBackup() async throws {
        // Given: Test files with backup enabled
        let file1URL = tempDirectory.appendingPathComponent("backup_test1.txt")
        let file2URL = tempDirectory.appendingPathComponent("backup_test2.txt")
        
        try "Backup content 1".write(to: file1URL, atomically: true, encoding: .utf8)
        try "Backup content 2".write(to: file2URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup with backup
        let result = try await cleanupEngine.cleanup(
            files: [file1, file2],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Backup should be created
        XCTAssertNotNil(result.backupLocation)
        XCTAssertEqual(backupManager.lastBackupFiles.count, 2)
        XCTAssertEqual(backupManager.backups.count, 1)
        XCTAssertEqual(result.filesRemoved, 2)
    }
    
    func testCleanup_WithBackupFailure_DoesNotDeleteFiles() async throws {
        // Given: Test files with backup that will fail
        let fileURL = tempDirectory.appendingPathComponent("backup_fail_test.txt")
        try "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let file = try createFileMetadata(from: fileURL)
        
        backupManager.shouldFailBackup = true
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup with failing backup
        let result = try await cleanupEngine.cleanup(
            files: [file],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Files should not be deleted
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(result.errors.contains { error in
            if case .backupFailed = error {
                return true
            }
            return false
        })
    }
    
    func testCleanup_WithBackupDisabled_DoesNotCreateBackup() async throws {
        // Given: Test files with backup disabled
        let fileURL = tempDirectory.appendingPathComponent("no_backup_test.txt")
        try "Content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let file = try createFileMetadata(from: fileURL)
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup without backup
        let result = try await cleanupEngine.cleanup(
            files: [file],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: No backup should be created
        XCTAssertNil(result.backupLocation)
        XCTAssertEqual(backupManager.backups.count, 0)
        XCTAssertEqual(result.filesRemoved, 1)
    }
    
    func testCleanup_WithDeletionError_RollsBackChanges() async throws {
        // Given: Mix of valid and invalid files
        let validFileURL = tempDirectory.appendingPathComponent("valid.txt")
        try "Valid content".write(to: validFileURL, atomically: true, encoding: .utf8)
        
        let validFile = try createFileMetadata(from: validFileURL)
        let invalidFile = createTestFileMetadata(path: "/nonexistent/invalid.txt")
        
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing cleanup that will fail on second file
        let result = try await cleanupEngine.cleanup(
            files: [validFile, invalidFile],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should rollback (filesRemoved should be 0 due to rollback)
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertTrue(result.errors.contains { error in
            if case .fileNotFound = error {
                return true
            }
            return false
        })
        XCTAssertNotNil(result.backupLocation)
    }
    
    // MARK: - Helper Methods
    
    // MARK: - Duplicate Cleanup Tests
    
    func testCleanupDuplicates_PreservesAtLeastOneCopy() async throws {
        // Given: Duplicate group with 3 files
        let file1URL = tempDirectory.appendingPathComponent("duplicate1.txt")
        let file2URL = tempDirectory.appendingPathComponent("duplicate2.txt")
        let file3URL = tempDirectory.appendingPathComponent("duplicate3.txt")
        
        let content = "Duplicate content"
        try content.write(to: file1URL, atomically: true, encoding: .utf8)
        try content.write(to: file2URL, atomically: true, encoding: .utf8)
        try content.write(to: file3URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        let file3 = try createFileMetadata(from: file3URL)
        
        let duplicateGroup = DuplicateGroup(
            hash: "test_hash_123",
            files: [file1, file2, file3],
            totalSize: file1.size * 3,
            wastedSpace: file1.size * 2
        )
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning duplicates without specifying which to keep (should keep first)
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [duplicateGroup],
            filesToKeep: [:],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should remove 2 files and keep 1
        XCTAssertEqual(result.filesRemoved, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1URL.path), "First file should be preserved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2URL.path), "Second file should be removed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file3URL.path), "Third file should be removed")
    }
    
    func testCleanupDuplicates_AllowsUserToSelectWhichCopyToKeep() async throws {
        // Given: Duplicate group with 3 files
        let file1URL = tempDirectory.appendingPathComponent("dup1.txt")
        let file2URL = tempDirectory.appendingPathComponent("dup2.txt")
        let file3URL = tempDirectory.appendingPathComponent("dup3.txt")
        
        let content = "Same content"
        try content.write(to: file1URL, atomically: true, encoding: .utf8)
        try content.write(to: file2URL, atomically: true, encoding: .utf8)
        try content.write(to: file3URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        let file3 = try createFileMetadata(from: file3URL)
        
        let duplicateGroup = DuplicateGroup(
            hash: "test_hash_456",
            files: [file1, file2, file3],
            totalSize: file1.size * 3,
            wastedSpace: file1.size * 2
        )
        
        // User wants to keep the second file
        let filesToKeep = ["test_hash_456": file2URL]
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning duplicates with user selection
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [duplicateGroup],
            filesToKeep: filesToKeep,
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should keep the user-selected file and remove others
        XCTAssertEqual(result.filesRemoved, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1URL.path), "First file should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2URL.path), "Second file should be preserved (user choice)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file3URL.path), "Third file should be removed")
    }
    
    func testCleanupDuplicates_HandlesMultipleGroups() async throws {
        // Given: Two duplicate groups
        // Group 1
        let group1File1URL = tempDirectory.appendingPathComponent("group1_file1.txt")
        let group1File2URL = tempDirectory.appendingPathComponent("group1_file2.txt")
        try "Group 1 content".write(to: group1File1URL, atomically: true, encoding: .utf8)
        try "Group 1 content".write(to: group1File2URL, atomically: true, encoding: .utf8)
        
        let group1File1 = try createFileMetadata(from: group1File1URL)
        let group1File2 = try createFileMetadata(from: group1File2URL)
        
        let group1 = DuplicateGroup(
            hash: "hash_group1",
            files: [group1File1, group1File2],
            totalSize: group1File1.size * 2,
            wastedSpace: group1File1.size
        )
        
        // Group 2
        let group2File1URL = tempDirectory.appendingPathComponent("group2_file1.txt")
        let group2File2URL = tempDirectory.appendingPathComponent("group2_file2.txt")
        let group2File3URL = tempDirectory.appendingPathComponent("group2_file3.txt")
        try "Group 2 content".write(to: group2File1URL, atomically: true, encoding: .utf8)
        try "Group 2 content".write(to: group2File2URL, atomically: true, encoding: .utf8)
        try "Group 2 content".write(to: group2File3URL, atomically: true, encoding: .utf8)
        
        let group2File1 = try createFileMetadata(from: group2File1URL)
        let group2File2 = try createFileMetadata(from: group2File2URL)
        let group2File3 = try createFileMetadata(from: group2File3URL)
        
        let group2 = DuplicateGroup(
            hash: "hash_group2",
            files: [group2File1, group2File2, group2File3],
            totalSize: group2File1.size * 3,
            wastedSpace: group2File1.size * 2
        )
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning multiple duplicate groups
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [group1, group2],
            filesToKeep: [:],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should preserve one file from each group
        XCTAssertEqual(result.filesRemoved, 3)  // 1 from group1 + 2 from group2
        
        // Group 1: first file preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: group1File1URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group1File2URL.path))
        
        // Group 2: first file preserved
        XCTAssertTrue(FileManager.default.fileExists(atPath: group2File1URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group2File2URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: group2File3URL.path))
    }
    
    func testCleanupDuplicates_WithBackupEnabled_CreatesBackup() async throws {
        // Given: Duplicate group with backup enabled
        let file1URL = tempDirectory.appendingPathComponent("backup_dup1.txt")
        let file2URL = tempDirectory.appendingPathComponent("backup_dup2.txt")
        
        let content = "Backup duplicate content"
        try content.write(to: file1URL, atomically: true, encoding: .utf8)
        try content.write(to: file2URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        
        let duplicateGroup = DuplicateGroup(
            hash: "backup_hash",
            files: [file1, file2],
            totalSize: file1.size * 2,
            wastedSpace: file1.size
        )
        
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning duplicates with backup
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [duplicateGroup],
            filesToKeep: [:],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should create backup and remove duplicate
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertNotNil(result.backupLocation)
        XCTAssertEqual(backupManager.lastBackupFiles.count, 1)
    }
    
    func testCleanupDuplicates_WithMoveToTrash_MovesFilesToTrash() async throws {
        // Given: Duplicate group with trash option
        let file1URL = tempDirectory.appendingPathComponent("trash_dup1.txt")
        let file2URL = tempDirectory.appendingPathComponent("trash_dup2.txt")
        
        let content = "Trash duplicate content"
        try content.write(to: file1URL, atomically: true, encoding: .utf8)
        try content.write(to: file2URL, atomically: true, encoding: .utf8)
        
        let file1 = try createFileMetadata(from: file1URL)
        let file2 = try createFileMetadata(from: file2URL)
        
        let duplicateGroup = DuplicateGroup(
            hash: "trash_hash",
            files: [file1, file2],
            totalSize: file1.size * 2,
            wastedSpace: file1.size
        )
        
        let options = CleanupOptions(createBackup: false, moveToTrash: true, skipInUseFiles: true)
        
        // When: Cleaning duplicates with trash option
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [duplicateGroup],
            filesToKeep: [:],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should move duplicate to trash
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file1URL.path), "First file preserved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2URL.path), "Second file moved to trash")
    }
    
    func testCleanupDuplicates_WithEmptyGroups_ReturnsZeroRemoved() async throws {
        // Given: Empty duplicate groups array
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning with no duplicate groups
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [],
            filesToKeep: [:],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Should return zero files removed
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertEqual(result.spaceFreed, 0)
        XCTAssertEqual(result.errors.count, 0)
    }
    
    func testCleanupDuplicates_IntegratesWithExistingCleanupOperations() async throws {
        // Given: Duplicate group with protected file
        let normalFileURL = tempDirectory.appendingPathComponent("normal_dup.txt")
        let protectedFileURL = URL(fileURLWithPath: "/System/protected_dup.txt")
        
        try "Duplicate content".write(to: normalFileURL, atomically: true, encoding: .utf8)
        
        let normalFile = try createFileMetadata(from: normalFileURL)
        let protectedFile = createTestFileMetadata(path: protectedFileURL.path)
        
        let duplicateGroup = DuplicateGroup(
            hash: "protected_hash",
            files: [normalFile, protectedFile],
            totalSize: normalFile.size * 2,
            wastedSpace: normalFile.size
        )
        
        safeListManager.protectedPaths = ["/System"]
        
        // User wants to keep the normal file (delete protected - which should be blocked)
        let filesToKeep = ["protected_hash": normalFileURL]
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Cleaning duplicates with protected file
        let result = try await cleanupEngine.cleanupDuplicates(
            duplicateGroups: [duplicateGroup],
            filesToKeep: filesToKeep,
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Protected file should be skipped by validation
        XCTAssertEqual(result.filesRemoved, 0)  // Protected file blocked
        XCTAssertTrue(FileManager.default.fileExists(atPath: normalFileURL.path))
    }
    
    // MARK: - Helper Methods
    
    // MARK: - Log Cleanup Tests
    
    func testCleanupLogs_PreservesRecentLogs() async throws {
        // Given: Mix of recent and old log files
        let now = Date()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        
        let recentLogURL = tempDirectory.appendingPathComponent("recent.log")
        let oldLogURL = tempDirectory.appendingPathComponent("old.log")
        
        try "Recent log".write(to: recentLogURL, atomically: true, encoding: .utf8)
        try "Old log".write(to: oldLogURL, atomically: true, encoding: .utf8)
        
        let recentLog = try createLogFileMetadata(from: recentLogURL, modifiedDate: fiveDaysAgo)
        let oldLog = try createLogFileMetadata(from: oldLogURL, modifiedDate: tenDaysAgo)
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup
        let result = try await cleanupEngine.cleanupLogs(
            files: [recentLog, oldLog],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Only old log should be removed, recent log preserved
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentLogURL.path), "Recent log should be preserved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLogURL.path), "Old log should be removed")
    }
    
    func testCleanupLogs_WithBackupEnabled_ArchivesOldLogs() async throws {
        // Given: Very old log files (>30 days) with backup enabled
        let now = Date()
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        
        let veryOldLogURL = tempDirectory.appendingPathComponent("very_old.log")
        try "Very old log content".write(to: veryOldLogURL, atomically: true, encoding: .utf8)
        
        let veryOldLog = try createLogFileMetadata(from: veryOldLogURL, modifiedDate: fortyDaysAgo)
        
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup with backup
        let result = try await cleanupEngine.cleanupLogs(
            files: [veryOldLog],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Log should be archived and removed
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertNotNil(result.backupLocation, "Backup should be created for old logs")
        XCTAssertEqual(backupManager.lastBackupFiles.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: veryOldLogURL.path))
    }
    
    func testCleanupLogs_WithoutBackup_DoesNotDeleteVeryOldLogs() async throws {
        // Given: Mix of moderately old (10 days) and very old (40 days) logs without backup
        let now = Date()
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        
        let moderateLogURL = tempDirectory.appendingPathComponent("moderate.log")
        let veryOldLogURL = tempDirectory.appendingPathComponent("very_old.log")
        
        try "Moderate log".write(to: moderateLogURL, atomically: true, encoding: .utf8)
        try "Very old log".write(to: veryOldLogURL, atomically: true, encoding: .utf8)
        
        let moderateLog = try createLogFileMetadata(from: moderateLogURL, modifiedDate: tenDaysAgo)
        let veryOldLog = try createLogFileMetadata(from: veryOldLogURL, modifiedDate: fortyDaysAgo)
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup without backup
        let result = try await cleanupEngine.cleanupLogs(
            files: [moderateLog, veryOldLog],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Only moderately old log should be removed, very old log preserved (needs archiving)
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moderateLogURL.path), "Moderate log should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: veryOldLogURL.path), "Very old log should be preserved without backup")
    }
    
    func testCleanupLogs_FiltersNonLogFiles() async throws {
        // Given: Mix of log and non-log files
        let now = Date()
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        
        let logURL = tempDirectory.appendingPathComponent("old.log")
        let cacheURL = tempDirectory.appendingPathComponent("old.cache")
        
        try "Old log".write(to: logURL, atomically: true, encoding: .utf8)
        try "Old cache".write(to: cacheURL, atomically: true, encoding: .utf8)
        
        let logFile = try createLogFileMetadata(from: logURL, modifiedDate: tenDaysAgo)
        var cacheFile = try createFileMetadata(from: cacheURL)
        cacheFile = FileMetadata(
            url: cacheFile.url,
            size: cacheFile.size,
            createdDate: cacheFile.createdDate,
            modifiedDate: tenDaysAgo,
            accessedDate: cacheFile.accessedDate,
            fileType: .cache,  // Not a log file
            isInUse: cacheFile.isInUse,
            permissions: cacheFile.permissions
        )
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup
        let result = try await cleanupEngine.cleanupLogs(
            files: [logFile, cacheFile],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Only log file should be removed, cache file ignored
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path), "Log file should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path), "Cache file should be preserved")
    }
    
    func testCleanupLogs_WithArchiveFailure_DoesNotDeleteOldLogs() async throws {
        // Given: Very old log with backup that will fail
        let now = Date()
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        
        let veryOldLogURL = tempDirectory.appendingPathComponent("very_old_fail.log")
        try "Very old log".write(to: veryOldLogURL, atomically: true, encoding: .utf8)
        
        let veryOldLog = try createLogFileMetadata(from: veryOldLogURL, modifiedDate: fortyDaysAgo)
        
        backupManager.shouldFailBackup = true
        let options = CleanupOptions(createBackup: true, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup with failing backup
        let result = try await cleanupEngine.cleanupLogs(
            files: [veryOldLog],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Log should not be deleted due to archive failure
        XCTAssertEqual(result.filesRemoved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: veryOldLogURL.path), "Log should be preserved when archive fails")
        XCTAssertTrue(result.errors.contains { error in
            if case .backupFailed = error {
                return true
            }
            return false
        })
    }
    
    func testCleanupLogs_WithSevenDayBoundary_PreservesExactly() async throws {
        // Given: Logs at 6.5 days old (should be preserved) and 7.5 days old (should be deleted)
        let now = Date()
        let sixPointFiveDaysAgo = Calendar.current.date(byAdding: .hour, value: -156, to: now)!  // 6.5 days
        let sevenPointFiveDaysAgo = Calendar.current.date(byAdding: .hour, value: -180, to: now)!  // 7.5 days
        
        let recentLogURL = tempDirectory.appendingPathComponent("recent.log")
        let oldLogURL = tempDirectory.appendingPathComponent("old.log")
        
        try "Recent log".write(to: recentLogURL, atomically: true, encoding: .utf8)
        try "Old log".write(to: oldLogURL, atomically: true, encoding: .utf8)
        
        let recentLog = try createLogFileMetadata(from: recentLogURL, modifiedDate: sixPointFiveDaysAgo)
        let oldLog = try createLogFileMetadata(from: oldLogURL, modifiedDate: sevenPointFiveDaysAgo)
        
        let options = CleanupOptions(createBackup: false, moveToTrash: false, skipInUseFiles: true)
        
        // When: Performing log cleanup
        let result = try await cleanupEngine.cleanupLogs(
            files: [recentLog, oldLog],
            options: options,
            progressHandler: { _ in }
        )
        
        // Then: Old log (7.5 days) should be removed, recent log (6.5 days) preserved
        XCTAssertEqual(result.filesRemoved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentLogURL.path), "6.5-day log should be preserved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldLogURL.path), "7.5-day log should be removed")
    }
    
    // MARK: - Helper Methods
    
    private func createLogFileMetadata(from url: URL, modifiedDate: Date) throws -> FileMetadata {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        let createdDate = attributes[.creationDate] as? Date ?? Date()
        
        return FileMetadata(
            url: url,
            size: size,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            accessedDate: Date(),
            fileType: .log,  // Explicitly set as log file
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
    
    private func createTestFileMetadata(
        path: String,
        size: Int64 = 1024,
        isInUse: Bool = false,
        permissions: FilePermissions = FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
    ) -> FileMetadata {
        return FileMetadata(
            url: URL(fileURLWithPath: path),
            size: size,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary,
            isInUse: isInUse,
            permissions: permissions
        )
    }
    
    private func createFileMetadata(from url: URL) throws -> FileMetadata {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int64 ?? 0
        let createdDate = attributes[.creationDate] as? Date ?? Date()
        let modifiedDate = attributes[.modificationDate] as? Date ?? Date()
        
        return FileMetadata(
            url: url,
            size: size,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            accessedDate: Date(),
            fileType: .temporary,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
}

// MARK: - Mock SafeListManager

class MockSafeListManager: SafeListManager {
    var protectedPaths: Set<String> = []
    
    func isProtected(url: URL) -> Bool {
        return isProtected(path: url.path)
    }
    
    func isProtected(path: String) -> Bool {
        for protectedPath in protectedPaths {
            if path.hasPrefix(protectedPath) {
                return true
            }
        }
        return false
    }
    
    func updateSafeList(for macOSVersion: OperatingSystemVersion) {
        // Mock implementation - do nothing
    }
}

// MARK: - Mock BackupManager

class MockBackupManager: BackupManager {
    var backups: [Backup] = []
    var shouldFailBackup = false
    var shouldFailRestore = false
    var lastBackupFiles: [FileMetadata] = []
    
    func createBackup(files: [FileMetadata], destination: URL) async throws -> BackupResult {
        lastBackupFiles = files
        
        if shouldFailBackup {
            throw CleanupError.backupFailed("Mock backup failure")
        }
        
        let backupURL = destination.appendingPathComponent("mock_backup_\(UUID().uuidString).tar.gz")
        let backup = Backup(
            id: UUID(),
            createdDate: Date(),
            fileCount: files.count,
            originalSize: files.reduce(0) { $0 + $1.size },
            compressedSize: 1000,
            location: backupURL
        )
        backups.append(backup)
        
        return BackupResult(
            backupURL: backupURL,
            filesBackedUp: files.count,
            compressedSize: 1000,
            duration: 0.1
        )
    }
    
    func listBackups() -> [Backup] {
        return backups
    }
    
    func restoreBackup(backup: Backup, destination: URL) async throws -> RestoreResult {
        if shouldFailRestore {
            throw RestoreError.backupCorrupted
        }
        
        return RestoreResult(filesRestored: backup.fileCount, errors: [])
    }
    
    func deleteBackup(backup: Backup) throws {
        backups.removeAll { $0.id == backup.id }
    }
}

