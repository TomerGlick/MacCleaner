import Foundation
import SwiftUI

protocol StorageAnalysisService {
    func beginSession() async
    func cancelSession() async
    func invalidateSession() async
    func categoryBreakdown(totalCapacity: Int64, usedSpace: Int64, homeDirectory: String) async throws -> StorageBreakdownResult
    func details(for category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData
}

struct StorageBreakdownResult {
    let categories: [StorageCategoryData]
    let summary: StorageBreakdownSummary
}

struct StorageBreakdownSummary {
    let applications: Int64
    let documents: Int64
    let desktop: Int64
    let downloads: Int64
    let pictures: Int64
    let movies: Int64
    let music: Int64
    let caches: Int64
    let logs: Int64
    let appData: Int64
    let trash: Int64
    let accounted: Int64
    let system: Int64
}

final class DefaultStorageAnalysisService: StorageAnalysisService {
    private let inspectionService: any StorageInspectionService
    private let folderItemLimit = 100
    private let minimumVisibleCategorySize: Int64 = 1_000_000_000

    init(inspectionService: any StorageInspectionService = DefaultStorageInspectionService()) {
        self.inspectionService = inspectionService
    }

    func beginSession() async {
        await inspectionService.beginSession()
    }

    func cancelSession() async {
        await inspectionService.cancelSession()
    }

    func invalidateSession() async {
        await inspectionService.beginSession()
    }

    func categoryBreakdown(totalCapacity: Int64, usedSpace: Int64, homeDirectory: String) async throws -> StorageBreakdownResult {
        async let applicationsSize = inspectionService.directorySize(at: "/Applications")
        async let userApplicationsSize = inspectionService.directorySize(at: homeDirectory + "/Applications")
        async let documentsSize = inspectionService.directorySize(at: homeDirectory + "/Documents")
        async let cachesSize = inspectionService.directorySize(at: homeDirectory + "/Library/Caches")
        async let logsSize = inspectionService.directorySize(at: homeDirectory + "/Library/Logs")
        async let downloadsSize = inspectionService.directorySize(at: homeDirectory + "/Downloads")
        async let desktopSize = inspectionService.directorySize(at: homeDirectory + "/Desktop")
        async let picturesSize = inspectionService.directorySize(at: homeDirectory + "/Pictures")
        async let moviesSize = inspectionService.directorySize(at: homeDirectory + "/Movies")
        async let musicSize = inspectionService.directorySize(at: homeDirectory + "/Music")
        async let librarySize = inspectionService.directorySize(at: homeDirectory + "/Library")
        async let trashSize = inspectionService.directorySize(at: homeDirectory + "/.Trash")

        let apps = try await applicationsSize
        let userApps = try await userApplicationsSize
        let documents = try await documentsSize
        let caches = try await cachesSize
        let logs = try await logsSize
        let downloads = try await downloadsSize
        let desktop = try await desktopSize
        let pictures = try await picturesSize
        let movies = try await moviesSize
        let music = try await musicSize
        let library = try await librarySize
        let trash = try await trashSize

        let totalApplicationsSize = apps + userApps
        let otherLibrarySize = max(0, library - caches - logs)
        let accountedSize = totalApplicationsSize + documents + caches + logs + downloads + desktop + pictures + movies + music + otherLibrarySize + trash
        let systemSize = max(0, usedSpace - accountedSize)

        var categories: [StorageCategoryData] = []
        appendCategory(named: "Applications", size: totalApplicationsSize, totalCapacity: totalCapacity, color: .blue, path: "/Applications", to: &categories)
        appendCategory(named: "Documents", size: documents, totalCapacity: totalCapacity, color: .green, path: homeDirectory + "/Documents", to: &categories)
        appendCategory(named: "Desktop", size: desktop, totalCapacity: totalCapacity, color: .cyan, path: homeDirectory + "/Desktop", to: &categories)
        appendCategory(named: "Pictures", size: pictures, totalCapacity: totalCapacity, color: .pink, path: homeDirectory + "/Pictures", to: &categories)
        appendCategory(named: "Movies", size: movies, totalCapacity: totalCapacity, color: .red, path: homeDirectory + "/Movies", to: &categories)
        appendCategory(named: "Music", size: music, totalCapacity: totalCapacity, color: .indigo, path: homeDirectory + "/Music", to: &categories)
        appendCategory(named: "Downloads", size: downloads, totalCapacity: totalCapacity, color: .purple, isDeletable: true, path: homeDirectory + "/Downloads", to: &categories)
        appendCategory(named: "Caches", size: caches, totalCapacity: totalCapacity, color: .orange, isDeletable: true, path: homeDirectory + "/Library/Caches", to: &categories)
        appendCategory(named: "Logs", size: logs, totalCapacity: totalCapacity, color: .yellow, isDeletable: true, path: homeDirectory + "/Library/Logs", to: &categories)

        if otherLibrarySize > minimumVisibleCategorySize {
            appendCategory(named: "App Data", size: otherLibrarySize, totalCapacity: totalCapacity, color: .teal, path: homeDirectory + "/Library", to: &categories)
        }

        if trash > minimumVisibleCategorySize {
            appendCategory(named: "Trash", size: trash, totalCapacity: totalCapacity, color: .brown, isDeletable: true, path: homeDirectory + "/.Trash", to: &categories)
        }

        appendCategory(named: "System", size: systemSize, totalCapacity: totalCapacity, color: .gray, to: &categories)

        return StorageBreakdownResult(
            categories: categories.sorted { $0.size > $1.size },
            summary: StorageBreakdownSummary(
                applications: totalApplicationsSize,
                documents: documents,
                desktop: desktop,
                downloads: downloads,
                pictures: pictures,
                movies: movies,
                music: music,
                caches: caches,
                logs: logs,
                appData: otherLibrarySize,
                trash: trash,
                accounted: accountedSize,
                system: systemSize
            )
        )
    }

