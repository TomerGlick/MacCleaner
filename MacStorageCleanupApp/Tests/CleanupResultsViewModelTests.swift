import XCTest
@testable import MacStorageCleanupApp

/// Tests for CleanupResultsViewModel
/// Validates Requirements 10.1, 10.2, 10.5: Backup and restore functionality
@MainActor
final class CleanupResultsViewModelTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationWithSuccessfulResult() {
        // Given
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: URL(fileURLWithPath: "/tmp/backup.tar.gz")
        )
        
        // When
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertEqual(viewModel.filesRemoved, 10)
        XCTAssertEqual(viewModel.spaceFreed, 5_000_000_000)
        XCTAssertFalse(viewModel.hasErrors)
        XCTAssertTrue(viewModel.hasBackup)
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertFalse(viewModel.restoreCompleted)
        XCTAssertNil(viewModel.restoreError)
    }
    
    func testInitializationWithErrors() {
        // Given
        let result = CleanupResult(
            filesRemoved: 5,
            spaceFreed: 2_000_000_000,
            errors: [
                .fileInUse(path: "/tmp/file1.tmp"),
                .permissionDenied(path: "/tmp/file2.tmp")
            ],
            backupLocation: nil
        )
        
        // When
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertEqual(viewModel.filesRemoved, 5)
        XCTAssertTrue(viewModel.hasErrors)
        XCTAssertEqual(viewModel.errorCount, 2)
        XCTAssertFalse(viewModel.hasBackup)
    }
    
    // MARK: - Computed Properties Tests
    
    func testFormattedSpaceFreed() {
        // Given
        let result = CleanupResult(
            filesRemoved: 1,
            spaceFreed: 1_500_000_000, // 1.5 GB
            errors: [],
            backupLocation: nil
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // When
        let formatted = viewModel.formattedSpaceFreed
        
        // Then
        XCTAssertTrue(formatted.contains("GB") || formatted.contains("1"))
    }
    
    func testBackupProperties() {
        // Given
        let backupURL = URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup_2024-01-15.tar.gz")
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 1_000_000_000,
            errors: [],
            backupLocation: backupURL
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertTrue(viewModel.hasBackup)
        XCTAssertEqual(viewModel.backupPath, backupURL.path)
        XCTAssertEqual(viewModel.backupName, "backup_2024-01-15.tar.gz")
    }
    
    func testStatusPropertiesForSuccess() {
        // Given
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: nil
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertTrue(viewModel.isSuccessful)
        XCTAssertFalse(viewModel.isPartialSuccess)
        XCTAssertEqual(viewModel.statusIcon, "checkmark.circle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Completed Successfully")
        XCTAssertTrue(viewModel.statusMessage.contains("Successfully removed"))
    }
    
    func testStatusPropertiesForPartialSuccess() {
        // Given
        let result = CleanupResult(
            filesRemoved: 8,
            spaceFreed: 4_000_000_000,
            errors: [
                .fileInUse(path: "/tmp/file1.tmp"),
                .permissionDenied(path: "/tmp/file2.tmp")
            ],
            backupLocation: nil
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertFalse(viewModel.isSuccessful)
        XCTAssertTrue(viewModel.isPartialSuccess)
        XCTAssertEqual(viewModel.statusIcon, "exclamationmark.triangle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Completed with Errors")
        XCTAssertTrue(viewModel.statusMessage.contains("encountered 2 error"))
    }
    
    func testStatusPropertiesForFailure() {
        // Given
        let result = CleanupResult(
            filesRemoved: 0,
            spaceFreed: 0,
            errors: [.cancelled],
            backupLocation: nil
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Then
        XCTAssertFalse(viewModel.isSuccessful)
        XCTAssertFalse(viewModel.isPartialSuccess)
        XCTAssertEqual(viewModel.statusIcon, "xmark.circle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Failed")
    }
    
    // MARK: - Error Message Tests
    
    func testErrorMessageFormatting() {
        // Given
        let result = CleanupResult(filesRemoved: 0, spaceFreed: 0, errors: [], backupLocation: nil)
        let viewModel = CleanupResultsViewModel(result: result)
        
        // Test different error types
        let fileProtectedError = CleanupError.fileProtected(path: "/System/test.cache")
        XCTAssertEqual(viewModel.errorMessage(for: fileProtectedError), "Protected: /System/test.cache")
        
        let fileInUseError = CleanupError.fileInUse(path: "/tmp/active.tmp")
        XCTAssertEqual(viewModel.errorMessage(for: fileInUseError), "In use: /tmp/active.tmp")
        
        let permissionError = CleanupError.permissionDenied(path: "/root/file.txt")
        XCTAssertEqual(viewModel.errorMessage(for: permissionError), "Permission denied: /root/file.txt")
        
        let notFoundError = CleanupError.fileNotFound(path: "/tmp/missing.tmp")
        XCTAssertEqual(viewModel.errorMessage(for: notFoundError), "Not found: /tmp/missing.tmp")
        
        let cancelledError = CleanupError.cancelled
        XCTAssertEqual(viewModel.errorMessage(for: cancelledError), "Operation cancelled")
        
        let backupError = CleanupError.backupFailed(NSError(domain: "Test", code: 1))
        XCTAssertTrue(viewModel.errorMessage(for: backupError).contains("Backup failed"))
        
        let unknownError = CleanupError.unknown(NSError(domain: "Test", code: 2))
        XCTAssertTrue(viewModel.errorMessage(for: unknownError).contains("Unknown error"))
    }
    
    // MARK: - Restore Operation Tests
    
    func testRestoreFromBackupWithNoBackup() async {
        // Given
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: nil
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // When
        await viewModel.restoreFromBackup()
        
        // Then
        XCTAssertFalse(viewModel.isRestoring)
        XCTAssertFalse(viewModel.restoreCompleted)
    }
    
    func testRestoreFromBackupWithBackup() async {
        // Given
        let backupURL = URL(fileURLWithPath: "/tmp/backup.tar.gz")
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: backupURL
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // When
        await viewModel.restoreFromBackup()
        
        // Then
        XCTAssertFalse(viewModel.isRestoring) // Should be done
        XCTAssertTrue(viewModel.restoreCompleted)
        XCTAssertEqual(viewModel.restoreProgress, 1.0)
        XCTAssertNil(viewModel.restoreError)
    }
    
    func testRestoreProgressUpdates() async {
        // Given
        let backupURL = URL(fileURLWithPath: "/tmp/backup.tar.gz")
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: backupURL
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // When
        let restoreTask = Task {
            await viewModel.restoreFromBackup()
        }
        
        // Wait a bit and check progress
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then - should be in progress or completed
        let progressDuringRestore = viewModel.restoreProgress
        
        await restoreTask.value
        
        // Final state
        XCTAssertTrue(progressDuringRestore >= 0.0 && progressDuringRestore <= 1.0)
        XCTAssertEqual(viewModel.restoreProgress, 1.0)
        XCTAssertTrue(viewModel.restoreCompleted)
    }
    
    // MARK: - Backup Location Actions Tests
    
    func testCopyBackupPath() {
        // Given
        let backupURL = URL(fileURLWithPath: "/tmp/backup.tar.gz")
        let result = CleanupResult(
            filesRemoved: 10,
            spaceFreed: 5_000_000_000,
            errors: [],
            backupLocation: backupURL
        )
        let viewModel = CleanupResultsViewModel(result: result)
        
        // When
        viewModel.copyBackupPath()
        
        // Then
        let pasteboard = NSPasteboard.general
        let copiedString = pasteboard.string(forType: .string)
        XCTAssertEqual(copiedString, backupURL.path)
    }
    
    // MARK: - CleanupResult Tests
    
    func testCleanupResultCreation() {
        // When
        let result = CleanupResult(
            filesRemoved: 15,
            spaceFreed: 7_500_000_000,
            errors: [.fileInUse(path: "/tmp/test.tmp")],
            backupLocation: URL(fileURLWithPath: "/tmp/backup.tar.gz")
        )
        
        // Then
        XCTAssertEqual(result.filesRemoved, 15)
        XCTAssertEqual(result.spaceFreed, 7_500_000_000)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertNotNil(result.backupLocation)
    }
    
    // MARK: - CleanupError Equality Tests
    
    func testCleanupErrorEquality() {
        // Test fileProtected
        XCTAssertEqual(
            CleanupError.fileProtected(path: "/test"),
            CleanupError.fileProtected(path: "/test")
        )
        XCTAssertNotEqual(
            CleanupError.fileProtected(path: "/test1"),
            CleanupError.fileProtected(path: "/test2")
        )
        
        // Test fileInUse
        XCTAssertEqual(
            CleanupError.fileInUse(path: "/test"),
            CleanupError.fileInUse(path: "/test")
        )
        
        // Test permissionDenied
        XCTAssertEqual(
            CleanupError.permissionDenied(path: "/test"),
            CleanupError.permissionDenied(path: "/test")
        )
        
        // Test fileNotFound
        XCTAssertEqual(
            CleanupError.fileNotFound(path: "/test"),
            CleanupError.fileNotFound(path: "/test")
        )
        
        // Test cancelled
        XCTAssertEqual(CleanupError.cancelled, CleanupError.cancelled)
        
        // Test different types are not equal
        XCTAssertNotEqual(
            CleanupError.fileProtected(path: "/test"),
            CleanupError.fileInUse(path: "/test")
        )
    }
}
