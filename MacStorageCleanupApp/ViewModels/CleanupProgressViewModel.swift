import SwiftUI
import Foundation
import MacStorageCleanupCore

/// View model for cleanup progress tracking
/// Manages cleanup operation state and progress updates
/// Validates Requirement 9.5
@MainActor
class CleanupProgressViewModel: ObservableObject {
    // Progress state
    @Published var currentFile: String = ""
    @Published var filesProcessed: Int = 0
    @Published var spaceFreed: Int64 = 0
    @Published var errorCount: Int = 0
    @Published var progress: Double = 0.0
    @Published var status: CleanupStatus = .notStarted
    
    let totalFiles: Int
    private let filesToClean: [CleanupCandidateData]
    private let options: CleanupOptions
    private var cleanupTask: Task<Void, Never>?
    
    enum CleanupStatus {
        case notStarted
        case inProgress
        case completed
        case cancelled
        case failed
    }
    
    init(filesToClean: [CleanupCandidateData], options: CleanupOptions) {
        self.filesToClean = filesToClean
        self.options = options
        self.totalFiles = filesToClean.count
    }
    
    // MARK: - Computed Properties
    
    var percentageText: String {
        String(format: "%.0f%%", progress * 100)
    }
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: spaceFreed, countStyle: .file)
    }
    
    var isInProgress: Bool {
        status == .inProgress
    }
    
    var isCompleted: Bool {
        status == .completed
    }
    
    var isCancelled: Bool {
        status == .cancelled
    }
    
    var statusIcon: String {
        switch status {
        case .notStarted:
            return "hourglass"
        case .inProgress:
            return "arrow.clockwise.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .notStarted:
            return .gray
        case .inProgress:
            return .blue
        case .completed:
            return .green
        case .cancelled:
            return .orange
        case .failed:
            return .red
        }
    }
    
    var statusTitle: String {
        switch status {
        case .notStarted:
            return "Preparing Cleanup"
        case .inProgress:
            return "Cleaning Up Files"
        case .completed:
            return "Cleanup Complete"
        case .cancelled:
            return "Cleanup Cancelled"
        case .failed:
            return "Cleanup Failed"
        }
    }
    
    var statusMessage: String {
        switch status {
        case .notStarted:
            return "Initializing cleanup operation..."
        case .inProgress:
            return "Removing selected files and freeing up space"
        case .completed:
            if errorCount > 0 {
                return "Completed with \(errorCount) error\(errorCount == 1 ? "" : "s")"
            }
            return "Successfully freed \(formattedSpaceFreed)"
        case .cancelled:
            return "Operation was cancelled by user"
        case .failed:
            return "An error occurred during cleanup"
        }
    }
    
    // MARK: - Cleanup Operations
    
    /// Starts the cleanup operation
    /// Validates Requirement 9.5: Display progress with ability to cancel
    func startCleanup() {
        guard status == .notStarted else { return }
        
        status = .inProgress
        
        cleanupTask = Task {
            await performCleanup()
        }
    }
    
    /// Cancels the ongoing cleanup operation
    /// Validates Requirement 9.5: Provide cancel button with confirmation
    func cancelCleanup() {
        guard status == .inProgress else { return }
        
        cleanupTask?.cancel()
        status = .cancelled
    }
    
    // MARK: - Private Methods
    
    private func performCleanup() async {
        let coordinator = ApplicationCoordinator.shared
        
        print("DEBUG: Starting cleanup of \(filesToClean.count) items")
        
        // Convert CleanupCandidateData to FileMetadata
        let fileMetadataList = filesToClean.map { candidate in
            print("DEBUG: Preparing to clean: \(candidate.path)")
            return FileMetadata(
                url: URL(fileURLWithPath: candidate.path),
                size: candidate.size,
                createdDate: candidate.modifiedDate,
                modifiedDate: candidate.modifiedDate,
                accessedDate: candidate.accessedDate,
                fileType: .cache,
                isInUse: false,
                permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
            )
        }
        
        do {
            print("DEBUG: Calling performCleanup with options: moveToTrash=\(options.moveToTrash), createBackup=\(options.createBackup)")
            let result = try await coordinator.performCleanup(
                files: fileMetadataList,
                options: options,
                progressHandler: { progress in
                    Task { @MainActor in
                        self.currentFile = progress.currentFile
                        self.filesProcessed = progress.filesProcessed
                        self.spaceFreed = progress.spaceFreed
                        self.progress = Double(progress.filesProcessed) / Double(self.totalFiles)
                    }
                }
            )
            
            print("DEBUG: Cleanup result - filesRemoved: \(result.filesRemoved), spaceFreed: \(result.spaceFreed), errors: \(result.errors.count)")
            for error in result.errors {
                print("DEBUG: Cleanup error: \(error)")
            }
            
            // Cleanup completed
            status = .completed
            currentFile = ""
            errorCount = result.errors.count
            
        } catch {
            print("DEBUG: Cleanup threw error: \(error)")
            status = .cancelled
            errorCount += 1
        }
    }
    
    private func simulateFileDeletion(_ file: CleanupCandidateData) async throws {
        // No longer used - kept for compatibility
    }
}

/// Options for cleanup operations
struct CleanupOptions {
    let createBackup: Bool
    let moveToTrash: Bool
    let skipInUseFiles: Bool
    
    init(createBackup: Bool = false, moveToTrash: Bool = true, skipInUseFiles: Bool = true) {
        self.createBackup = createBackup
        self.moveToTrash = moveToTrash
        self.skipInUseFiles = skipInUseFiles
    }
}
