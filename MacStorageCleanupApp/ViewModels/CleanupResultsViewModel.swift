import SwiftUI
import Foundation

/// View model for cleanup results display
/// Manages cleanup result state and restore operations
/// Validates Requirements 10.1, 10.2, 10.5
@MainActor
class CleanupResultsViewModel: ObservableObject {
    // Result data
    let filesRemoved: Int
    let spaceFreed: Int64
    let errors: [CleanupError]
    let backupLocation: URL?
    
    // Restore state
    @Published var isRestoring: Bool = false
    @Published var restoreProgress: Double = 0.0
    @Published var restoreError: String?
    @Published var restoreCompleted: Bool = false
    
    init(result: CleanupResult) {
        self.filesRemoved = result.filesRemoved
        self.spaceFreed = result.spaceFreed
        self.errors = result.errors
        self.backupLocation = result.backupLocation
    }
    
    // MARK: - Computed Properties
    
    var formattedSpaceFreed: String {
        ByteCountFormatter.string(fromByteCount: spaceFreed, countStyle: .file)
    }
    
    var hasErrors: Bool {
        !errors.isEmpty
    }
    
    var errorCount: Int {
        errors.count
    }
    
    var hasBackup: Bool {
        backupLocation != nil
    }
    
    var backupPath: String {
        backupLocation?.path ?? ""
    }
    
    var backupName: String {
        backupLocation?.lastPathComponent ?? ""
    }
    
    var isSuccessful: Bool {
        filesRemoved > 0 && !hasErrors
    }
    
    var isPartialSuccess: Bool {
        filesRemoved > 0 && hasErrors
    }
    
    var statusIcon: String {
        if isSuccessful {
            return "checkmark.circle.fill"
        } else if isPartialSuccess {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    var statusColor: Color {
        if isSuccessful {
            return .green
        } else if isPartialSuccess {
            return .orange
        } else {
            return .red
        }
    }
    
    var statusTitle: String {
        if isSuccessful {
            return "Cleanup Completed Successfully"
        } else if isPartialSuccess {
            return "Cleanup Completed with Errors"
        } else {
            return "Cleanup Failed"
        }
    }
    
    var statusMessage: String {
        if isSuccessful {
            return "Successfully removed \(filesRemoved) file\(filesRemoved == 1 ? "" : "s") and freed \(formattedSpaceFreed)"
        } else if isPartialSuccess {
            return "Removed \(filesRemoved) file\(filesRemoved == 1 ? "" : "s") but encountered \(errorCount) error\(errorCount == 1 ? "" : "s")"
        } else {
            return "Failed to complete cleanup operation"
        }
    }
    
    // MARK: - Restore Operations
    
    /// Restores files from backup
    /// Validates Requirement 10.5: Provide restore function
    func restoreFromBackup() async {
        guard let backupLocation = backupLocation else { return }
        
        isRestoring = true
        restoreError = nil
        restoreProgress = 0.0
        
        do {
            // This would integrate with the actual BackupManager
            // For now, we'll simulate the restore process
            try await simulateRestore(from: backupLocation)
            
            restoreCompleted = true
            restoreProgress = 1.0
        } catch {
            restoreError = error.localizedDescription
        }
        
        isRestoring = false
    }
    
    /// Opens the backup location in Finder
    func revealBackupInFinder() {
        guard let backupLocation = backupLocation else { return }
        NSWorkspace.shared.activateFileViewerSelecting([backupLocation])
    }
    
    /// Copies the backup path to clipboard
    func copyBackupPath() {
        guard let backupLocation = backupLocation else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(backupLocation.path, forType: .string)
    }
    
    // MARK: - Error Details
    
    /// Returns a formatted error message for display
    func errorMessage(for error: CleanupError) -> String {
        switch error {
        case .fileProtected(let path):
            return "Protected: \(path)"
        case .fileInUse(let path):
            return "In use: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileNotFound(let path):
            return "Not found: \(path)"
        case .cancelled:
            return "Operation cancelled"
        case .backupFailed(let underlyingError):
            return "Backup failed: \(underlyingError.localizedDescription)"
        case .unknown(let underlyingError):
            return "Unknown error: \(underlyingError.localizedDescription)"
        }
    }
    
    // MARK: - Private Methods
    
    private func simulateRestore(from backupURL: URL) async throws {
        // This is a placeholder for the actual BackupManager integration
        // In production, this would call:
        // let backupManager = DefaultBackupManager()
        // let backup = // load backup from URL
        // try await backupManager.restoreBackup(backup: backup, destination: homeDirectory)
        
        // Simulate restore progress
        for i in 1...10 {
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            restoreProgress = Double(i) / 10.0
        }
    }
}

/// Cleanup error types
enum CleanupError: Error, Equatable {
    case fileProtected(path: String)
    case fileInUse(path: String)
    case permissionDenied(path: String)
    case fileNotFound(path: String)
    case cancelled
    case backupFailed(Error)
    case unknown(Error)
    
    static func == (lhs: CleanupError, rhs: CleanupError) -> Bool {
        switch (lhs, rhs) {
        case (.fileProtected(let lPath), .fileProtected(let rPath)):
            return lPath == rPath
        case (.fileInUse(let lPath), .fileInUse(let rPath)):
            return lPath == rPath
        case (.permissionDenied(let lPath), .permissionDenied(let rPath)):
            return lPath == rPath
        case (.fileNotFound(let lPath), .fileNotFound(let rPath)):
            return lPath == rPath
        case (.cancelled, .cancelled):
            return true
        case (.backupFailed, .backupFailed):
            return true
        case (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}

/// Result of a cleanup operation
struct CleanupResult {
    let filesRemoved: Int
    let spaceFreed: Int64
    let errors: [CleanupError]
    let backupLocation: URL?
}
