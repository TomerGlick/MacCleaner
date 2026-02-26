import SwiftUI

/// View that displays real-time cleanup progress with cancellation support
/// Validates Requirement 9.5
struct CleanupProgressView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CleanupProgressViewModel
    @State private var showingCancelConfirmation = false
    
    init(filesToClean: [CleanupCandidateData], options: CleanupOptions) {
        _viewModel = StateObject(wrappedValue: CleanupProgressViewModel(
            filesToClean: filesToClean,
            options: options
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Progress content
            progressContentView
            
            Divider()
            
            // Footer with cancel button
            footerView
        }
        .frame(width: 600, height: 400)
        .onAppear {
            viewModel.startCleanup()
        }
        .alert("Cancel Cleanup?", isPresented: $showingCancelConfirmation) {
            Button("Continue Cleanup", role: .cancel) { }
            Button("Cancel Cleanup", role: .destructive) {
                viewModel.cancelCleanup()
            }
        } message: {
            Text("Are you sure you want to cancel the cleanup operation? Any files already deleted cannot be recovered unless a backup was created.")
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .font(.title)
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
    
    private var progressContentView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Progress bar and percentage
            VStack(spacing: 12) {
                // Percentage
                Text(viewModel.percentageText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                
                // Progress bar
                ProgressView(value: viewModel.progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .frame(width: 400)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
            
            // Current file being processed
            if !viewModel.currentFile.isEmpty {
                VStack(spacing: 8) {
                    Text("Current file:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.currentFile)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: 500)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
            
            // Statistics
            HStack(spacing: 40) {
                StatView(
                    icon: "doc.fill",
                    label: "Files Processed",
                    value: "\(viewModel.filesProcessed) / \(viewModel.totalFiles)"
                )
                
                StatView(
                    icon: "arrow.down.circle.fill",
                    label: "Space Freed",
                    value: viewModel.formattedSpaceFreed,
                    valueColor: .green
                )
            }
            
            // Error count (if any)
            if viewModel.errorCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text("\(viewModel.errorCount) error\(viewModel.errorCount == 1 ? "" : "s") encountered")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var footerView: some View {
        HStack {
            Spacer()
            
            if viewModel.isInProgress {
                Button("Cancel") {
                    showingCancelConfirmation = true
                }
                .buttonStyle(.bordered)
            } else if viewModel.isCompleted {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if viewModel.isCancelled {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

/// Displays a single statistic with icon, label, and value
private struct StatView: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.headline)
                    .foregroundColor(valueColor)
            }
        }
    }
}

#Preview {
    CleanupProgressView(
        filesToClean: [
            CleanupCandidateData(
                path: "~/Library/Caches/com.apple.Safari",
                name: "Safari Cache",
                size: 5_000_000_000,
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                category: .caches
            ),
            CleanupCandidateData(
                path: "~/Library/Caches/com.google.Chrome",
                name: "Chrome Cache",
                size: 3_500_000_000,
                modifiedDate: Date(),
                accessedDate: Date(),
                fileType: .cache,
                category: .caches
            )
        ],
        options: CleanupOptions(
            createBackup: false,
            moveToTrash: true,
            skipInUseFiles: true
        )
    )
}