    func details(for category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        switch category.name {
        case "Applications" where category.path == "/Applications":
            return try await loadApplicationsDetails(category: category, totalCapacity: totalCapacity, homeDirectory: homeDirectory)
        case "App Data" where category.path == homeDirectory + "/Library":
            return try await loadAppDataDetails(category: category, totalCapacity: totalCapacity, homeDirectory: homeDirectory)
        case "System" where category.path == nil:
            return try await loadSystemDetails(category: category, totalCapacity: totalCapacity, homeDirectory: homeDirectory)
        default:
            guard let path = category.path else { return category }
            return try await loadFolderDetails(category: category, totalCapacity: totalCapacity, path: path)
        }
    }

    /// Generic folder drill-down: sub-folders become drillable subcategories, files stay as items.
    private func loadFolderDetails(category: StorageCategoryData, totalCapacity: Int64, path: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        let entries = try await inspectionService.topItems(inDirectory: path, limit: folderItemLimit)

        updatedCategory.subcategories = entries
            .filter { $0.type == .directory }
            .map {
                StorageCategoryData(
                    item: $0,
                    totalCapacity: totalCapacity,
                    color: category.color,
                    isDeletable: category.isDeletable
                )
            }

        updatedCategory.items = entries.filter { $0.type != .directory }
        return updatedCategory
    }

    private func loadApplicationsDetails(category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        var entries = try await inspectionService.topItems(inDirectory: "/Applications", limit: folderItemLimit)
        entries += try await inspectionService.topItems(inDirectory: homeDirectory + "/Applications", limit: folderItemLimit)
        entries.sort { $0.size > $1.size }

        updatedCategory.subcategories = entries
            .filter { $0.type == .directory }
            .map { StorageCategoryData(item: $0, totalCapacity: totalCapacity, color: category.color) }
        updatedCategory.items = entries.filter { $0.type != .directory }
        return updatedCategory
    }

    private func loadAppDataDetails(category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        let entries = try await inspectionService.topItems(inDirectory: homeDirectory + "/Library", limit: folderItemLimit)
            .filter { $0.name != "Caches" && $0.name != "Logs" }

        updatedCategory.subcategories = entries
            .filter { $0.type == .directory }
            .map { StorageCategoryData(item: $0, totalCapacity: totalCapacity, color: category.color) }
        updatedCategory.items = entries.filter { $0.type != .directory }
        return updatedCategory
    }

    private func loadSystemDetails(category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        var subcategories: [StorageCategoryData] = []

        async let systemOS = inspectionService.directorySize(at: "/System")
        async let systemLibrary = inspectionService.directorySize(at: "/Library")
        async let userLibrary = inspectionService.directorySize(at: homeDirectory + "/Library")
        async let privateVar = inspectionService.directorySize(at: "/private/var")

        appendCategory(named: "macOS System", size: try await systemOS, totalCapacity: totalCapacity, color: .gray, path: "/System", to: &subcategories)
        appendCategory(named: "System Library", size: try await systemLibrary, totalCapacity: totalCapacity, color: .gray, path: "/Library", to: &subcategories)
        appendCategory(named: "User Library", size: try await userLibrary, totalCapacity: totalCapacity, color: .orange, path: homeDirectory + "/Library", to: &subcategories)
        appendCategory(named: "System Data", size: try await privateVar, totalCapacity: totalCapacity, color: .yellow, path: "/private/var", to: &subcategories)

        updatedCategory.subcategories = subcategories.sorted { $0.size > $1.size }
        return updatedCategory
    }

    private func appendCategory(
        named name: String,
        size: Int64,
        totalCapacity: Int64,
        color: Color,
        isDeletable: Bool = false,
        path: String? = nil,
        to categories: inout [StorageCategoryData]
    ) {
        guard size > 0 else { return }

        categories.append(
            StorageCategoryData(
                name: name,
                size: size,
                totalCapacity: totalCapacity,
                color: color,
                isDeletable: isDeletable,
                path: path
            )
        )
    }
}
