import SwiftUI

/// View that displays a preview of files to be cleaned up and requires explicit confirmation
/// Validates Requirements 9.1, 9.2, 9.3, 9.4
struct CleanupPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CleanupPreviewViewModel
    @State private var showingConfirmation = false
    @State private var showingProgressView = false
    var onCleanupComplete: (([String]) -> Void)?
    
    init(selectedFiles: [CleanupCandidateData], onCleanupComplete: (([String]) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: CleanupPreviewViewModel(selectedFiles: selectedFiles))
        self.onCleanupComplete = onCleanupComplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Category groups with deselection
            categoryGroupsView
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(width: 700, height: 600)
        .alert("Confirm Cleanup", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clean Up", role: .destructive) {
                performCleanup()
            }
        } message: {
            Text("Are you sure you want to clean up \(viewModel.selectedCount) items? This will free up \(viewModel.formattedTotalSize). This action cannot be undone.")
        }
        .sheet(isPresented: $showingProgressView) {
            // When progress view dismisses, also dismiss preview and notify parent
            let cleanedPaths = viewModel.selectedFiles.map { $0.path }
            onCleanupComplete?(cleanedPaths)
            dismiss()
        } content: {
            CleanupProgressView(
                filesToClean: viewModel.selectedFiles,
                options: CleanupOptions(
                    createBackup: false,
                    moveToTrash: true,
                    skipInUseFiles: true
                )
            )
        }
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cleanup Preview")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Review the files that will be removed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Summary stats
            HStack(spacing: 24) {
                StatView(
                    icon: "doc.fill",
                    label: "Files",
                    value: "\(viewModel.selectedCount)"
                )
                
                StatView(
                    icon: "folder.fill",
                    label: "Categories",
                    value: "\(viewModel.categoryGroups.count)"
                )
                
                StatView(
                    icon: "arrow.down.circle.fill",
                    label: "Space to Free",
                    value: viewModel.formattedTotalSize,
                    valueColor: .green
                )
            }
        }
        .padding()
    }
    
    private var categoryGroupsView: some View {
        ScrollView {
            LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.categoryGroups) { group in
                    CategoryGroupView(
                        group: group,
                        onToggleCategory: { viewModel.toggleCategory(group.category) },
                        onToggleFile: { file in viewModel.toggleFile(file) }
                    )
                }
            }
            .padding()
        }
    }
    
    private var footerView: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if viewModel.selectedCount == 0 {
                Text("No items selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button("Clean Up \(viewModel.selectedCount) Items") {
                showingConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private func performCleanup() {
        showingProgressView = true
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

/// Displays a group of files organized by category with toggle controls
private struct CategoryGroupView: View {
    let group: CleanupPreviewViewModel.CategoryGroup
    let onToggleCategory: () -> Void
    let onToggleFile: (CleanupCandidateData) -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Button(action: onToggleCategory) {
                        Image(systemName: group.allSelected ? "checkmark.square.fill" : (group.someSelected ? "minus.square.fill" : "square"))
                            .foregroundColor(group.allSelected || group.someSelected ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Text(group.category.displayName)
                        .font(.headline)
                    
                    Text("(\(group.selectedCount)/\(group.files.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(group.formattedSize)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // File list (when expanded)
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.files) { file in
                        FileRowView(file: file, onToggle: { onToggleFile(file) })
                    }
                }
                .padding(.leading, 32)
            }
        }
    }
}

/// Displays a single file row with checkbox and metadata
private struct FileRowView: View {
    let file: CleanupCandidateData
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                Image(systemName: file.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(file.isSelected ? .blue : .secondary)
                    .frame(width: 16)
                
                Image(systemName: file.fileType.iconName)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    Text(file.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(file.isSelected ? Color.blue.opacity(0.05) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CleanupPreviewView(selectedFiles: [
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
        ),
        CleanupCandidateData(
            path: "/tmp/temp_file.tmp",
            name: "temp_file.tmp",
            size: 150_000_000,
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .temporary,
            category: .temporaryFiles
        )
    ])
}
