import SwiftUI

struct CleanupCandidatesView: View {
    @StateObject private var viewModel: CleanupCandidatesViewModel
    @ObservedObject var storageViewModel: StorageViewModel
    @State private var showingFilters = false
    @State private var showingPreview = false
    
    init(category: CleanupCandidateData.CleanupCategoryType, storageViewModel: StorageViewModel) {
        _viewModel = StateObject(wrappedValue: CleanupCandidatesViewModel(category: category))
        self.storageViewModel = storageViewModel
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Toolbar with sorting and filtering
            toolbarView
            
            Divider()
            
            // File list
            if viewModel.isLoading {
                loadingView
            } else if viewModel.filteredCandidates.isEmpty {
                emptyStateView
            } else {
                fileListView
            }
            
            Divider()
            
            // Footer with selection summary
            footerView
            }
        }
        .task {
            print("DEBUG: CleanupCandidatesView task started")
            await viewModel.loadCandidates()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.selectedCategory.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(viewModel.selectedCategory.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(viewModel.filteredCandidates.count) items")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private var toolbarView: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files...", text: $viewModel.searchText)
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
            
            // Sort menu
            Menu {
                Picker("Sort By", selection: $viewModel.sortBy) {
                    ForEach(CleanupCandidatesViewModel.SortOption.allCases, id: \.self) { option in
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
            .frame(width: 80)
            
            // Filter button
            Button(action: { showingFilters.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filter")
                }
            }
            .popover(isPresented: $showingFilters) {
                FilterPopoverView(viewModel: viewModel)
            }
            
            // Select all checkbox
            Button(action: { viewModel.toggleSelectAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.allSelected ? "checkmark.square.fill" : "square")
                    Text(viewModel.allSelected ? "Deselect All" : "Select All")
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredCandidates) { candidate in
                    HStack(spacing: 0) {
                        CleanupCandidateRowView(
                            candidate: candidate,
                            onToggle: { viewModel.toggleSelection(for: candidate) }
                        )
                        
                        // Drill-down button
                        NavigationLink(destination: CandidateDetailView(candidate: candidate, viewModel: viewModel)) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("No items found")
                .font(.headline)
            
            Text("Debug: isLoading=\(viewModel.isLoading), candidates=\(viewModel.candidates.count)")
                .font(.caption)
                .foregroundColor(.red)
            
            if !viewModel.searchText.isEmpty || !viewModel.selectedFileTypes.isEmpty || viewModel.minSize > 0 {
                Button("Clear Filters") {
                    viewModel.clearFilters()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            RotatingMagnifierView()
            
            ProgressView(value: viewModel.loadingProgress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(width: 300)
            
            Text(viewModel.loadingMessage.isEmpty ? "Scanning for caches..." : viewModel.loadingMessage)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("\(Int(viewModel.loadingProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct RotatingMagnifierView: View {
    @State private var isRotating = false
    
    var body: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 24))
            .foregroundColor(.blue)
            .offset(y: -30)
            .rotationEffect(.degrees(isRotating ? 360 : 0), anchor: .center)
            .rotationEffect(.degrees(isRotating ? -360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    isRotating = true
                }
            }
    }
}

private extension CleanupCandidatesView {
    var footerView: some View {
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
                Text("Select items to clean up")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Clean Up Selected") {
                showingPreview = true
            }
            .disabled(viewModel.selectedCount == 0)
            .sheet(isPresented: $showingPreview) {
                CleanupPreviewView(selectedFiles: viewModel.selectedFiles) { cleanedPaths in
                    // Remove cleaned files from list instantly
                    viewModel.removeCleanedFiles(cleanedPaths)
                    // Refresh disk space
                    Task {
                        await storageViewModel.refreshDiskSpace()
                    }
                }
            }
        }
        .padding()
    }
}

struct CleanupCandidateRowView: View {
    let candidate: CleanupCandidateData
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox - separate button
            Button(action: onToggle) {
                Image(systemName: candidate.isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(candidate.isSelected ? .blue : .secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            
            // File icon
            Image(systemName: candidate.fileType.iconName)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(candidate.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Metadata
            VStack(alignment: .trailing, spacing: 2) {
                Text(candidate.formattedSize)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    
                    Text(candidate.relativeAccessedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 120, alignment: .trailing)
                
                // Type badge
                Text(candidate.fileType.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
                    .frame(minWidth: 80)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(candidate.isSelected ? Color.blue.opacity(0.05) : Color.clear)
            .background(Color(NSColor.controlBackgroundColor))
            .help("\(candidate.name)\n\nPath: \(candidate.path)\nSize: \(candidate.formattedSize)")
            .contextMenu {
                Button(action: { showInFinder(path: candidate.path) }) {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
    }
    
    private func showInFinder(path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}

struct FilterPopoverView: View {
    @ObservedObject var viewModel: CleanupCandidatesViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Filters")
                .font(.headline)
            
            Divider()
            
            // File type filter
            VStack(alignment: .leading, spacing: 8) {
                Text("File Types")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                let fileTypes = Array(Set(viewModel.candidates.map { $0.fileType })).sorted { $0.displayName < $1.displayName }
                
                ForEach(fileTypes, id: \.self) { fileType in
                    Toggle(fileType.displayName, isOn: Binding(
                        get: { viewModel.selectedFileTypes.contains(fileType) },
                        set: { isOn in
                            if isOn {
                                viewModel.selectedFileTypes.insert(fileType)
                            } else {
                                viewModel.selectedFileTypes.remove(fileType)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
            
            Divider()
            
            // Size filter
            VStack(alignment: .leading, spacing: 8) {
                Text("Minimum Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: $viewModel.minSize) {
                    Text("Any").tag(Int64(0))
                    Text("1 MB").tag(Int64(1_000_000))
                    Text("10 MB").tag(Int64(10_000_000))
                    Text("100 MB").tag(Int64(100_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                }
                .labelsHidden()
            }
            
            Divider()
            
            // Age filter (for old files)
            if viewModel.selectedCategory == .oldFiles {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Maximum Age")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("", selection: Binding(
                        get: { viewModel.maxAge ?? 0 },
                        set: { viewModel.maxAge = $0 > 0 ? $0 : nil }
                    )) {
                        Text("Any").tag(0)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("180 days").tag(180)
                        Text("1 year").tag(365)
                        Text("2 years").tag(730)
                    }
                    .labelsHidden()
                }
                
                Divider()
            }
            
            // Clear filters button
            Button("Clear All Filters") {
                viewModel.clearFilters()
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(width: 250)
    }
}

#Preview {
    CleanupCandidatesView(category: .caches, storageViewModel: StorageViewModel())
        .frame(width: 800, height: 600)
}
