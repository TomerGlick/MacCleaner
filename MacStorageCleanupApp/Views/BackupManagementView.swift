import SwiftUI
import MacStorageCleanupCore

/// View for managing backups - list, restore, and delete
struct BackupManagementView: View {
    @StateObject private var viewModel = BackupManagementViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Old backups prompt
            if viewModel.hasOldBackups {
                oldBackupsPrompt
                Divider()
            }
            
            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.backups.isEmpty {
                emptyStateView
            } else {
                backupsList
            }
            
            // Messages
            if viewModel.errorMessage != nil || viewModel.successMessage != nil {
                Divider()
                messagesView
            }
        }
        .sheet(isPresented: $viewModel.showRestoreDialog) {
            if let backup = viewModel.selectedBackup {
                RestoreBackupDialog(
                    backup: backup,
                    isRestoring: viewModel.isRestoring,
                    onRestore: { destination in
                        Task {
                            await viewModel.performRestore(destination: destination)
                        }
                    },
                    onCancel: {
                        viewModel.cancelRestore()
                    }
                )
            }
        }
        .alert("Delete Backup", isPresented: $viewModel.showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelDelete()
            }
            Button("Delete", role: .destructive) {
                viewModel.performDelete()
            }
        } message: {
            if let backup = viewModel.selectedBackup {
                Text("Are you sure you want to delete the backup from \(formatDate(backup.createdDate))? This action cannot be undone.")
            }
        }
        .onAppear {
            viewModel.loadBackups()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Backup Management")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button(action: {
                viewModel.loadBackups()
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh backups list")
        }
        .padding()
    }
    
    // MARK: - Old Backups Prompt
    
    private var oldBackupsPrompt: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Old Backups Detected")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text(viewModel.oldBackupsPrompt)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Delete Old Backups") {
                viewModel.deleteOldBackups()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isDeleting)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - Backups List
    
    private var backupsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.sortedBackups, id: \.id) { backup in
                    BackupRow(
                        backup: backup,
                        isOld: isOldBackup(backup),
                        onRestore: {
                            viewModel.requestRestore(backup)
                        },
                        onDelete: {
                            viewModel.requestDelete(backup)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading backups...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Backups")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Backups will appear here when you perform cleanup operations with backup enabled")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Messages View
    
    private var messagesView: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dismissMessages()
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(Color.red.opacity(0.1))
            }
            
            if let successMessage = viewModel.successMessage {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(successMessage)
                        .font(.body)
                        .foregroundColor(.green)
                    Spacer()
                    Button("Dismiss") {
                        viewModel.dismissMessages()
                    }
                    .buttonStyle(.borderless)
                }
                .padding()
                .background(Color.green.opacity(0.1))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func isOldBackup(_ backup: Backup) -> Bool {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        return backup.createdDate < thirtyDaysAgo
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Backup Row

struct BackupRow: View {
    let backup: Backup
    let isOld: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "archivebox.fill")
                .font(.system(size: 32))
                .foregroundColor(isOld ? .orange : .blue)
                .frame(width: 40, height: 40)
            
            // Backup info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(formatDate(backup.createdDate))
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if isOld {
                        Text("Old")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    Text("\(backup.fileCount) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("Original: \(ByteCountFormatter.string(fromByteCount: backup.originalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text("Compressed: \(ByteCountFormatter.string(fromByteCount: backup.compressedSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onRestore) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restore")
                    }
                }
                .buttonStyle(.bordered)
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Restore Backup Dialog

struct RestoreBackupDialog: View {
    let backup: Backup
    let isRestoring: Bool
    let onRestore: (URL) -> Void
    let onCancel: () -> Void
    
    @State private var selectedDestination: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Restore Backup")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Created \(formatDate(backup.createdDate))")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Backup details
            VStack(alignment: .leading, spacing: 12) {
                detailRow(label: "Files", value: "\(backup.fileCount)")
                detailRow(label: "Original Size", value: ByteCountFormatter.string(fromByteCount: backup.originalSize, countStyle: .file))
                detailRow(label: "Compressed Size", value: ByteCountFormatter.string(fromByteCount: backup.compressedSize, countStyle: .file))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Destination selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Restore Destination")
                    .font(.headline)
                
                HStack {
                    if let destination = selectedDestination {
                        Text(destination.path)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Select a destination folder...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Choose...") {
                        selectDestination()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRestoring)
                
                Spacer()
                
                Button(action: {
                    if let destination = selectedDestination {
                        onRestore(destination)
                    }
                }) {
                    HStack {
                        if isRestoring {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        Text(isRestoring ? "Restoring..." : "Restore")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedDestination == nil || isRestoring)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func selectDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select destination for restored files"
        
        if panel.runModal() == .OK {
            selectedDestination = panel.url
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    BackupManagementView()
        .frame(width: 800, height: 600)
}
