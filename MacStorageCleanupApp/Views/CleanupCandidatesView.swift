import SwiftUI

/// One traffic-light dot. Size is the only thing that varies between a row and a heading.
struct RiskDot: View {
    let level: CleanupCandidateData.RiskLevel
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: diameter, height: diameter)
            // A ring keeps yellow and green apart for a red-green colour-blind viewer,
            // and keeps any dot visible against both light and dark backgrounds.
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
            .help("\(level.label) — \(level.explanation)")
            .accessibilityLabel(level.label)
    }
}

struct CleanupCandidatesView: View {
    @StateObject private var viewModel: CleanupCandidatesViewModel
    @ObservedObject var storageViewModel: StorageViewModel
    @State private var showingFilters = false
    @State private var showingPreview = false
    @State private var expandedGroups: Set<String> = []
    @State private var hasInitializedGroupExpansion = false
    @State private var showingProjectFoldersPrompt = false
    /// Mirrors the stored folders so the shortcut's label updates as soon as they change.
    @State private var projectFolders: [String] = PreferencesService.shared.projectFolders
    
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

            riskLegendView

            Divider()
            
            // File list
            if viewModel.isLoading {
                loadingView
            } else if viewModel.candidates.isEmpty {
                // Empty state with scan button
                VStack(spacing: 20) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Scan for \(viewModel.selectedCategory.displayName)")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(viewModel.selectedCategory.description)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button(action: { startScan() }) {
                        Label("Scan", systemImage: "magnifyingglass")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            
            // Re-run the scan. Sizes and pins go stale as soon as a build runs or a
            // cleanup completes, and until now the only way to rescan was to leave the
            // page and come back.
            Button(action: { startScan() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Rescan")
                }
            }
            .disabled(viewModel.isLoading)
            .keyboardShortcut("r", modifiers: .command)
            .help("Scan again (⌘R)")

            // Select all checkbox
            Button(action: { viewModel.toggleSelectAll() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.allSelected ? "checkmark.square.fill" : "square")
                    Text(viewModel.allSelected ? "Deselect All" : "Select All")
                }
            }
            .disabled(viewModel.filteredCandidates.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    /// Explains the dots once, at the top, so a row never has to.
    private var riskLegendView: some View {
        HStack(spacing: 16) {
            ForEach(CleanupCandidateData.RiskLevel.allCases, id: \.self) { level in
                HStack(spacing: 5) {
                    RiskDot(level: level)
                    Text(level.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help(level.explanation)
            }

            Spacer()

            Text("Only green and superseded amber items are ticked for you")
                .font(.caption2)
                .foregroundColor(.secondary)

            if viewModel.selectedCategory == .caches {
                Divider().frame(height: 12)
                projectFoldersShortcut
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    /// Opens the project folders picker from the page whose results depend on it.
    ///
    /// The label doubles as status: whether the app is reading real folders or falling
    /// back to guessing is exactly what decides if a pinned version is protected, so it
    /// belongs next to the rows rather than buried in Preferences.
    private var projectFoldersShortcut: some View {
        Button {
            showingProjectFoldersPrompt = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: projectFolders.isEmpty ? "folder.badge.questionmark" : "folder.fill")
                Text(projectFolders.isEmpty
                     ? "Guessing project folders"
                     : "\(projectFolders.count) project folder\(projectFolders.count == 1 ? "" : "s")")
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .foregroundColor(projectFolders.isEmpty ? .orange : .secondary)
        .help(projectFolders.isEmpty
              ? "No folders set — the app guesses where your code lives, so a version pinned by a project it cannot find may be offered for deletion. Click to choose."
              : projectFolders.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "\n"))
    }

    private var fileListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1, pinnedViews: [.sectionHeaders]) {
                ForEach(viewModel.groupedCandidates, id: \.label) { group in
                    if !group.label.isEmpty {
                        Section {
                            if expandedGroups.contains(group.label) {
                                candidateRows(for: group.items)
                            }
                        } header: {
                            groupHeader(label: group.label, items: group.items)
                        }
                    } else {
                        candidateRows(for: group.items)
                    }
                }
            }
        }
        .onAppear { initializeGroupExpansionIfNeeded() }
        .onChange(of: viewModel.groupedCandidates.map(\.label)) { _ in
            initializeGroupExpansionIfNeeded()
        }
    }
    
    /// Defaults the first group to expanded and all others to collapsed, but only the
    /// first time groups become available for this scan (so user toggles aren't reset
    /// on every unrelated view update).
    private func initializeGroupExpansionIfNeeded() {
        guard !hasInitializedGroupExpansion else { return }
        let labels = viewModel.groupedCandidates.map(\.label).filter { !$0.isEmpty }
        guard !labels.isEmpty else { return }
        
        if let firstLabel = labels.first {
            expandedGroups = [firstLabel]
        }
        hasInitializedGroupExpansion = true
    }
    
    private func candidateRows(for items: [CleanupCandidateData]) -> some View {
        ForEach(items) { candidate in
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
    
    private func groupHeader(label: String, items: [CleanupCandidateData]) -> some View {
        let totalSize = items.reduce(Int64(0)) { $0 + $1.size }
        let isExpanded = expandedGroups.contains(label)
        let isFullySelected = viewModel.isGroupFullySelected(label)
        let isPartiallySelected = viewModel.isGroupPartiallySelected(label)
        let selectedSize = viewModel.selectedSize(inGroup: label)

        return HStack(spacing: 8) {
            // Select the whole group. Its own button, so ticking a group never
            // collapses it and expanding never changes the selection.
            Button(action: { viewModel.toggleGroupSelection(label) }) {
                Image(systemName: groupCheckboxSymbol(full: isFullySelected, partial: isPartiallySelected))
                    .font(.title3)
                    .foregroundColor(isFullySelected || isPartiallySelected ? .blue : .secondary)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(isFullySelected ? "Deselect everything in \(label)" : "Select everything in \(label)")

            RiskDot(level: viewModel.riskLevel(inGroup: label), diameter: 9)

            Button(action: { toggleGroupExpansion(label) }) {
                HStack {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(label)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("(\(items.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    // Once something in the group is ticked, show what that adds up to —
                    // that is the number the user is deciding about.
                    if selectedSize > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("of")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func groupCheckboxSymbol(full: Bool, partial: Bool) -> String {
        if full { return "checkmark.square.fill" }
        if partial { return "minus.square.fill" }
        return "square"
    }
    
    private func toggleGroupExpansion(_ label: String) {
        if expandedGroups.contains(label) {
            expandedGroups.remove(label)
        } else {
            expandedGroups.insert(label)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            
            Text("No items found")
                .font(.headline)
            
            Text(viewModel.isLoading ? "Loading cleanup candidates…" : "No cleanup candidates matched the current category or filters.")
                .font(.caption)
                .foregroundColor(.secondary)
            
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
            
            Button("Cancel") {
                viewModel.cancelScan()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct RotatingMagnifierView: View {
    @State private var isOrbiting = false
    private let orbitRadius: CGFloat = 20
    private let orbitSize: CGFloat = 24
    
    var body: some View {
        ZStack {
            Color.clear
                .frame(width: orbitRadius * 2 + orbitSize, height: orbitRadius * 2 + orbitSize)
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: orbitSize))
                .foregroundColor(.blue)
                // Counter-rotate so the glyph itself never spins, only its position orbits
                .rotationEffect(.degrees(isOrbiting ? -360 : 0))
                .offset(y: -orbitRadius)
        }
        .rotationEffect(.degrees(isOrbiting ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                isOrbiting = true
            }
        }
    }
}

private extension CleanupCandidatesView {
    /// Ask where the user's code lives before the first developer cache scan, since that
    /// scan's safety decisions depend on the answer. Only ever asked once.
    func startScan() {
        let preferences = PreferencesService.shared
        let shouldAsk = viewModel.selectedCategory == .caches
            && preferences.scanIncludeDeveloperCaches
            && !preferences.hasPromptedForProjectFolders

        if shouldAsk {
            showingProjectFoldersPrompt = true
            return
        }

        Task { await viewModel.loadCandidates() }
    }

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
            .sheet(isPresented: $showingProjectFoldersPrompt) {
            ProjectFoldersPrompt(initialFolders: projectFolders) { chosen in
                let preferences = PreferencesService.shared
                // Recorded even when declined: that is an answer, and re-asking on every
                // scan would be worse than guessing.
                preferences.hasPromptedForProjectFolders = true

                if let chosen {
                    preferences.projectFolders = chosen
                    projectFolders = chosen
                }

                // Pins decide which rows are pre-ticked, so a change has to re-scan —
                // except on a first run that was declined, where there is nothing yet.
                if chosen != nil || viewModel.candidates.isEmpty {
                    Task { await viewModel.loadCandidates() }
                }
            }
        }
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

            RiskDot(level: candidate.riskLevel)

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

                // Why this row is or is not checked — a superseded version, a pinned
                // one, or a path we could not read without Full Disk Access.
                if let note = candidate.safetyNote {
                    HStack(spacing: 4) {
                        Image(systemName: safetyNoteIcon)
                        Text(note)
                    }
                    .font(.caption2)
                    .foregroundColor(safetyNoteColor)
                    .lineLimit(1)
                }
            }

            Spacer()

            // Metadata
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    if candidate.isPartialSize {
                        Text("≥")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .help("Measurement hit its time budget — the real size is larger")
                    }
                    Text(candidate.needsFullDiskAccess ? "—" : candidate.formattedSize)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

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
    
    private var safetyNoteIcon: String {
        if candidate.needsFullDiskAccess { return "lock.fill" }
        if !candidate.referencedBy.isEmpty { return "pin.fill" }
        if candidate.requiresAdmin { return "key.fill" }
        return candidate.isSelected ? "checkmark.seal" : "info.circle"
    }

    private var safetyNoteColor: Color {
        if candidate.needsFullDiskAccess { return .orange }
        if !candidate.referencedBy.isEmpty { return .orange }
        return .secondary
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
