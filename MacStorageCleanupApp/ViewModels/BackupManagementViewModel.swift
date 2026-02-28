import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class BackupManagementViewModel: ObservableObject {
    @Published var backups: [Backup] = []
    @Published var isLoading = false
    @Published var selectedBackup: Backup?
    @Published var showRestoreDialog = false
    @Published var showDeleteConfirmation = false
    @Published var isRestoring = false
    @Published var isDeleting = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    
    private let backupManager: BackupManager
    
    init(backupManager: BackupManager = DefaultBackupManager()) {
        self.backupManager = backupManager
    }
    
    var sortedBackups: [Backup] {
        backups.sorted { $0.createdDate > $1.createdDate }
    }
    
    var oldBackups: [Backup] {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return backups.filter { $0.createdDate < thirtyDaysAgo }
    }
    
    var hasOldBackups: Bool {
        !oldBackups.isEmpty
    }
    
    var oldBackupsPrompt: String {
        let count = oldBackups.count
        let totalSize = oldBackups.reduce(0) { $0 + $1.compressedSize }
        let sizeString = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        return "You have \(count) backup\(count == 1 ? "" : "s") older than 30 days (\(sizeString)). Consider removing them to free up space."
    }
    
    func loadBackups() {
        isLoading = true
        errorMessage = nil
        
        backups = backupManager.listBackups()
        
        isLoading = false
    }
    
    func cancelLoad() {
        isLoading = false
    }
    
    func selectBackup(_ backup: Backup) {
        selectedBackup = backup
    }
    
    func requestRestore(_ backup: Backup) {
        selectedBackup = backup
        showRestoreDialog = true
    }
    
    func requestDelete(_ backup: Backup) {
        selectedBackup = backup
        showDeleteConfirmation = true
    }
    
    func performRestore(destination: URL) async {
        guard let backup = selectedBackup else { return }
        
        isRestoring = true
        errorMessage = nil
        successMessage = nil
        
        do {
            let result = try await backupManager.restoreBackup(backup: backup, destination: destination)
            
            if result.errors.isEmpty {
                successMessage = "Successfully restored \(result.filesRestored) files"
            } else {
                successMessage = "Restored \(result.filesRestored) files with \(result.errors.count) errors"
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
        
        isRestoring = false
        showRestoreDialog = false
    }
    
    func performDelete() {
        guard let backup = selectedBackup else { return }
        
        isDeleting = true
        errorMessage = nil
        successMessage = nil
        
        do {
            try backupManager.deleteBackup(backup: backup)
            backups.removeAll { $0.id == backup.id }
            successMessage = "Backup deleted successfully"
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
        
        isDeleting = false
        showDeleteConfirmation = false
        selectedBackup = nil
    }
    
    func deleteOldBackups() {
        isDeleting = true
        errorMessage = nil
        
        var deletedCount = 0
        var errors: [String] = []
        
        for backup in oldBackups {
            do {
                try backupManager.deleteBackup(backup: backup)
                backups.removeAll { $0.id == backup.id }
                deletedCount += 1
            } catch {
                errors.append("Failed to delete backup from \(formatDate(backup.createdDate)): \(error.localizedDescription)")
            }
        }
        
        if errors.isEmpty {
            successMessage = "Deleted \(deletedCount) old backup\(deletedCount == 1 ? "" : "s")"
        } else {
            errorMessage = "Deleted \(deletedCount) backups with \(errors.count) errors"
        }
        
        isDeleting = false
    }
    
    func cancelRestore() {
        showRestoreDialog = false
        selectedBackup = nil
    }
    
    func cancelDelete() {
        showDeleteConfirmation = false
        selectedBackup = nil
    }
    
    func dismissMessages() {
        errorMessage = nil
        successMessage = nil
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // Preview helper
    static var preview: BackupManagementViewModel {
        let vm = BackupManagementViewModel()
        vm.backups = [
            Backup(
                createdDate: Date(),
                fileCount: 150,
                originalSize: 500_000_000,
                compressedSize: 250_000_000,
                location: URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup-2024-01-15.zip")
            ),
            Backup(
                createdDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
                fileCount: 200,
                originalSize: 800_000_000,
                compressedSize: 400_000_000,
                location: URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup-2024-01-08.zip")
            ),
            Backup(
                createdDate: Date().addingTimeInterval(-35 * 24 * 60 * 60),
                fileCount: 100,
                originalSize: 300_000_000,
                compressedSize: 150_000_000,
                location: URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup-2023-12-11.zip")
            )
        ]
        return vm
    }
}
