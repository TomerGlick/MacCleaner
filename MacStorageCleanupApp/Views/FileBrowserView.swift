import SwiftUI

struct FileBrowserView: View {
    @StateObject private var viewModel: FileBrowserViewModel
    @State private var showingDeleteConfirmation = false
    
    init(startPath: URL? = nil) {
        _viewModel = StateObject(wrappedValue: FileBrowserViewModel(startPath: startPath))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            navigationBar
            
            Divider()
            
            // Toolbar
            toolbar
            
            Divider()
            
            // File list
            if viewModel.isLoading {
                loadingView
            } else if viewModel.items.isEmpty {
                // Empty state with scan button
                VStack(spacing: 20) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("File Browser")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Browse and manage files on your Mac")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            await viewModel.loadItems()
                        }
                    }) {
                        Label("Browse Files", systemImage: "folder")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredItems.isEmpty {
                emptyView
            } else {
                fileListView
            }
            
            Divider()
            
            // Footer with selection info
            footer
        }
    }
    
    // MARK: - Navigation Bar
    
    private var navigationBar: some View {
        HStack(spacing: 8) {
            // Back button
            Button(action: { viewModel.navigateBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.navigationStack.count <= 1)
            
            // Up button
            Button(action: { viewModel.navigateToParent() }) {
                Image(systemName: "chevron.up")
            }
            
            // Home button
            Button(action: { viewModel.navigateToHome() }) {
                Image(systemName: "house")
            }
            
            Divider()
                .frame(height: 20)
            
            // Current path
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(viewModel.currentPath.pathComponents.indices, id: \.self) { index in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(viewModel.currentPath.pathComponents[index])
                            .font(.body)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Reveal in Finder
            Button(action: {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: viewModel.currentPath.path)
            }) {
                Image(systemName: "arrow.up.forward.app")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Toolbar
    
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 300)
            
            Spacer()
            
            // Show hidden files toggle
            Toggle("Hidden", isOn: $viewModel.showHiddenFiles)
                .toggleStyle(.checkbox)
            
            // Size filter
            Menu {
                Button("Any size") { viewModel.minSize = 0 }
                Button("1 MB+") { viewModel.minSize = 1_000_000 }
                Button("10 MB+") { viewModel.minSize = 10_000_000 }
                Button("100 MB+") { viewModel.minSize = 100_000_000 }
                Button("1 GB+") { viewModel.minSize = 1_000_000_000 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Size")
                }
            }
            
            // Sort menu
            Menu {
                Picker("Sort By", selection: $viewModel.sortBy) {
                    ForEach(FileBrowserViewModel.SortOption.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                
                Divider()
                
                Toggle("Ascending", isOn: $viewModel.sortAscending)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort")
                }
            }
            
            // Select all
            Button(action: {
                if viewModel.selectedCount > 0 {
                    viewModel.deselectAll()
                } else {
                    viewModel.selectAll()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.selectedCount > 0 ? "checkmark.square.fill" : "square")
                    Text(viewModel.selectedCount > 0 ? "Deselect All" : "Select All")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - File List
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredItems) { item in
                    FileBrowserRowView(
                        item: item,
                        onToggle: { viewModel.toggleSelection(for: item) },
                        onNavigate: { viewModel.navigateInto(item) },
                        onReveal: { viewModel.revealInFinder(item) }
                    )
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading...")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Button("Cancel") {
                viewModel.cancelLoad()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No items found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if !viewModel.searchText.isEmpty || viewModel.minSize > 0 {
                Button("Clear Filters") {
                    viewModel.searchText = ""
                    viewModel.minSize = 0
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if viewModel.selectedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                    
                    Text("\(viewModel.selectedCount) items selected")
                        .font(.subheadline)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.formattedSelectedSize)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            } else {
                Text("\(viewModel.filteredItems.count) items")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                showingDeleteConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Selected")
                }
            }
            .disabled(viewModel.selectedCount == 0)
            .alert("Delete \(viewModel.selectedCount) items?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        try? await viewModel.deleteSelectedItems()
                    }
                }
            } message: {
                Text("This will permanently delete \(viewModel.selectedCount) items (\(viewModel.formattedSelectedSize)). This action cannot be undone.")
            }
        }
        .padding()
    }
}

// MARK: - File Browser Row View

struct FileBrowserRowView: View {
    let item: FileItem
    let onToggle: () -> Void
    let onNavigate: () -> Void
    let onReveal: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(item.isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 20)
            
            // Icon
            Image(systemName: item.icon)
                .font(.title3)
                .foregroundColor(item.isDirectory ? .blue : .secondary)
                .frame(width: 24)
            
            // Name
            Button(action: {
                if item.isDirectory {
                    onNavigate()
                }
            }) {
                Text(item.name)
                    .font(.body)
                    .foregroundColor(item.isDirectory ? .blue : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            // Type
            Text(item.fileType.displayName)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            // Size
            Text(item.formattedSize)
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
            
            // Modified date
            Text(item.formattedModifiedDate)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .trailing)
            
            // Actions
            Menu {
                if item.isDirectory {
                    Button(action: onNavigate) {
                        Label("Open", systemImage: "arrow.right")
                    }
                }
                
                Button(action: onReveal) {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.app")
                }
                
                Divider()
                
                Button(role: .destructive, action: {
                    onToggle()
                }) {
                    Label(item.isSelected ? "Deselect" : "Select for Deletion", systemImage: item.isSelected ? "xmark" : "checkmark")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(item.isSelected ? Color.blue.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    FileBrowserView()
        .frame(width: 900, height: 600)
}
