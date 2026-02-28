import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class FileBrowserViewModel: ObservableObject {
    @Published var currentPath: URL
    @Published var items: [FileItem] = []
    @Published var filteredItems: [FileItem] = []
    @Published var isLoading = false
    @Published var navigationStack: [URL] = []
    
    // Sorting
    @Published var sortBy: SortOption = .size {
        didSet { applySorting() }
    }
    @Published var sortAscending: Bool = false {
        didSet { applySorting() }
    }
    
    // Filtering
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var showHiddenFiles: Bool = false {
        didSet { applyFilters() }
    }
    @Published var minSize: Int64 = 0 {
        didSet { applyFilters() }
    }
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case modifiedDate = "Modified Date"
        case type = "Type"
        
        var displayName: String { rawValue }
    }
    
    // Selection
    var selectedCount: Int {
        items.filter { $0.isSelected }.count
    }
    
    var selectedSize: Int64 {
        items.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }
    
    var selectedItems: [FileItem] {
        items.filter { $0.isSelected }
    }
    
    init(startPath: URL? = nil) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        self.currentPath = startPath ?? homeDir
        self.navigationStack = [self.currentPath]
    }
    
    // MARK: - Navigation
    
    func navigateToHome() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        navigateTo(homeDir)
    }
    
    func navigateTo(_ path: URL) {
        currentPath = path
        navigationStack.append(path)
        loadItems()
    }
    
    func navigateBack() {
        guard navigationStack.count > 1 else { return }
        navigationStack.removeLast()
        currentPath = navigationStack.last!
        loadItems()
    }
    
    func navigateToParent() {
        let parent = currentPath.deletingLastPathComponent()
        guard parent.path != currentPath.path else { return }
        navigateTo(parent)
    }
    
    func navigateInto(_ item: FileItem) {
        guard item.isDirectory else { return }
        navigateTo(item.url)
    }
    
    // MARK: - Data Loading
    
    func loadItems() {
        Task {
            await loadItemsAsync()
        }
    }
    
    func cancelLoad() {
        isLoading = false
    }
    
    private func loadItemsAsync() async {
        isLoading = true
        
        // Move to background thread
        let currentPath = self.currentPath
        let loadedItems = await Task.detached(priority: .userInitiated) {
            var items: [FileItem] = []
            let fileManager = FileManager.default
            
            guard let contents = try? fileManager.contentsOfDirectory(
                at: currentPath,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey, .isHiddenKey],
                options: []
            ) else {
                return items
            }
            
            for url in contents {
                guard let item = await Self.createFileItem(from: url) else { continue }
                items.append(item)
            }
            
            return items
        }.value
        
        items = loadedItems
        applyFilters()
        isLoading = false
    }
    
    private static func createFileItem(from url: URL) async -> FileItem? {
        let fileManager = FileManager.default
        
        guard let resourceValues = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .isDirectoryKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .contentAccessDateKey
        ]) else {
            return nil
        }
        
        let isDirectory = resourceValues.isDirectory ?? false
        let isHidden = resourceValues.isHidden ?? false
        let modifiedDate = resourceValues.contentModificationDate ?? Date()
        let accessedDate = resourceValues.contentAccessDate ?? Date()
        
        // Calculate size
        let size: Int64
        if isDirectory {
            size = await calculateDirectorySize(url)
        } else {
            size = Int64(resourceValues.fileSize ?? 0)
        }
        
        // Determine file type
        let fileType = determineFileType(url: url, isDirectory: isDirectory)
        
        return FileItem(
            url: url,
            name: url.lastPathComponent,
            size: size,
            modifiedDate: modifiedDate,
            accessedDate: accessedDate,
            isDirectory: isDirectory,
            isHidden: isHidden,
            fileType: fileType
        )
    }
    
    private static func calculateDirectorySize(_ directory: URL) async -> Int64 {
        return await Task.detached(priority: .utility) {
            var totalSize: Int64 = 0
            let fileManager = FileManager.default
            
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            
            return totalSize
        }.value
    }
    
    private static func determineFileType(url: URL, isDirectory: Bool) -> FileItemType {
        if isDirectory {
            if url.lastPathComponent.hasSuffix(".app") {
                return .application
            }
            return .folder
        }
        
        let ext = url.pathExtension.lowercased()
        
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "heif", "bmp", "tiff":
            return .image
        case "mov", "mp4", "avi", "mkv", "m4v":
            return .video
        case "mp3", "m4a", "wav", "aiff", "flac":
            return .audio
        case "pdf":
            return .pdf
        case "doc", "docx", "txt", "rtf", "pages":
            return .document
        case "xls", "xlsx", "numbers":
            return .spreadsheet
        case "zip", "rar", "7z", "tar", "gz", "dmg":
            return .archive
        case "app":
            return .application
        default:
            return .file
        }
    }
    
    // MARK: - Filtering
    
    func applyFilters() {
        var filtered = items
        
        // Hidden files filter
        if !showHiddenFiles {
            filtered = filtered.filter { !$0.isHidden }
        }
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // Size filter
        if minSize > 0 {
            filtered = filtered.filter { $0.size >= minSize }
        }
        
        filteredItems = filtered
        applySorting()
    }
    
    // MARK: - Sorting
    
    func applySorting() {
        filteredItems.sort { lhs, rhs in
            // Always put directories first
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            
            let result: Bool
            switch sortBy {
            case .name:
                result = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .size:
                result = lhs.size < rhs.size
            case .modifiedDate:
                result = lhs.modifiedDate < rhs.modifiedDate
            case .type:
                result = lhs.fileType.displayName < rhs.fileType.displayName
            }
            return sortAscending ? result : !result
        }
    }
    
    // MARK: - Selection
    
    func toggleSelection(for item: FileItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isSelected.toggle()
        }
        if let index = filteredItems.firstIndex(where: { $0.id == item.id }) {
            filteredItems[index].isSelected.toggle()
        }
    }
    
    func selectAll() {
        for index in filteredItems.indices {
            filteredItems[index].isSelected = true
        }
        for index in items.indices {
            if filteredItems.contains(where: { $0.id == items[index].id }) {
                items[index].isSelected = true
            }
        }
    }
    
    func deselectAll() {
        for index in items.indices {
            items[index].isSelected = false
        }
        for index in filteredItems.indices {
            filteredItems[index].isSelected = false
        }
    }
    
    // MARK: - Actions
    
    func deleteSelectedItems() async throws {
        let itemsToDelete = selectedItems
        let fileManager = FileManager.default
        
        for item in itemsToDelete {
            try fileManager.removeItem(at: item.url)
        }
        
        // Reload after deletion
        loadItems()
    }
    
    func revealInFinder(_ item: FileItem) {
        NSWorkspace.shared.selectFile(item.url.path, inFileViewerRootedAtPath: item.url.deletingLastPathComponent().path)
    }
}

// MARK: - FileItem Model

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let modifiedDate: Date
    let accessedDate: Date
    let isDirectory: Bool
    let isHidden: Bool
    let fileType: FileItemType
    var isSelected: Bool = false
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedModifiedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedDate)
    }
    
    var icon: String {
        fileType.icon
    }
}

enum FileItemType {
    case folder
    case file
    case image
    case video
    case audio
    case document
    case spreadsheet
    case pdf
    case archive
    case application
    
    var displayName: String {
        switch self {
        case .folder: return "Folder"
        case .file: return "File"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .spreadsheet: return "Spreadsheet"
        case .pdf: return "PDF"
        case .archive: return "Archive"
        case .application: return "Application"
        }
    }
    
    var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .file: return "doc.fill"
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .document: return "doc.text.fill"
        case .spreadsheet: return "tablecells.fill"
        case .pdf: return "doc.richtext.fill"
        case .archive: return "archivebox.fill"
        case .application: return "app.fill"
        }
    }
}
