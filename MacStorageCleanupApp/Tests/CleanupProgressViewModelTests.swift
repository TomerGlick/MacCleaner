import XCTest
@testable import MacStorageCleanupApp

/// Tests for CleanupProgressViewModel
/// Validates Requirement 9.5: Cleanup progress display and cancellation
@MainActor
final class CleanupProgressViewModelTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        // Given
        let files = createSampleFiles(count: 5)
        let options = CleanupOptions()
        
        // When
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: options)
        
        // Then
        XCTAssertEqual(viewModel.totalFiles, 5)
        XCTAssertEqual(viewModel.filesProcessed, 0)
        XCTAssertEqual(viewModel.spaceFreed, 0)
        XCTAssertEqual(viewModel.errorCount, 0)
        XCTAssertEqual(viewModel.progress, 0.0)
        XCTAssertEqual(viewModel.status, .notStarted)
        XCTAssertTrue(viewModel.currentFile.isEmpty)
    }
    
    // MARK: - Progress Calculation Tests
    
    func testPercentageText() {
        // Given
        let files = createSampleFiles(count: 10)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.progress = 0.0
        let zeroPercent = viewModel.percentageText
        
        viewModel.progress = 0.5
        let fiftyPercent = viewModel.percentageText
        
        viewModel.progress = 1.0
        let hundredPercent = viewModel.percentageText
        
        // Then
        XCTAssertEqual(zeroPercent, "0%")
        XCTAssertEqual(fiftyPercent, "50%")
        XCTAssertEqual(hundredPercent, "100%")
    }
    
    func testFormattedSpaceFreed() {
        // Given
        let files = createSampleFiles(count: 1)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.spaceFreed = 0
        let zeroBytes = viewModel.formattedSpaceFreed
        
        viewModel.spaceFreed = 1_000_000 // 1 MB
        let oneMB = viewModel.formattedSpaceFreed
        
        viewModel.spaceFreed = 1_000_000_000 // 1 GB
        let oneGB = viewModel.formattedSpaceFreed
        
        // Then
        XCTAssertEqual(zeroBytes, "Zero KB")
        XCTAssertTrue(oneMB.contains("MB"))
        XCTAssertTrue(oneGB.contains("GB"))
    }
    
    // MARK: - Status Tests
    
    func testStatusProperties() {
        // Given
        let files = createSampleFiles(count: 1)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // Test notStarted
        XCTAssertFalse(viewModel.isInProgress)
        XCTAssertFalse(viewModel.isCompleted)
        XCTAssertFalse(viewModel.isCancelled)
        XCTAssertEqual(viewModel.statusIcon, "hourglass")
        XCTAssertEqual(viewModel.statusTitle, "Preparing Cleanup")
        
        // Test inProgress
        viewModel.status = .inProgress
        XCTAssertTrue(viewModel.isInProgress)
        XCTAssertFalse(viewModel.isCompleted)
        XCTAssertFalse(viewModel.isCancelled)
        XCTAssertEqual(viewModel.statusIcon, "arrow.clockwise.circle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleaning Up Files")
        
        // Test completed
        viewModel.status = .completed
        XCTAssertFalse(viewModel.isInProgress)
        XCTAssertTrue(viewModel.isCompleted)
        XCTAssertFalse(viewModel.isCancelled)
        XCTAssertEqual(viewModel.statusIcon, "checkmark.circle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Complete")
        
        // Test cancelled
        viewModel.status = .cancelled
        XCTAssertFalse(viewModel.isInProgress)
        XCTAssertFalse(viewModel.isCompleted)
        XCTAssertTrue(viewModel.isCancelled)
        XCTAssertEqual(viewModel.statusIcon, "xmark.circle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Cancelled")
        
        // Test failed
        viewModel.status = .failed
        XCTAssertEqual(viewModel.statusIcon, "exclamationmark.triangle.fill")
        XCTAssertEqual(viewModel.statusTitle, "Cleanup Failed")
    }
    
    func testStatusMessageWithErrors() {
        // Given
        let files = createSampleFiles(count: 1)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When - completed with no errors
        viewModel.status = .completed
        viewModel.errorCount = 0
        viewModel.spaceFreed = 1_000_000_000
        let noErrorsMessage = viewModel.statusMessage
        
        // When - completed with errors
        viewModel.errorCount = 3
        let withErrorsMessage = viewModel.statusMessage
        
        // Then
        XCTAssertTrue(noErrorsMessage.contains("Successfully freed"))
        XCTAssertTrue(withErrorsMessage.contains("3 errors"))
    }
    
    // MARK: - Cleanup Operation Tests
    
    func testStartCleanupChangesStatus() async {
        // Given
        let files = createSampleFiles(count: 2)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.startCleanup()
        
        // Then
        XCTAssertEqual(viewModel.status, .inProgress)
    }
    
    func testStartCleanupOnlyWorksOnce() {
        // Given
        let files = createSampleFiles(count: 1)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.startCleanup()
        let firstStatus = viewModel.status
        
        viewModel.status = .completed
        viewModel.startCleanup() // Should not restart
        let secondStatus = viewModel.status
        
        // Then
        XCTAssertEqual(firstStatus, .inProgress)
        XCTAssertEqual(secondStatus, .completed) // Should remain completed
    }
    
    func testCancelCleanup() {
        // Given
        let files = createSampleFiles(count: 5)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.startCleanup()
        XCTAssertEqual(viewModel.status, .inProgress)
        
        viewModel.cancelCleanup()
        
        // Then
        XCTAssertEqual(viewModel.status, .cancelled)
    }
    
    func testCancelCleanupOnlyWorksWhenInProgress() {
        // Given
        let files = createSampleFiles(count: 1)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When - try to cancel when not started
        viewModel.cancelCleanup()
        
        // Then
        XCTAssertEqual(viewModel.status, .notStarted) // Should remain not started
    }
    
    // MARK: - Progress Update Tests
    
    func testProgressUpdates() async {
        // Given
        let files = createSampleFiles(count: 3)
        let viewModel = CleanupProgressViewModel(filesToClean: files, options: CleanupOptions())
        
        // When
        viewModel.startCleanup()
        
        // Wait for cleanup to complete (with timeout)
        let expectation = XCTestExpectation(description: "Cleanup completes")
        
        Task {
            // Poll for completion
            for _ in 0..<50 { // 5 seconds max
                if viewModel.status == .completed || viewModel.status == .cancelled {
                    expectation.fulfill()
                    break
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
        }
        
        await fulfillment(of: [expectation], timeout: 6.0)
        
        // Then
        XCTAssertTrue(viewModel.status == .completed || viewModel.status == .cancelled)
        if viewModel.status == .completed {
            XCTAssertEqual(viewModel.filesProcessed, 3)
            XCTAssertEqual(viewModel.progress, 1.0)
            XCTAssertGreaterThan(viewModel.spaceFreed, 0)
        }
    }
    
    // MARK: - CleanupOptions Tests
    
    func testCleanupOptionsDefaults() {
        // When
        let options = CleanupOptions()
        
        // Then
        XCTAssertFalse(options.createBackup)
        XCTAssertTrue(options.moveToTrash)
        XCTAssertTrue(options.skipInUseFiles)
    }
    
    func testCleanupOptionsCustomValues() {
        // When
        let options = CleanupOptions(
            createBackup: true,
            moveToTrash: false,
            skipInUseFiles: false
        )
        
        // Then
        XCTAssertTrue(options.createBackup)
        XCTAssertFalse(options.moveToTrash)
        XCTAssertFalse(options.skipInUseFiles)
    }
    
    // MARK: - Helper Methods
    
    private func createSampleFiles(count: Int) -> [CleanupCandidateData] {
        return (0..<count).map { index in
            CleanupCandidateData(
                path: "/tmp/file\(index).tmp",
                name: "file\(index).tmp",
                size: Int64((index + 1) * 1_000_000), // 1MB, 2MB, 3MB, etc.
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .temporary,
                category: .temporaryFiles
            )
        }
    }
}
