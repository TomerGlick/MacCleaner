import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class StorageViewModel: ObservableObject {
    @Published var isLoading = false
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
    private let coordinator: ApplicationCoordinator
    private let storageAnalysisService: StorageAnalysisService
    private let loggingService: LoggingService
    private var storageAnalysisTask: Task<Void, Never>?
    private var detailLoadTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var storageAnalysisToken = UUID()
    private var detailLoadToken = UUID()
    private var scanToken = UUID()

    init(
        coordinator: ApplicationCoordinator? = nil,
        storageAnalysisService: StorageAnalysisService = DefaultStorageAnalysisService(),
        loggingService: LoggingService = .shared
    ) {
        self.coordinator = coordinator ?? .shared
        self.storageAnalysisService = storageAnalysisService
        self.loggingService = loggingService
    }
    
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
        storageAnalysisTask?.cancel()
        detailLoadTask?.cancel()

        let token = UUID()
        storageAnalysisToken = token

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            self.isLoading = true
            self.selectedCategory = nil
            self.navigationPath.removeAll()
            await self.storageAnalysisService.beginSession()

            defer {
                if self.storageAnalysisToken == token {
                    self.isLoading = false
                    self.storageAnalysisTask = nil
                }
            }

            await self.refreshDiskSpace()

            do {
                try Task.checkCancellation()

                let breakdown = try await self.storageAnalysisService.categoryBreakdown(
                    totalCapacity: self.totalCapacity,
                    usedSpace: self.usedSpace,
                    homeDirectory: NSHomeDirectory()
                )

                try Task.checkCancellation()
                guard self.storageAnalysisToken == token else { return }

                self.categoryData = breakdown.categories
                self.logStorageBreakdown(breakdown.summary)
            } catch is CancellationError {
                self.loggingService.debug("Storage analysis cancelled")
            } catch {
                self.loggingService.error("Storage analysis failed", error: error)
            }
        }

        storageAnalysisTask = task
        await task.value
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
                loggingService.error("Error getting volume information", error: error)
            }
        }
    }
    
    // MARK: - Drill-down Navigation
    
    func selectCategory(_ category: StorageCategoryData) {
        selectedCategory = category
        if navigationPath.last?.id != category.id {
            navigationPath.append(category)
        }

        scheduleCategoryDetailsLoad(for: category)
    }
    
    func navigateBack() {
        guard !navigationPath.isEmpty else { return }
        detailLoadTask?.cancel()
        detailLoadTask = nil
        navigationPath.removeLast()
        selectedCategory = navigationPath.last
    }
    
    func navigateToRoot() {
        detailLoadTask?.cancel()
        detailLoadTask = nil
        navigationPath.removeAll()
        selectedCategory = nil
    }

    func cancelStorageAnalysis() {
        storageAnalysisToken = UUID()
        detailLoadToken = UUID()
        storageAnalysisTask?.cancel()
        detailLoadTask?.cancel()
        storageAnalysisTask = nil
        detailLoadTask = nil
        isLoading = false

        Task {
            await storageAnalysisService.cancelSession()
        }
    }

    private func scheduleCategoryDetailsLoad(for category: StorageCategoryData) {
        loggingService.debug("Loading details for category \(category.name)")

        detailLoadTask?.cancel()
        let token = UUID()
        detailLoadToken = token

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            guard self.categoryData.contains(where: { $0.id == category.id }) else {
                self.loggingService.warning("Category detail load skipped because \(category.name) was not found in category data")
                return
            }

            do {
                let updatedCategory = try await self.storageAnalysisService.details(
                    for: category,
                    totalCapacity: self.totalCapacity,
                    homeDirectory: NSHomeDirectory()
                )

                guard !Task.isCancelled, self.detailLoadToken == token else { return }
                self.applyLoadedCategory(updatedCategory, originalCategoryID: category.id)
            } catch is CancellationError {
                self.loggingService.debug("Category detail loading cancelled for \(category.name)")
            } catch {
                self.loggingService.error("Category detail loading failed for \(category.name)", error: error)
            }

            if self.detailLoadToken == token {
                self.detailLoadTask = nil
            }
        }

        detailLoadTask = task
    }

    private func applyLoadedCategory(_ updatedCategory: StorageCategoryData, originalCategoryID: UUID) {
        loggingService.debug("Loaded \(updatedCategory.subcategories.count) subcategories and \(updatedCategory.items.count) items for \(updatedCategory.name)")

        if let categoryIndex = categoryData.firstIndex(where: { $0.id == originalCategoryID }) {
            categoryData[categoryIndex] = updatedCategory
        }

        if let navigationIndex = navigationPath.firstIndex(where: { $0.id == originalCategoryID }) {
            navigationPath[navigationIndex] = updatedCategory
            if navigationIndex == navigationPath.count - 1 {
                selectedCategory = updatedCategory
                loggingService.debug("Updated selected category details for \(updatedCategory.name)")
            }
        }
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
                isDeletable: updatedCategory.isDeletable,
                subcategories: updatedCategory.subcategories,
                items: updatedCategory.items
            )
            
            // Reload details if this category is selected
            if selectedCategory?.id == updatedCategory.id {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.storageAnalysisService.invalidateSession()
                    self.scheduleCategoryDetailsLoad(for: self.categoryData[index])
                }
            }
        }
    }
    
    // MARK: - Scan Operations
    
    func startScan() async {
        scanTask?.cancel()

        let categories = configuredScanCategories()
        let paths = configuredScanPaths()

        // Create scanner if needed
        if fileScanner == nil {
            fileScanner = coordinator.fileScanner
        }

        let token = UUID()
        scanToken = token

        let task = Task { @MainActor [weak self] in
            guard let self else { return }

            self.isScanning = true
            self.scanProgress = ScanProgressData()
            self.lastScanResult = nil

            defer {
                if self.scanToken == token {
                    self.isScanning = false
                    self.scanTask = nil
                }
            }

            do {
                let result = try await self.coordinator.performScan(
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

                try Task.checkCancellation()
                guard self.scanToken == token else { return }
                await self.processScanResults(result, categories: categories)
            } catch is CancellationError {
                self.loggingService.debug("Cleanup scan cancelled")
            } catch {
                self.loggingService.error("Scan failed", error: error)
            }
        }

        scanTask = task
        await task.value
    }
    
    func cancelScan() {
        scanToken = UUID()
        fileScanner?.cancelScan()
        scanTask?.cancel()
        scanTask = nil
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

    private func configuredScanCategories() -> Set<CleanupCategory> {
        var categories = Set<CleanupCategory>()
        if scanIncludeSystemCaches { categories.insert(.systemCaches) }
        if scanIncludeAppCaches { categories.insert(.applicationCaches) }
        if scanIncludeTempFiles { categories.insert(.temporaryFiles) }
        if scanIncludeLargeFiles { categories.insert(.largeFiles) }
        if scanIncludeOldFiles { categories.insert(.oldFiles) }
        if scanIncludeLogFiles { categories.insert(.logFiles) }
        return categories
    }

    private func configuredScanPaths() -> [URL] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            homeDirectory.appendingPathComponent("Library/Caches"),
            homeDirectory.appendingPathComponent("Library/Logs"),
            homeDirectory.appendingPathComponent("Downloads"),
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/var/tmp")
        ]

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

        return paths
    }

    private func logStorageBreakdown(_ summary: StorageBreakdownSummary) {
        loggingService.debug(
            "Storage breakdown | used=\(formattedUsedSpace) applications=\(formatBytes(summary.applications)) documents=\(formatBytes(summary.documents)) desktop=\(formatBytes(summary.desktop)) downloads=\(formatBytes(summary.downloads)) pictures=\(formatBytes(summary.pictures)) movies=\(formatBytes(summary.movies)) music=\(formatBytes(summary.music)) caches=\(formatBytes(summary.caches)) logs=\(formatBytes(summary.logs)) appData=\(formatBytes(summary.appData)) trash=\(formatBytes(summary.trash)) accounted=\(formatBytes(summary.accounted)) system=\(formatBytes(summary.system))"
        )
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
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
