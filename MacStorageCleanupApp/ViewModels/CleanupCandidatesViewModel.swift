import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class CleanupCandidatesViewModel: ObservableObject {
    @Published var candidates: [CleanupCandidateData] = []
    @Published var filteredCandidates: [CleanupCandidateData] = []
    @Published var selectedCategory: CleanupCandidateData.CleanupCategoryType
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0.0
    @Published var loadingMessage: String = ""
    
    // Filtering options
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var selectedFileTypes: Set<CleanupCandidateData.FileType> = [] {
        didSet { applyFilters() }
    }
    @Published var minSize: Int64 = 0 {
        didSet { applyFilters() }
    }
    @Published var maxAge: Int? = nil {
        didSet { applyFilters() }
    }
    
    // Sorting options
    @Published var sortBy: SortOption = .name {
        didSet { applySorting() }
    }
    @Published var sortAscending: Bool = true {
        didSet { applySorting() }
    }
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case modifiedDate = "Modified Date"
        case accessedDate = "Last Accessed"
        case type = "Type"
        
        var displayName: String { rawValue }
    }
    
    // Selection state
    var selectedCount: Int {
        filteredCandidates.filter { $0.isSelected }.count
    }
    
    var selectedSize: Int64 {
        filteredCandidates.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }
    
    var allSelected: Bool {
        !filteredCandidates.isEmpty && filteredCandidates.allSatisfy { $0.isSelected }
    }
    
    var selectedFiles: [CleanupCandidateData] {
        candidates.filter { $0.isSelected }
    }
    
    init(category: CleanupCandidateData.CleanupCategoryType) {
        self.selectedCategory = category
    }
    
    private var loadTask: Task<Void, Never>?
    private let loggingService = LoggingService.shared
    
    // MARK: - Data Loading
    
    func loadCandidates() async {
        // Cancel any existing task
        loadTask?.cancel()
        
        loadTask = Task {
            isLoading = true
            loggingService.debug("Starting candidate load for category \(selectedCategory.rawValue)")
            await loadRealCandidates()
            
            if !Task.isCancelled {
                isLoading = false
                loggingService.debug("Finished candidate load with \(candidates.count) candidates")
            }
        }
        
        await loadTask?.value
    }
    
    func cancelScan() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
        loadingProgress = 0.0
        loadingMessage = ""
    }
    
    func removeCleanedFiles(_ cleanedPaths: [String]) {
        loggingService.debug("Removing \(cleanedPaths.count) cleaned candidates from list")
        candidates.removeAll { candidate in
            cleanedPaths.contains(candidate.path)
        }
        applyFilters()
    }
    
    private func loadRealCandidates() async {
        let coordinator = ApplicationCoordinator.shared
        var loadedCandidates: [CleanupCandidateData] = []
        
        switch selectedCategory {
        case .caches:
            // Update progress as we scan
            loadingMessage = "Scanning system caches..."
            loadingProgress = 0.1
            let systemResults = await coordinator.cacheManager.findSystemCaches()
            
            guard !Task.isCancelled else { return }
            
            loadingMessage = "Scanning application caches..."
            loadingProgress = 0.3
            let appResults = await coordinator.cacheManager.findApplicationCaches()
            
            guard !Task.isCancelled else { return }
            
            loadingMessage = "Scanning browser caches..."
            loadingProgress = 0.5
            let browserResults = await coordinator.cacheManager.findBrowserCaches()
            
            guard !Task.isCancelled else { return }
            
            loadingMessage = "Scanning developer caches..."
            loadingProgress = 0.7
            let devResults = await coordinator.cacheManager.findDeveloperCaches()
            
            guard !Task.isCancelled else { return }
            
            loadingMessage = "Scanning AI agent caches..."
            loadingProgress = 0.9
            let aiResults = await coordinator.cacheManager.findAIAgentCaches()
            
            guard !Task.isCancelled else { return }

            loggingService.debug(
                "Cache scan results | system=\(systemResults.count) app=\(appResults.count) browser=\(browserResults.count) developer=\(devResults.count) ai=\(aiResults.count)"
            )

            // Paths already claimed by a specific classification (browser/dev tool/AI agent).
            // Generic system/app cache entries that are an ancestor of (or identical to) one of
            // these paths are suppressed below, since their content is already represented by
            // the more specific entry — showing both would double-count the same bytes on disk
            // and create duplicate/overlapping groups (e.g. "Google" and "Android Studio").
            let claimedPaths: [String] =
                browserResults.map { $0.cacheLocation.path } +
                devResults.map { $0.cacheLocation.path } +
                aiResults.map { $0.cacheLocation.path }

            func isSuperseded(_ path: String) -> Bool {
                claimedPaths.contains { claimed in
                    claimed == path || claimed.hasPrefix(path + "/")
                }
            }
            
            // Convert to CleanupCandidateData
            for cache in systemResults where !isSuperseded(cache.url.path) {
                loadedCandidates.append(CleanupCandidateData(
                    path: cache.url.path,
                    name: cache.url.lastPathComponent,
                    size: cache.size,
                    modifiedDate: cache.modifiedDate,
                    accessedDate: cache.accessedDate,
                    fileType: .cache,
                    category: .caches,
                    groupLabel: groupLabel(forUnclassifiedCache: cache)
                ))
            }
            
            for cache in appResults where !isSuperseded(cache.url.path) {
                loadedCandidates.append(CleanupCandidateData(
                    path: cache.url.path,
                    name: cache.url.lastPathComponent,
                    size: cache.size,
                    modifiedDate: cache.modifiedDate,
                    accessedDate: cache.accessedDate,
                    fileType: .cache,
                    category: .caches,
                    groupLabel: groupLabel(forUnclassifiedCache: cache)
                ))
            }
            
            for browserCache in browserResults {
                loadedCandidates.append(CleanupCandidateData(
                    path: browserCache.cacheLocation.path,
                    name: "\(browserCache.browser.rawValue.capitalized) Cache",
                    size: browserCache.size,
                    modifiedDate: Date(),
                    accessedDate: Date(),
                    fileType: .cache,
                    category: .caches,
                    groupLabel: browserCache.browser.rawValue.capitalized
                ))
            }
            
            for devCache in devResults {
                loadedCandidates.append(CleanupCandidateData(
                    path: devCache.cacheLocation.path,
                    name: devCache.description,
                    size: devCache.size,
                    modifiedDate: Date(),
                    accessedDate: Date(),
                    fileType: .cache,
                    category: .caches,
                    groupLabel: groupLabel(forDeveloperTool: devCache.tool)
                ))
            }
            
            for aiCache in aiResults {
                loadedCandidates.append(CleanupCandidateData(
                    path: aiCache.cacheLocation.path,
                    name: aiCache.description,
                    size: aiCache.size,
                    modifiedDate: Date(),
                    accessedDate: Date(),
                    fileType: .cache,
                    category: .caches,
                    groupLabel: groupLabel(forAIAgent: aiCache.agent)
                ))
            }
            
        case .temporaryFiles:
            loadingMessage = "Scanning temporary files..."
            loadingProgress = 0.3
            let files = await scanAndAnalyze(coordinator: coordinator, paths: temporaryFileScanPaths(), category: .temporaryFiles)

            guard !Task.isCancelled else { return }

            loadedCandidates = files.map { file in
                CleanupCandidateData(
                    path: file.url.path,
                    name: file.url.lastPathComponent,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    accessedDate: file.accessedDate,
                    fileType: .temporary,
                    category: .temporaryFiles
                )
            }

        case .largeFiles:
            loadingMessage = "Scanning for large files..."
            loadingProgress = 0.3
            let files = await scanAndAnalyze(coordinator: coordinator, paths: userContentScanPaths(), category: .largeFiles)

            guard !Task.isCancelled else { return }

            loadedCandidates = files.map { file in
                CleanupCandidateData(
                    path: file.url.path,
                    name: file.url.lastPathComponent,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    accessedDate: file.accessedDate,
                    fileType: .largeFile,
                    category: .largeFiles
                )
            }

        case .oldFiles:
            loadingMessage = "Scanning for old files..."
            loadingProgress = 0.3
            let files = await scanAndAnalyze(coordinator: coordinator, paths: userContentScanPaths(), category: .oldFiles)

            guard !Task.isCancelled else { return }

            loadedCandidates = files.map { file in
                CleanupCandidateData(
                    path: file.url.path,
                    name: file.url.lastPathComponent,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    accessedDate: file.accessedDate,
                    fileType: .oldFile,
                    category: .oldFiles
                )
            }

        case .logs:
            loadingMessage = "Scanning log files..."
            loadingProgress = 0.3
            let files = await scanAndAnalyze(coordinator: coordinator, paths: logScanPaths(), category: .logFiles)

            guard !Task.isCancelled else { return }

            loadedCandidates = files.map { file in
                CleanupCandidateData(
                    path: file.url.path,
                    name: file.url.lastPathComponent,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    accessedDate: file.accessedDate,
                    fileType: .log,
                    category: .logs
                )
            }

        case .downloads:
            loadingMessage = "Scanning Downloads..."
            loadingProgress = 0.3
            let files = await scanAndAnalyze(coordinator: coordinator, paths: downloadsScanPaths(), category: .downloads)

            guard !Task.isCancelled else { return }

            loadedCandidates = files.map { file in
                CleanupCandidateData(
                    path: file.url.path,
                    name: file.url.lastPathComponent,
                    size: file.size,
                    modifiedDate: file.modifiedDate,
                    accessedDate: file.accessedDate,
                    fileType: .download,
                    category: .downloads
                )
            }

        case .duplicates:
            loadingMessage = "Scanning for duplicate files..."
            loadingProgress = 0.3
            let duplicateGroups = await scanForDuplicates(coordinator: coordinator, paths: userContentScanPaths())

            guard !Task.isCancelled else { return }

            loadedCandidates = duplicateGroups.flatMap { group -> [CleanupCandidateData] in
                // Preserve the first file in each group; surface the rest as candidates
                guard group.files.count > 1 else { return [] }
                return group.files.dropFirst().map { file in
                    CleanupCandidateData(
                        path: file.url.path,
                        name: file.url.lastPathComponent,
                        size: file.size,
                        modifiedDate: file.modifiedDate,
                        accessedDate: file.accessedDate,
                        fileType: .duplicate,
                        category: .duplicates
                    )
                }
            }
        }
        
        guard !Task.isCancelled else { return }
        
        candidates = loadedCandidates
        applyFilters()
    }

    // MARK: - Real Scanning Helpers

    /// Vendor affiliation for developer tools that are published by a company already
    /// represented as its own cache group (e.g. Android Studio is a Google product, so its
    /// cache is grouped under "Google" instead of standing alone and overlapping with it).
    private static let developerToolVendorAffiliation: [DeveloperTool: String] = [
        .androidStudio: "Google",
        .intellijIdea: "JetBrains",
        .jetbrainsToolbox: "JetBrains"
    ]

    /// Vendor affiliation for AI agents published by a company with its own generic cache group.
    private static let aiAgentVendorAffiliation: [AIAgent: String] = [:]

    private func groupLabel(forDeveloperTool tool: DeveloperTool) -> String {
        Self.developerToolVendorAffiliation[tool] ?? tool.displayName
    }

    private func groupLabel(forAIAgent agent: AIAgent) -> String {
        Self.aiAgentVendorAffiliation[agent] ?? agent.displayName
    }

    /// Recognized vendor/publisher folder names found directly under ~/Library/Caches
    /// that are not already covered by DeveloperTool/AIAgent/Browser classification.
    /// Matched case-insensitively against path components and bundle-id-style prefixes.
    private static let knownVendorPatterns: [(match: String, label: String)] = [
        ("google", "Google"),
        ("com.google", "Google"),
        ("com.apple", "Apple"),
        ("microsoft", "Microsoft"),
        ("com.microsoft", "Microsoft"),
        ("adobe", "Adobe"),
        ("com.adobe", "Adobe"),
        ("mozilla", "Mozilla"),
        ("org.mozilla", "Mozilla"),
        ("dropbox", "Dropbox"),
        ("com.dropbox", "Dropbox"),
        ("slack", "Slack"),
        ("com.tinyspeck", "Slack"),
        ("zoom", "Zoom"),
        ("us.zoom", "Zoom"),
        ("spotify", "Spotify"),
        ("com.spotify", "Spotify")
    ]

    /// Threshold under which unrecognized cache folders are bucketed into "Other Caches"
    /// rather than shown as individually named groups.
    private static let otherCachesGroupingThresholdBytes: Int64 = 100 * 1024 * 1024 // 100 MB

    /// Determine a display group label for a cache folder that wasn't already tagged
    /// by DeveloperTool/AIAgent/Browser classification (i.e. results from findSystemCaches/findApplicationCaches).
    private func groupLabel(forUnclassifiedCache cache: FileMetadata) -> String {
        let folderName = cache.url.lastPathComponent
        let lowerName = folderName.lowercased()

        for (match, label) in Self.knownVendorPatterns {
            if lowerName.contains(match) {
                return label
            }
        }

        if cache.size < Self.otherCachesGroupingThresholdBytes {
            return "Other Caches"
        }

        // Unrecognized but large enough to warrant its own visible entry rather than
        // being folded into the catch-all group.
        return folderName
    }

    /// Cache candidates grouped by their display label (developer tool, AI agent, browser,
    /// recognized vendor, or "Other Caches"). Only meaningful for the `.caches` category;
    /// other categories are returned as a single unlabeled group.
    var groupedCandidates: [(label: String, items: [CleanupCandidateData])] {
        guard selectedCategory == .caches else {
            return [(label: "", items: filteredCandidates)]
        }

        let grouped = Dictionary(grouping: filteredCandidates) { $0.groupLabel ?? $0.name }
        return grouped
            .map { (label: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                // "Other Caches" always sorts last
                if lhs.label == "Other Caches" { return false }
                if rhs.label == "Other Caches" { return true }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
    }

    /// Scan the given paths for the given category and return matching files via the shared analyzer.
    private func scanAndAnalyze(coordinator: ApplicationCoordinator, paths: [URL], category: CleanupCategory) async -> [FileMetadata] {
        do {
            let scanResult = try await coordinator.performScan(
                paths: paths,
                categories: [category],
                progressHandler: { _ in }
            )

            guard !Task.isCancelled else { return [] }

            let analysis = coordinator.storageAnalyzer.analyze(scanResult: scanResult)
            return analysis.categorizedFiles[category] ?? []
        } catch {
            loggingService.error("Scan failed for category \(category.rawValue)", error: error)
            return []
        }
    }

    /// Scan the given paths across all categories and return detected duplicate groups.
    private func scanForDuplicates(coordinator: ApplicationCoordinator, paths: [URL]) async -> [DuplicateGroup] {
        do {
            let scanResult = try await coordinator.performScan(
                paths: paths,
                categories: Set(CleanupCategory.allCases),
                progressHandler: { _ in }
            )

            guard !Task.isCancelled else { return [] }

            let analysis = coordinator.storageAnalyzer.analyze(scanResult: scanResult)
            return analysis.duplicateGroups
        } catch {
            loggingService.error("Duplicate scan failed", error: error)
            return []
        }
    }

    private func temporaryFileScanPaths() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/var/tmp"),
            homeDirectory.appendingPathComponent("Library/Caches")
        ]
    }

    private func logScanPaths() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDirectory.appendingPathComponent("Library/Logs"),
            URL(fileURLWithPath: "/var/log")
        ]
    }

    private func downloadsScanPaths() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return [homeDirectory.appendingPathComponent("Downloads")]
    }

    /// Common user content directories scanned for large/old files and duplicates.
    private func userContentScanPaths() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDirectory.appendingPathComponent("Documents"),
            homeDirectory.appendingPathComponent("Desktop"),
            homeDirectory.appendingPathComponent("Downloads"),
            homeDirectory.appendingPathComponent("Movies"),
            homeDirectory.appendingPathComponent("Pictures")
        ]
    }
    
    // MARK: - Filtering
    
    func applyFilters() {
        var filtered = candidates
        
        // Search text filter
        if !searchText.isEmpty {
            filtered = filtered.filter { candidate in
                candidate.name.localizedCaseInsensitiveContains(searchText) ||
                candidate.path.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // File type filter
        if !selectedFileTypes.isEmpty {
            filtered = filtered.filter { selectedFileTypes.contains($0.fileType) }
        }
        
        // Size filter
        if minSize > 0 {
            filtered = filtered.filter { $0.size >= minSize }
        }
        
        // Age filter
        if let maxAge = maxAge {
            let cutoffDate = Date().addingTimeInterval(-Double(maxAge * 86400))
            filtered = filtered.filter { $0.accessedDate <= cutoffDate }
        }
        
        filteredCandidates = filtered
        applySorting()
    }
    
    func clearFilters() {
        searchText = ""
        selectedFileTypes.removeAll()
        minSize = 0
        maxAge = nil
    }
    
    // MARK: - Sorting
    
    func applySorting() {
        filteredCandidates.sort { lhs, rhs in
            let result: Bool
            switch sortBy {
            case .name:
                result = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                result = lhs.size < rhs.size
            case .modifiedDate:
                result = lhs.modifiedDate < rhs.modifiedDate
            case .accessedDate:
                result = lhs.accessedDate < rhs.accessedDate
            case .type:
                result = lhs.fileType.displayName < rhs.fileType.displayName
            }
            return sortAscending ? result : !result
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(for candidate: CleanupCandidateData) {
        if let index = filteredCandidates.firstIndex(where: { $0.id == candidate.id }) {
            filteredCandidates[index].isSelected.toggle()
        }
        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index].isSelected.toggle()
        }
    }
    
    func selectAll() {
        for index in filteredCandidates.indices {
            filteredCandidates[index].isSelected = true
        }
        for index in candidates.indices {
            if filteredCandidates.contains(where: { $0.id == candidates[index].id }) {
                candidates[index].isSelected = true
            }
        }
    }
    
    func deselectAll() {
        for index in filteredCandidates.indices {
            filteredCandidates[index].isSelected = false
        }
        for index in candidates.indices {
            candidates[index].isSelected = false
        }
    }
    
    func toggleSelectAll() {
        if allSelected {
            deselectAll()
        } else {
            selectAll()
        }
    }
}
