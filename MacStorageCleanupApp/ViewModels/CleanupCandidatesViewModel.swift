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
    @Published var sortBy: SortOption = .size {
        didSet { applySorting() }
    }
    @Published var sortAscending: Bool = false {
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
    
    // MARK: - Data Loading
    
    func loadCandidates() async {
        isLoading = true
        print("DEBUG: Starting to load candidates for category: \(selectedCategory)")
        await loadRealCandidates()
        isLoading = false
        print("DEBUG: Finished loading. Total candidates: \(candidates.count)")
    }
    
    func removeCleanedFiles(_ cleanedPaths: [String]) {
        print("DEBUG: Removing \(cleanedPaths.count) cleaned files from list")
        candidates.removeAll { candidate in
            cleanedPaths.contains(candidate.path)
        }
        applyFilters()
    }
    
    private func loadRealCandidates() async {
        print("DEBUG: loadRealCandidates called")
        let coordinator = ApplicationCoordinator.shared
        print("DEBUG: Got coordinator")
        var loadedCandidates: [CleanupCandidateData] = []
        
        switch selectedCategory {
        case .caches:
            print("DEBUG: Loading caches...")
            
            // Update progress as we scan
            loadingMessage = "Scanning system caches..."
            loadingProgress = 0.1
            let systemResults = await coordinator.cacheManager.findSystemCaches()
            
            loadingMessage = "Scanning application caches..."
            loadingProgress = 0.3
            let appResults = await coordinator.cacheManager.findApplicationCaches()
            
            loadingMessage = "Scanning browser caches..."
            loadingProgress = 0.5
            let browserResults = await coordinator.cacheManager.findBrowserCaches()
            
            loadingMessage = "Scanning developer caches..."
            loadingProgress = 0.7
            let devResults = await coordinator.cacheManager.findDeveloperCaches()
            
            loadingMessage = "Scanning AI agent caches..."
            loadingProgress = 0.9
            let aiResults = await coordinator.cacheManager.findAIAgentCaches()
            
            print("DEBUG: System caches found: \(systemResults.count)")
            print("DEBUG: App caches found: \(appResults.count)")
            print("DEBUG: Browser caches found: \(browserResults.count)")
            print("DEBUG: Developer caches found: \(devResults.count)")
            print("DEBUG: AI agent caches found: \(aiResults.count)")
            
            // Convert to CleanupCandidateData
            for cache in systemResults {
                loadedCandidates.append(CleanupCandidateData(
                    path: cache.url.path,
                    name: cache.url.lastPathComponent,
                    size: cache.size,
                    modifiedDate: cache.modifiedDate,
                    accessedDate: cache.accessedDate,
                    fileType: .cache,
                    category: .caches
                ))
            }
            
            for cache in appResults {
                loadedCandidates.append(CleanupCandidateData(
                    path: cache.url.path,
                    name: cache.url.lastPathComponent,
                    size: cache.size,
                    modifiedDate: cache.modifiedDate,
                    accessedDate: cache.accessedDate,
                    fileType: .cache,
                    category: .caches
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
                    category: .caches
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
                    category: .caches
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
                    category: .caches
                ))
            }
            
        case .temporaryFiles, .largeFiles, .oldFiles, .logs, .downloads, .duplicates:
            // For other categories, use sample data for now
            loadedCandidates = generateSampleCandidates(for: selectedCategory)
        }
        
        candidates = loadedCandidates
        applyFilters()
    }
    
    private func generateSampleCandidates(for category: CleanupCandidateData.CleanupCategoryType) -> [CleanupCandidateData] {
        // Sample data for demonstration
        var samples: [CleanupCandidateData] = []
        
        switch category {
        case .caches:
            samples = [
                CleanupCandidateData(
                    path: "~/Library/Caches/com.apple.Safari",
                    name: "Safari Cache",
                    size: 5_000_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 7),
                    accessedDate: Date().addingTimeInterval(-86400 * 2),
                    fileType: .cache,
                    category: .caches
                ),
                CleanupCandidateData(
                    path: "~/Library/Caches/com.google.Chrome",
                    name: "Chrome Cache",
                    size: 3_500_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 3),
                    accessedDate: Date().addingTimeInterval(-86400),
                    fileType: .cache,
                    category: .caches
                )
            ]
        case .temporaryFiles:
            samples = [
                CleanupCandidateData(
                    path: "/tmp/temp_file_1.tmp",
                    name: "temp_file_1.tmp",
                    size: 150_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 10),
                    accessedDate: Date().addingTimeInterval(-86400 * 10),
                    fileType: .temporary,
                    category: .temporaryFiles
                )
            ]
        case .largeFiles:
            samples = [
                CleanupCandidateData(
                    path: "~/Documents/large_video.mov",
                    name: "large_video.mov",
                    size: 15_000_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 30),
                    accessedDate: Date().addingTimeInterval(-86400 * 30),
                    fileType: .largeFile,
                    category: .largeFiles
                )
            ]
        case .oldFiles:
            samples = [
                CleanupCandidateData(
                    path: "~/Documents/old_project.zip",
                    name: "old_project.zip",
                    size: 500_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 400),
                    accessedDate: Date().addingTimeInterval(-86400 * 400),
                    fileType: .archive,
                    category: .oldFiles
                )
            ]
        case .logs:
            samples = [
                CleanupCandidateData(
                    path: "~/Library/Logs/app.log",
                    name: "app.log",
                    size: 250_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 15),
                    accessedDate: Date().addingTimeInterval(-86400 * 15),
                    fileType: .log,
                    category: .logs
                )
            ]
        case .downloads:
            samples = [
                CleanupCandidateData(
                    path: "~/Downloads/installer.dmg",
                    name: "installer.dmg",
                    size: 2_000_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 100),
                    accessedDate: Date().addingTimeInterval(-86400 * 100),
                    fileType: .installer,
                    category: .downloads
                )
            ]
        case .duplicates:
            samples = [
                CleanupCandidateData(
                    path: "~/Documents/photo_copy.jpg",
                    name: "photo_copy.jpg",
                    size: 5_000_000,
                    modifiedDate: Date().addingTimeInterval(-86400 * 50),
                    accessedDate: Date().addingTimeInterval(-86400 * 50),
                    fileType: .duplicate,
                    category: .duplicates
                )
            ]
        }
        
        return samples
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
