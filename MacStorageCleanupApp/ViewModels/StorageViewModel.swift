import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class StorageViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var totalCapacity: Int64 = 0
    @Published var usedSpace: Int64 = 0
    @Published var availableSpace: Int64 = 0
    @Published var categoryData: [StorageCategoryData] = []
    @Published var selectedCategory: StorageCategoryData?
    @Published var navigationPath: [StorageCategoryData] = []
    
    // Scan state
    @Published var isScanning = false
    @Published var scanProgress = ScanProgressData()
    @Published var lastScanResult: ScanResultData?
    
    // Scan configuration
    @Published var scanIncludeSystemCaches = true
    @Published var scanIncludeAppCaches = true
    @Published var scanIncludeTempFiles = true
    @Published var scanIncludeLargeFiles = true
    @Published var scanIncludeOldFiles = true
    @Published var scanIncludeLogFiles = true
    @Published var scanIncludeDeveloperCaches = true
    @Published var scanIncludeAIAgentCaches = true
    
    private var fileScanner: FileScanner?
    private let coordinator = ApplicationCoordinator.shared
    
    // Computed properties for display
    var formattedTotalCapacity: String {
        ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file)
    }
    
    var formattedUsedSpace: String {
        ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file)
    }
    
    var formattedAvailableSpace: String {
        ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
    }
    
    var usedPercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedSpace) / Double(totalCapacity) * 100
    }
    
    var availablePercentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(availableSpace) / Double(totalCapacity) * 100
    }
    
    func loadStorageData() async {
        isLoading = true
        await refreshDiskSpace()
        await calculateCategoryBreakdown()
        isLoading = false
    }
    
    func refreshDiskSpace() async {
        // Get disk space information
        if let volumeURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                let values = try volumeURL.resourceValues(forKeys: [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey
                ])
                
                if let capacity = values.volumeTotalCapacity,
                   let available = values.volumeAvailableCapacity {
                    totalCapacity = Int64(capacity)
                    availableSpace = Int64(available)
                    usedSpace = totalCapacity - availableSpace
                }
            } catch {
                print("Error getting volume information: \(error)")
            }
        }
    }
    
    private func calculateCategoryBreakdown() async {
        // Calculate categories in parallel for better performance
        async let applicationsSize = calculateDirectorySize(path: "/Applications")
        async let userApplicationsSize = calculateDirectorySize(path: NSHomeDirectory() + "/Applications")
        async let documentsSize = calculateDirectorySize(path: NSHomeDirectory() + "/Documents")
        async let cachesSize = calculateDirectorySize(path: NSHomeDirectory() + "/Library/Caches")
        async let logsSize = calculateDirectorySize(path: NSHomeDirectory() + "/Library/Logs")
        async let downloadsSize = calculateDirectorySize(path: NSHomeDirectory() + "/Downloads")
        async let desktopSize = calculateDirectorySize(path: NSHomeDirectory() + "/Desktop")
        async let picturesSize = calculateDirectorySize(path: NSHomeDirectory() + "/Pictures")
        async let moviesSize = calculateDirectorySize(path: NSHomeDirectory() + "/Movies")
        async let musicSize = calculateDirectorySize(path: NSHomeDirectory() + "/Music")
        
        // Additional large directories that are often missed
        async let librarySize = calculateDirectorySize(path: NSHomeDirectory() + "/Library")
        async let virtualMachinesSize = calculateDirectorySize(path: NSHomeDirectory() + "/.Trash")
        
        // Wait for all calculations to complete
        let (apps, userApps, docs, caches, logs, downloads, desktop, pictures, movies, music, library, trash) = await (
            applicationsSize, userApplicationsSize, documentsSize, cachesSize, logsSize, 
            downloadsSize, desktopSize, picturesSize, moviesSize, musicSize, librarySize, virtualMachinesSize
        )
        let totalApplicationsSize = apps + userApps
        
        // Library contains caches and logs, so subtract those to avoid double counting
        let otherLibrarySize = max(0, library - caches - logs)
        
        print("DEBUG Storage Breakdown:")
        print("  Total Used: \(ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file))")
        print("  Applications: \(ByteCountFormatter.string(fromByteCount: totalApplicationsSize, countStyle: .file))")
        print("  Documents: \(ByteCountFormatter.string(fromByteCount: docs, countStyle: .file))")
        print("  Desktop: \(ByteCountFormatter.string(fromByteCount: desktop, countStyle: .file))")
        print("  Downloads: \(ByteCountFormatter.string(fromByteCount: downloads, countStyle: .file))")
        print("  Pictures: \(ByteCountFormatter.string(fromByteCount: pictures, countStyle: .file))")
        print("  Movies: \(ByteCountFormatter.string(fromByteCount: movies, countStyle: .file))")
        print("  Music: \(ByteCountFormatter.string(fromByteCount: music, countStyle: .file))")
        print("  Caches: \(ByteCountFormatter.string(fromByteCount: caches, countStyle: .file))")
        print("  Logs: \(ByteCountFormatter.string(fromByteCount: logs, countStyle: .file))")
        print("  Other Library Data: \(ByteCountFormatter.string(fromByteCount: otherLibrarySize, countStyle: .file))")
        print("  Trash: \(ByteCountFormatter.string(fromByteCount: trash, countStyle: .file))")
        
        // System (estimated as remaining space after accounting for user data)
        let accountedSize = totalApplicationsSize + docs + caches + logs + downloads + desktop + pictures + movies + music + otherLibrarySize + trash
        let systemSize = max(0, usedSpace - accountedSize)
        
        print("  Accounted: \(ByteCountFormatter.string(fromByteCount: accountedSize, countStyle: .file))")
        print("  System (remainder): \(ByteCountFormatter.string(fromByteCount: systemSize, countStyle: .file))")
        
        var categories: [StorageCategoryData] = []
        
        // Create category data
        if totalApplicationsSize > 0 {
            categories.append(StorageCategoryData(
                name: "Applications",
                size: totalApplicationsSize,
                totalCapacity: totalCapacity,
                color: .blue
            ))
        }
        
        if docs > 0 {
            categories.append(StorageCategoryData(
                name: "Documents",
                size: docs,
                totalCapacity: totalCapacity,
                color: .green
            ))
        }
        
        if desktop > 0 {
            categories.append(StorageCategoryData(
                name: "Desktop",
                size: desktop,
                totalCapacity: totalCapacity,
                color: .cyan
            ))
        }
        
        if pictures > 0 {
            categories.append(StorageCategoryData(
                name: "Pictures",
                size: pictures,
                totalCapacity: totalCapacity,
                color: .pink
            ))
        }
        
        if movies > 0 {
            categories.append(StorageCategoryData(
                name: "Movies",
                size: movies,
                totalCapacity: totalCapacity,
                color: .red
            ))
        }
        
        if music > 0 {
            categories.append(StorageCategoryData(
                name: "Music",
                size: music,
                totalCapacity: totalCapacity,
                color: .indigo
            ))
        }
        
        if downloads > 0 {
            categories.append(StorageCategoryData(
                name: "Downloads",
                size: downloads,
                totalCapacity: totalCapacity,
                color: .purple,
                isDeletable: true
            ))
        }
        
        if caches > 0 {
            categories.append(StorageCategoryData(
                name: "Caches",
                size: caches,
                totalCapacity: totalCapacity,
                color: .orange,
                isDeletable: true
            ))
        }
        
        if logs > 0 {
            categories.append(StorageCategoryData(
                name: "Logs",
                size: logs,
                totalCapacity: totalCapacity,
                color: .yellow,
                isDeletable: true
            ))
        }
        
        if otherLibrarySize > 1_000_000_000 { // Only show if > 1GB
            categories.append(StorageCategoryData(
                name: "App Data",
                size: otherLibrarySize,
                totalCapacity: totalCapacity,
                color: .teal
            ))
        }
        
        if trash > 1_000_000_000 { // Only show if > 1GB
            categories.append(StorageCategoryData(
                name: "Trash",
                size: trash,
                totalCapacity: totalCapacity,
                color: .brown,
                isDeletable: true
            ))
        }
        
        if systemSize > 0 {
            categories.append(StorageCategoryData(
                name: "System",
                size: systemSize,
                totalCapacity: totalCapacity,
                color: .gray,
                isDeletable: false
            ))
        }
        
        // Sort by size descending
        categoryData = categories.sorted { $0.size > $1.size }
    }
    
    private func calculateDirectorySize(path: String) async -> Int64 {
        // Move file system operations to a background thread
        return await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else { return 0 }
            
            var totalSize: Int64 = 0
            
            // Use URL-based enumerator for better memory efficiency
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            
            // Process files one at a time instead of loading all into memory
            for case let fileURL as URL in enumerator {
                // Check if it's a regular file (not a directory)
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                   let isDirectory = resourceValues.isDirectory,
                   !isDirectory,
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            
            return totalSize
        }.value
    }
    
    // MARK: - Drill-down Navigation
    
    func selectCategory(_ category: StorageCategoryData) {
        selectedCategory = category
        navigationPath.append(category)
        
        // Load subcategories and items if not already loaded
        Task {
            await loadCategoryDetails(for: category)
        }
    }
    
    func navigateBack() {
        guard !navigationPath.isEmpty else { return }
        navigationPath.removeLast()
        selectedCategory = navigationPath.last
    }
    
    func navigateToRoot() {
        navigationPath.removeAll()
        selectedCategory = nil
    }
    
    private func loadCategoryDetails(for category: StorageCategoryData) async {
        print("DEBUG: Loading details for category: \(category.name)")
        
        // Find the category in our data and update it with details
        guard let index = categoryData.firstIndex(where: { $0.id == category.id }) else {
            print("DEBUG: Category not found in categoryData")
            return
        }
        
        var updatedCategory = categoryData[index]
        
        // Load subcategories and items based on category name
        switch category.name {
        case "Applications":
            updatedCategory = await loadApplicationsDetails(category: updatedCategory)
        case "Documents":
            updatedCategory = await loadDocumentsDetails(category: updatedCategory)
        case "Desktop":
            updatedCategory = await loadDesktopDetails(category: updatedCategory)
        case "Pictures":
            updatedCategory = await loadPicturesDetails(category: updatedCategory)
        case "Movies":
            updatedCategory = await loadMoviesDetails(category: updatedCategory)
        case "Music":
            updatedCategory = await loadMusicDetails(category: updatedCategory)
        case "Downloads":
            updatedCategory = await loadDownloadsDetails(category: updatedCategory)
        case "Caches":
            updatedCategory = await loadCachesDetails(category: updatedCategory)
        case "Logs":
            updatedCategory = await loadLogsDetails(category: updatedCategory)
        case "App Data":
            updatedCategory = await loadAppDataDetails(category: updatedCategory)
        case "Trash":
            updatedCategory = await loadTrashDetails(category: updatedCategory)
        case "System":
            updatedCategory = await loadSystemDetails(category: updatedCategory)
        default:
            break
        }
        
        print("DEBUG: Loaded \(updatedCategory.subcategories.count) subcategories and \(updatedCategory.items.count) items")
        
        categoryData[index] = updatedCategory
        
        // Update selected category with new details
        if let navIndex = navigationPath.firstIndex(where: { $0.id == category.id }) {
            navigationPath[navIndex] = updatedCategory
            if navIndex == navigationPath.count - 1 {
                selectedCategory = updatedCategory
                print("DEBUG: Updated selectedCategory with details")
            }
        }
    }
    
    private func loadApplicationsDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        // Get top applications by size
        let applicationsPath = "/Applications"
        let userApplicationsPath = NSHomeDirectory() + "/Applications"
        
        var items: [StorageItemData] = []
        
        // Scan /Applications
        items += await getTopItemsInDirectory(path: applicationsPath, limit: 20)
        
        // Scan ~/Applications
        items += await getTopItemsInDirectory(path: userApplicationsPath, limit: 20)
        
        // Sort by size and take top 20
        items.sort { $0.size > $1.size }
        updated.items = Array(items.prefix(20))
        
        return updated
    }
    
    private func loadDocumentsDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        let documentsPath = NSHomeDirectory() + "/Documents"
        
        // Get top files and folders
        updated.items = await getTopItemsInDirectory(path: documentsPath, limit: 20)
        
        return updated
    }
    
    private func loadDownloadsDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        let downloadsPath = NSHomeDirectory() + "/Downloads"
        
        // Get top files and folders
        updated.items = await getTopItemsInDirectory(path: downloadsPath, limit: 20)
        
        return updated
    }
    
    private func loadLogsDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        let logsPath = NSHomeDirectory() + "/Library/Logs"
        
        // Get top log files and folders
        updated.items = await getTopItemsInDirectory(path: logsPath, limit: 20)
        
        return updated
    }
    
    private func loadDesktopDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        updated.items = await getTopItemsInDirectory(path: NSHomeDirectory() + "/Desktop", limit: 20)
        return updated
    }
    
    private func loadPicturesDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        updated.items = await getTopItemsInDirectory(path: NSHomeDirectory() + "/Pictures", limit: 20)
        return updated
    }
    
    private func loadMoviesDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        updated.items = await getTopItemsInDirectory(path: NSHomeDirectory() + "/Movies", limit: 20)
        return updated
    }
    
    private func loadMusicDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        updated.items = await getTopItemsInDirectory(path: NSHomeDirectory() + "/Music", limit: 20)
        return updated
    }
    
    private func loadAppDataDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        // Show top items in Library (excluding Caches and Logs which are separate)
        let libraryPath = NSHomeDirectory() + "/Library"
        var items = await getTopItemsInDirectory(path: libraryPath, limit: 30)
        // Filter out Caches and Logs
        items = items.filter { !$0.name.contains("Caches") && !$0.name.contains("Logs") }
        updated.items = Array(items.prefix(20))
        return updated
    }
    
    private func loadTrashDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        updated.items = await getTopItemsInDirectory(path: NSHomeDirectory() + "/.Trash", limit: 20)
        return updated
    }
    
    private func loadCachesDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        let cachesPath = NSHomeDirectory() + "/Library/Caches"
        
        // Create subcategories for different cache types
        var subcategories: [StorageCategoryData] = []
        
        let fileManager = FileManager.default
        if let contents = try? fileManager.contentsOfDirectory(atPath: cachesPath) {
            for item in contents.prefix(10) {
                let itemPath = (cachesPath as NSString).appendingPathComponent(item)
                let size = await calculateDirectorySize(path: itemPath)
                
                if size > 0 {
                    subcategories.append(StorageCategoryData(
                        name: item,
                        size: size,
                        totalCapacity: totalCapacity,
                        color: .orange
                    ))
                }
            }
        }
        
        // Sort by size
        subcategories.sort { $0.size > $1.size }
        updated.subcategories = Array(subcategories.prefix(10))
        
        return updated
    }
    
    private func loadSystemDetails(category: StorageCategoryData) async -> StorageCategoryData {
        var updated = category
        
        // Show breakdown of what's in "System" - inspired by osx_cleaner approach
        var subcategories: [StorageCategoryData] = []
        
        // Calculate sizes of major system components
        async let systemOS = calculateDirectorySize(path: "/System")
        async let systemLibrary = calculateDirectorySize(path: "/Library")
        async let userLibrarySize = calculateDirectorySize(path: NSHomeDirectory() + "/Library")
        async let privateVar = calculateDirectorySize(path: "/private/var")
        async let coreServices = calculateDirectorySize(path: "/System/Library/CoreServices")
        
        let (sysOS, sysLib, userLib, privVar, coreSvc) = await (systemOS, systemLibrary, userLibrarySize, privateVar, coreServices)
        
        // macOS System Files (read-only, cannot delete)
        if sysOS > 0 {
            subcategories.append(StorageCategoryData(
                name: "macOS System",
                size: sysOS,
                totalCapacity: totalCapacity,
                color: .gray,
                isDeletable: false
            ))
        }
        
        // System Library (shared frameworks, cannot delete)
        if sysLib > 0 {
            subcategories.append(StorageCategoryData(
                name: "System Library",
                size: sysLib,
                totalCapacity: totalCapacity,
                color: .gray,
                isDeletable: false
            ))
        }
        
        // User Library (app support, preferences - mostly safe but complex)
        if userLib > 0 {
            subcategories.append(StorageCategoryData(
                name: "User Library",
                size: userLib,
                totalCapacity: totalCapacity,
                color: .orange,
                isDeletable: false
            ))
        }
        
        // System Data (/private/var - logs, temp files, some deletable)
        if privVar > 0 {
            subcategories.append(StorageCategoryData(
                name: "System Data",
                size: privVar,
                totalCapacity: totalCapacity,
                color: .yellow,
                isDeletable: false
            ))
        }
        
        updated.subcategories = subcategories.sorted { $0.size > $1.size }
        
        return updated
    }
    
    private func getTopItemsInDirectory(path: String, limit: Int) async -> [StorageItemData] {
        // Move file system operations to a background thread
        return await Task.detached(priority: .userInitiated) { [weak self] in
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else { return [] }
            
            var items: [StorageItemData] = []
            
            if let contents = try? fileManager.contentsOfDirectory(atPath: path) {
                for item in contents {
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) else { continue }
                    
                    let size: Int64
                    if isDirectory.boolValue {
                        // Calculate directory size on background thread
                        size = await self?.calculateDirectorySize(path: itemPath) ?? 0
                    } else {
                        if let attributes = try? fileManager.attributesOfItem(atPath: itemPath),
                           let fileSize = attributes[.size] as? Int64 {
                            size = fileSize
                        } else {
                            continue
                        }
                    }
                    
                    let itemType: StorageItemData.ItemType
                    if itemPath.hasSuffix(".app") {
                        itemType = .application
                    } else if isDirectory.boolValue {
                        itemType = .directory
                    } else {
                        itemType = .file
                    }
                    
                    items.append(StorageItemData(
                        name: item,
                        path: itemPath,
                        size: size,
                        type: itemType
                    ))
                }
            }
            
            // Sort by size and return top items
            items.sort { $0.size > $1.size }
            return Array(items.prefix(limit))
        }.value
    }
    
    // MARK: - Real-time Updates
    
    func updateAfterCleanup(removedSize: Int64, category: String) {
        // Update available space
        availableSpace += removedSize
        usedSpace -= removedSize
        
        // Update category data
        if let index = categoryData.firstIndex(where: { $0.name == category }) {
            let updatedCategory = categoryData[index]
            let newSize = max(0, updatedCategory.size - removedSize)
            
            categoryData[index] = StorageCategoryData(
                name: updatedCategory.name,
                size: newSize,
                totalCapacity: totalCapacity,
                color: updatedCategory.color,
                subcategories: updatedCategory.subcategories,
                items: updatedCategory.items
            )
            
            // Reload details if this category is selected
            if selectedCategory?.id == updatedCategory.id {
                Task {
                    await loadCategoryDetails(for: categoryData[index])
                }
            }
        }
    }
    
    // MARK: - Scan Operations
    
    func startScan() async {
        isScanning = true
        scanProgress = ScanProgressData()
        lastScanResult = nil
        
        // Determine which categories to scan based on configuration
        var categories = Set<CleanupCategory>()
        if scanIncludeSystemCaches { categories.insert(.systemCaches) }
        if scanIncludeAppCaches { categories.insert(.applicationCaches) }
        if scanIncludeTempFiles { categories.insert(.temporaryFiles) }
        if scanIncludeLargeFiles { categories.insert(.largeFiles) }
        if scanIncludeOldFiles { categories.insert(.oldFiles) }
        if scanIncludeLogFiles { categories.insert(.logFiles) }
        
        // Determine paths to scan
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            homeDirectory.appendingPathComponent("Library/Caches"),
            homeDirectory.appendingPathComponent("Library/Logs"),
            homeDirectory.appendingPathComponent("Downloads"),
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/var/tmp")
        ]
        
        // Add developer tool cache paths if enabled
        if scanIncludeDeveloperCaches {
            paths.append(contentsOf: [
                homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                homeDirectory.appendingPathComponent("Library/Developer/Xcode/Archives"),
                homeDirectory.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
                homeDirectory.appendingPathComponent("Library/Caches/CocoaPods"),
                homeDirectory.appendingPathComponent("Library/Caches/Homebrew"),
                homeDirectory.appendingPathComponent(".gradle/caches"),
                homeDirectory.appendingPathComponent(".npm"),
                homeDirectory.appendingPathComponent("Library/Caches/Yarn")
            ])
        }
        
        // Add AI agent cache paths if enabled
        if scanIncludeAIAgentCaches {
            paths.append(contentsOf: [
                homeDirectory.appendingPathComponent("Library/Application Support/Cursor/Cache"),
                homeDirectory.appendingPathComponent("Library/Application Support/Cursor/CachedData"),
                homeDirectory.appendingPathComponent(".kiro/cache"),
                homeDirectory.appendingPathComponent("Library/Caches/Kiro"),
                homeDirectory.appendingPathComponent(".codeium"),
                homeDirectory.appendingPathComponent(".tabnine"),
                homeDirectory.appendingPathComponent(".continue"),
                homeDirectory.appendingPathComponent(".aider")
            ])
        }
        
        // Create scanner if needed
        if fileScanner == nil {
            fileScanner = coordinator.fileScanner
        }
        
        do {
            let result = try await coordinator.performScan(
                paths: paths,
                categories: categories,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = ScanProgressData(
                            currentPath: progress.currentPath,
                            filesScanned: progress.filesScanned,
                            percentComplete: progress.percentComplete
                        )
                    }
                }
            )
            
            // Process scan results
            await processScanResults(result, categories: categories)
        } catch {
            print("Scan error: \(error)")
        }
        
        isScanning = false
    }
    
    func cancelScan() {
        fileScanner?.cancelScan()
        isScanning = false
    }
    
    func dismissScanResults() {
        lastScanResult = nil
    }
    
    private func processScanResults(_ result: ScanResult, categories: Set<CleanupCategory>) async {
        // Group files by category
        var categorySummary: [CleanupCategory: CategorySummary] = [:]
        
        for file in result.files {
            let fileCategories = fileScanner?.categorize(file: file) ?? []
            
            for category in fileCategories where categories.contains(category) {
                if var summary = categorySummary[category] {
                    summary.count += 1
                    summary.size += file.size
                    categorySummary[category] = summary
                } else {
                    categorySummary[category] = CategorySummary(count: 1, size: file.size)
                }
            }
        }
        
        // Create scan result data
        lastScanResult = ScanResultData(
            filesScanned: result.files.count,
            duration: result.duration,
            errorCount: result.errors.count,
            categorySummary: categorySummary
        )
    }
    
    // Preview helper
    static var preview: StorageViewModel {
        let vm = StorageViewModel()
        vm.isLoading = false
        vm.totalCapacity = 500_000_000_000 // 500 GB
        vm.usedSpace = 350_000_000_000 // 350 GB
        vm.availableSpace = 150_000_000_000 // 150 GB
        
        // Create sample items for Applications
        let appItems = [
            StorageItemData(name: "Xcode.app", path: "/Applications/Xcode.app", size: 15_000_000_000, type: .application),
            StorageItemData(name: "Final Cut Pro.app", path: "/Applications/Final Cut Pro.app", size: 8_000_000_000, type: .application),
            StorageItemData(name: "Logic Pro.app", path: "/Applications/Logic Pro.app", size: 5_000_000_000, type: .application)
        ]
        
        // Create sample subcategories for Caches
        let cacheSubcategories = [
            StorageCategoryData(name: "com.apple.Safari", size: 5_000_000_000, totalCapacity: 500_000_000_000, color: .orange),
            StorageCategoryData(name: "com.google.Chrome", size: 3_000_000_000, totalCapacity: 500_000_000_000, color: .orange),
            StorageCategoryData(name: "com.apple.Music", size: 2_000_000_000, totalCapacity: 500_000_000_000, color: .orange)
        ]
        
        vm.categoryData = [
            StorageCategoryData(name: "Applications", size: 100_000_000_000, totalCapacity: 500_000_000_000, color: .blue, subcategories: [], items: appItems),
            StorageCategoryData(name: "Documents", size: 80_000_000_000, totalCapacity: 500_000_000_000, color: .green),
            StorageCategoryData(name: "System", size: 120_000_000_000, totalCapacity: 500_000_000_000, color: .gray),
            StorageCategoryData(name: "Caches", size: 30_000_000_000, totalCapacity: 500_000_000_000, color: .orange, subcategories: cacheSubcategories),
            StorageCategoryData(name: "Other", size: 20_000_000_000, totalCapacity: 500_000_000_000, color: .purple)
        ]
        return vm
    }
}

// MARK: - Supporting Data Structures

struct ScanProgressData {
    var currentPath: String = ""
    var filesScanned: Int = 0
    var percentComplete: Double = 0.0
}

struct ScanResultData {
    let filesScanned: Int
    let duration: TimeInterval
    let errorCount: Int
    let categorySummary: [CleanupCategory: CategorySummary]
}

struct CategorySummary {
    var count: Int
    var size: Int64
}
