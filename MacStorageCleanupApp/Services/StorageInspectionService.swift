import Foundation

protocol StorageInspectionService: Actor {
    func beginSession()
    func cancelSession()
    func directorySize(at path: String) async throws -> Int64
    func topItems(inDirectory path: String, limit: Int) async throws -> [StorageItemData]
}

actor DefaultStorageInspectionService: StorageInspectionService {
    private let fileManager: FileManager
    private var sizeCache: [String: Int64] = [:]
    private var topItemsCache: [TopItemsCacheKey: [StorageItemData]] = [:]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func beginSession() {
        sizeCache.removeAll()
        topItemsCache.removeAll()
    }

    func cancelSession() {
        sizeCache.removeAll()
        topItemsCache.removeAll()
    }

    func directorySize(at path: String) async throws -> Int64 {
        if let cachedSize = sizeCache[path] {
            return cachedSize
        }

        let size = try await Self.computeDirectorySize(fileManager: fileManager, path: path)
        sizeCache[path] = size
        return size
    }

    func topItems(inDirectory path: String, limit: Int) async throws -> [StorageItemData] {
        let cacheKey = TopItemsCacheKey(path: path, limit: limit)
        if let cachedItems = topItemsCache[cacheKey] {
            return cachedItems
        }

        let entries = try await Self.readDirectoryEntries(fileManager: fileManager, path: path)
        var items: [StorageItemData] = []
        items.reserveCapacity(entries.count)

        for entry in entries {
            try Task.checkCancellation()

            let size: Int64
            if entry.isDirectory {
                size = try await directorySize(at: entry.path)
            } else {
                size = entry.fileSize
            }

            items.append(
                StorageItemData(
                    name: entry.name,
                    path: entry.path,
                    size: size,
                    type: entry.itemType
                )
            )
        }

        items.sort { $0.size > $1.size }
        let topItems = Array(items.prefix(limit))
        topItemsCache[cacheKey] = topItems
        return topItems
    }

    private static func computeDirectorySize(fileManager: FileManager, path: String) async throws -> Int64 {
        try await Task(priority: .userInitiated) {
            guard fileManager.fileExists(atPath: path) else { return Int64(0) }

            var totalSize: Int64 = 0
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return Int64(0)
            }

            while let fileURL = enumerator.nextObject() as? URL {
                try Task.checkCancellation()

                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                      resourceValues.isDirectory == false,
                      let fileSize = resourceValues.fileSize else {
                    continue
                }

                totalSize += Int64(fileSize)
            }

            return totalSize
        }.value
    }

    private static func readDirectoryEntries(fileManager: FileManager, path: String) async throws -> [DirectoryEntry] {
        try await Task(priority: .userInitiated) {
            guard fileManager.fileExists(atPath: path) else { return [] }

            let directoryURL = URL(fileURLWithPath: path)
            let contents = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            return try contents.map { itemURL in
                try Task.checkCancellation()
                let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                let isDirectory = resourceValues.isDirectory ?? false
                let itemType: StorageItemData.ItemType

                if itemURL.pathExtension == "app" {
                    itemType = .application
                } else if isDirectory {
                    itemType = .directory
                } else {
                    itemType = .file
                }

                return DirectoryEntry(
                    name: itemURL.lastPathComponent,
                    path: itemURL.path,
                    isDirectory: isDirectory,
                    fileSize: Int64(resourceValues.fileSize ?? 0),
                    itemType: itemType
                )
            }
        }.value
    }
}

private struct TopItemsCacheKey: Hashable, Sendable {
    let path: String
    let limit: Int
}

private struct DirectoryEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int64
    let itemType: StorageItemData.ItemType
}
