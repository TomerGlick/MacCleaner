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
    private let detailItemLimit = 20
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
        appendCategory(named: "Applications", size: totalApplicationsSize, totalCapacity: totalCapacity, color: .blue, to: &categories)
        appendCategory(named: "Documents", size: documents, totalCapacity: totalCapacity, color: .green, to: &categories)
        appendCategory(named: "Desktop", size: desktop, totalCapacity: totalCapacity, color: .cyan, to: &categories)
        appendCategory(named: "Pictures", size: pictures, totalCapacity: totalCapacity, color: .pink, to: &categories)
        appendCategory(named: "Movies", size: movies, totalCapacity: totalCapacity, color: .red, to: &categories)
        appendCategory(named: "Music", size: music, totalCapacity: totalCapacity, color: .indigo, to: &categories)
        appendCategory(named: "Downloads", size: downloads, totalCapacity: totalCapacity, color: .purple, isDeletable: true, to: &categories)
        appendCategory(named: "Caches", size: caches, totalCapacity: totalCapacity, color: .orange, isDeletable: true, to: &categories)
        appendCategory(named: "Logs", size: logs, totalCapacity: totalCapacity, color: .yellow, isDeletable: true, to: &categories)

        if otherLibrarySize > minimumVisibleCategorySize {
            appendCategory(named: "App Data", size: otherLibrarySize, totalCapacity: totalCapacity, color: .teal, to: &categories)
        }

        if trash > minimumVisibleCategorySize {
            appendCategory(named: "Trash", size: trash, totalCapacity: totalCapacity, color: .brown, isDeletable: true, to: &categories)
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
        case "Applications":
            return try await loadApplicationsDetails(category: category, homeDirectory: homeDirectory)
        case "Documents":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Documents")
        case "Desktop":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Desktop")
        case "Pictures":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Pictures")
        case "Movies":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Movies")
        case "Music":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Music")
        case "Downloads":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Downloads")
        case "Caches":
            return try await loadCachesDetails(category: category, totalCapacity: totalCapacity, homeDirectory: homeDirectory)
        case "Logs":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/Library/Logs")
        case "App Data":
            return try await loadAppDataDetails(category: category, homeDirectory: homeDirectory)
        case "Trash":
            return try await loadTopItemsDetails(category: category, path: homeDirectory + "/.Trash")
        case "System":
            return try await loadSystemDetails(category: category, totalCapacity: totalCapacity, homeDirectory: homeDirectory)
        default:
            return category
        }
    }

    private func loadApplicationsDetails(category: StorageCategoryData, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        var items = try await inspectionService.topItems(inDirectory: "/Applications", limit: detailItemLimit)
        items += try await inspectionService.topItems(inDirectory: homeDirectory + "/Applications", limit: detailItemLimit)
        items.sort { $0.size > $1.size }
        updatedCategory.items = Array(items.prefix(detailItemLimit))
        return updatedCategory
    }

    private func loadTopItemsDetails(category: StorageCategoryData, path: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        updatedCategory.items = try await inspectionService.topItems(inDirectory: path, limit: detailItemLimit)
        return updatedCategory
    }

    private func loadCachesDetails(category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        let cacheItems = try await inspectionService.topItems(inDirectory: homeDirectory + "/Library/Caches", limit: detailItemLimit)

        updatedCategory.subcategories = Array(
            cacheItems
                .filter { $0.type != .file }
                .prefix(10)
                .map {
                    StorageCategoryData(
                        name: $0.name,
                        size: $0.size,
                        totalCapacity: totalCapacity,
                        color: .orange
                    )
                }
        )
        updatedCategory.items = cacheItems
        return updatedCategory
    }

    private func loadAppDataDetails(category: StorageCategoryData, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        let items = try await inspectionService.topItems(inDirectory: homeDirectory + "/Library", limit: 30)
        updatedCategory.items = Array(
            items
                .filter { !$0.name.contains("Caches") && !$0.name.contains("Logs") }
                .prefix(detailItemLimit)
        )
        return updatedCategory
    }

    private func loadSystemDetails(category: StorageCategoryData, totalCapacity: Int64, homeDirectory: String) async throws -> StorageCategoryData {
        var updatedCategory = category
        var subcategories: [StorageCategoryData] = []

        async let systemOS = inspectionService.directorySize(at: "/System")
        async let systemLibrary = inspectionService.directorySize(at: "/Library")
        async let userLibrary = inspectionService.directorySize(at: homeDirectory + "/Library")
        async let privateVar = inspectionService.directorySize(at: "/private/var")

        appendCategory(named: "macOS System", size: try await systemOS, totalCapacity: totalCapacity, color: .gray, to: &subcategories)
        appendCategory(named: "System Library", size: try await systemLibrary, totalCapacity: totalCapacity, color: .gray, to: &subcategories)
        appendCategory(named: "User Library", size: try await userLibrary, totalCapacity: totalCapacity, color: .orange, to: &subcategories)
        appendCategory(named: "System Data", size: try await privateVar, totalCapacity: totalCapacity, color: .yellow, to: &subcategories)

        updatedCategory.subcategories = subcategories.sorted { $0.size > $1.size }
        return updatedCategory
    }

    private func appendCategory(
        named name: String,
        size: Int64,
        totalCapacity: Int64,
        color: Color,
        isDeletable: Bool = false,
        to categories: inout [StorageCategoryData]
    ) {
        guard size > 0 else { return }

        categories.append(
            StorageCategoryData(
                name: name,
                size: size,
                totalCapacity: totalCapacity,
                color: color,
                isDeletable: isDeletable
            )
        )
    }
}
