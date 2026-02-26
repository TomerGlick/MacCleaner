import SwiftUI
import MacStorageCleanupCore

struct CandidateDetailView: View {
    let candidate: CleanupCandidateData
    @ObservedObject var viewModel: CleanupCandidatesViewModel
    @State private var subItems: [SubItem] = []
    @State private var isLoading = true
    
    struct SubItem: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let size: Int64
        var isSelected: Bool
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(candidate.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(formatSize(candidate.size))
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            .padding()
            
            Divider()
            
            // Toolbar
            HStack {
                Button(action: toggleSelectAll) {
                    HStack(spacing: 4) {
                        Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                        Text(allSelected ? "Deselect All" : "Select All")
                    }
                }
                
                Spacer()
                
                Text("\(selectedCount) of \(subItems.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if selectedCount > 0 {
                    Button(action: deleteSelected) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete Selected")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Content
            if isLoading {
                ProgressView("Loading contents...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if subItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No items found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach($subItems) { $item in
                            SubItemRow(item: $item)
                        }
                    }
                }
            }
        }
        .task {
            await loadSubItems()
        }
    }
    
    private var allSelected: Bool {
        !subItems.isEmpty && subItems.allSatisfy { $0.isSelected }
    }
    
    private var selectedCount: Int {
        subItems.filter { $0.isSelected }.count
    }
    
    private func toggleSelectAll() {
        let newValue = !allSelected
        for i in subItems.indices {
            subItems[i].isSelected = newValue
        }
    }
    
    private func deleteSelected() {
        let selectedPaths = subItems.filter { $0.isSelected }.map { $0.path }
        
        guard !selectedPaths.isEmpty else { return }
        
        Task {
            let coordinator = ApplicationCoordinator.shared
            let fileMetadata = selectedPaths.map { path in
                FileMetadata(
                    url: URL(fileURLWithPath: path),
                    size: 0,
                    createdDate: Date(),
                    modifiedDate: Date(),
                    accessedDate: Date(),
                    fileType: .cache,
                    isInUse: false,
                    permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
                )
            }
            
            let options = MacStorageCleanupCore.CleanupOptions(
                createBackup: false,
                moveToTrash: true,
                skipInUseFiles: true
            )
            
            do {
                _ = try await coordinator.cleanupEngine.cleanup(
                    files: fileMetadata,
                    options: options,
                    progressHandler: { _ in }
                )
                
                // Remove deleted items from list
                subItems.removeAll { item in
                    selectedPaths.contains(item.path)
                }
            } catch {
                print("Error deleting files: \(error)")
            }
        }
    }
    
    private func loadSubItems() async {
        isLoading = true
        defer { isLoading = false }
        
        let fileManager = FileManager.default
        let url = URL(fileURLWithPath: candidate.path)
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        var items: [SubItem] = []
        
        for case let fileURL as URL in enumerator {
            enumerator.skipDescendants()
            
            let name = fileURL.lastPathComponent
            let path = fileURL.path
            
            let size = await calculateSize(at: fileURL)
            
            items.append(SubItem(
                name: name,
                path: path,
                size: size,
                isSelected: true
            ))
        }
        
        subItems = items.sorted { $0.size > $1.size }
    }
    
    private func calculateSize(at url: URL) async -> Int64 {
        let fileManager = FileManager.default
        
        guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
              let isDirectory = resourceValues.isDirectory else {
            return 0
        }
        
        if !isDirectory {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                return Int64(size)
            }
            return 0
        }
        
        // Calculate directory size
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
               let isDirectory = resourceValues.isDirectory,
               !isDirectory,
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct SubItemRow: View {
    @Binding var item: CandidateDetailView.SubItem
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: { item.isSelected.toggle() }) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(item.isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            Image(systemName: "folder.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(formatSize(item.size))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .contextMenu {
            Button(action: { showInFinder(path: item.path) }) {
                Label("Show in Finder", systemImage: "folder")
            }
        }
    }
    
    private func showInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
