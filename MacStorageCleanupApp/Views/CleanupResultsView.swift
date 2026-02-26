import SwiftUI

/// View that displays cleanup results with backup and restore options
/// Validates Requirements 10.1, 10.2, 10.5
struct CleanupResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CleanupResultsViewModel
    @State private var showingRestoreConfirmation = false
    @State private var showingErrorDetails = false
    
    init(result: CleanupResult) {
        _viewModel = StateObject(wrappedValue: CleanupResultsViewModel(result: result))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Results content
            ScrollView {
                resultsContentView
            }
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(width: 600, height: 500)
        .alert("Restore from Backup?", isPresented: $showingRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                Task {
                    await viewModel.restoreFromBackup()
                }
            }
        } message: {
            Text("This will restore all files from the backup. Any changes made since the cleanup will be lost.")
        }
        .sheet(isPresented: $showingErrorDetails) {
            errorDetailsSheet
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .font(.system(size: 48))
                    .foregroundColor(viewModel.statusColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.statusTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
        }
        .padding()
    }
    
    private var resultsContentView: some View {
        VStack(spacing: 24) {
            // Summary statistics
            summarySection
            
            // Backup information (if backup was created)
            if viewModel.hasBackup {
                backupSection
            }
            
            // Error information (if errors occurred)
            if viewModel.hasErrors {
                errorSection
            }
            
            // Restore progress (if restoring)
            if viewModel.isRestoring {
                restoreProgressSection
            }
            
            // Restore success message
            if viewModel.restoreCompleted {
                restoreSuccessSection
            }
            
            // Restore error message
            if let error = viewModel.restoreError {
                restoreErrorSection(error: error)
            }
        }
        .padding()
    }
    
    private var summarySection: some View {
        VStack(spacing: 16) {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 40) {
                ResultStatView(
                    icon: "doc.fill",
                    label: "Files Removed",
                    value: "\(viewModel.filesRemoved)",
                    color: .blue
                )
                
                ResultStatView(
                    icon: "arrow.down.circle.fill",
                    label: "Space Freed",
                    value: viewModel.formattedSpaceFreed,
                    color: .green
                )
                
                if viewModel.hasErrors {
                    ResultStatView(
                        icon: "exclamationmark.triangle.fill",
                        label: "Errors",
                        value: "\(viewModel.errorCount)",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var backupSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Backup Information")
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Backup Location:")
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                HStack(spacing: 8) {
                    Text(viewModel.backupName)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    
                    Spacer()
                    
                    Button(action: viewModel.revealBackupInFinder) {
                        Image(systemName: "folder.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                    
                    Button(action: viewModel.copyBackupPath) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy path")
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var errorSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Errors Encountered")
                    .font(.headline)
                
                Spacer()
                
                Button("View Details") {
                    showingErrorDetails = true
                }
                .buttonStyle(.link)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("\(viewModel.errorCount) file\(viewModel.errorCount == 1 ? "" : "s") could not be removed")
                        .font(.subheadline)
                }
                
                Text("Some files may be in use or protected. Click 'View Details' to see the full error list.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var restoreProgressSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Restoring from Backup")
                    .font(.headline)
                
                Spacer()
                
                ProgressView()
                    .scaleEffect(0.8)
            }
            
            ProgressView(value: viewModel.restoreProgress, total: 1.0)
                .progressViewStyle(.linear)
            
            Text("Restoring files to their original locations...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var restoreSuccessSection: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore Completed")
                    .font(.headline)
                
                Text("All files have been restored from the backup")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func restoreErrorSection(error: String) -> some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore Failed")
                    .font(.headline)
                
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var footerView: some View {
        HStack {
            if viewModel.hasBackup && !viewModel.isRestoring && !viewModel.restoreCompleted {
                Button("Restore from Backup") {
                    showingRestoreConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private var errorDetailsSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Error Details")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showingErrorDetails = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Error list
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(viewModel.errors.enumerated()), id: \.offset) { index, error in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.errorMessage(for: error))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        
                        if index < viewModel.errors.count - 1 {
                            Divider()
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Close") {
                    showingErrorDetails = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}

/// Displays a single result statistic with icon, label, and value
private struct ResultStatView: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Success") {
    CleanupResultsView(result: CleanupResult(
        filesRemoved: 42,
        spaceFreed: 5_000_000_000,
        errors: [],
        backupLocation: URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup_2024-01-15_12-30-45.tar.gz")
    ))
}

#Preview("With Errors") {
    CleanupResultsView(result: CleanupResult(
        filesRemoved: 38,
        spaceFreed: 4_500_000_000,
        errors: [
            .fileInUse(path: "/Users/test/Library/Caches/com.apple.Safari/Cache.db"),
            .permissionDenied(path: "/System/Library/Caches/protected.cache"),
            .fileNotFound(path: "/tmp/missing.tmp"),
            .fileProtected(path: "/Library/Apple/System.cache")
        ],
        backupLocation: URL(fileURLWithPath: "/Users/test/Library/Application Support/MacStorageCleanup/Backups/backup_2024-01-15_12-30-45.tar.gz")
    ))
}

#Preview("No Backup") {
    CleanupResultsView(result: CleanupResult(
        filesRemoved: 25,
        spaceFreed: 2_000_000_000,
        errors: [],
        backupLocation: nil
    ))
}

#Preview("Failed") {
    CleanupResultsView(result: CleanupResult(
        filesRemoved: 0,
        spaceFreed: 0,
        errors: [
            .cancelled,
            .backupFailed(NSError(domain: "BackupError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insufficient disk space"]))
        ],
        backupLocation: nil
    ))
}
