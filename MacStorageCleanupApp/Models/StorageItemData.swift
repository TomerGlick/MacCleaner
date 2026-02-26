import Foundation

/// Represents an individual file or directory item within a storage category
struct StorageItemData: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let type: ItemType
    
    enum ItemType {
        case file
        case directory
        case application
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
