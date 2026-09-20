import SwiftUI

struct StorageCategoryData: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let totalCapacity: Int64
    let color: Color
    let isDeletable: Bool
    /// Filesystem location backing this category, when it maps to a real directory.
    /// Present for every drillable node so sub-folders can be expanded recursively.
    let path: String?
    var subcategories: [StorageCategoryData]
    var items: [StorageItemData]

    init(
        name: String,
        size: Int64,
        totalCapacity: Int64,
        color: Color,
        isDeletable: Bool = false,
        path: String? = nil,
        subcategories: [StorageCategoryData] = [],
        items: [StorageItemData] = []
    ) {
        self.name = name
        self.size = size
        self.totalCapacity = totalCapacity
        self.color = color
        self.isDeletable = isDeletable
        self.path = path
        self.subcategories = subcategories
        self.items = items
    }

    init(item: StorageItemData, totalCapacity: Int64, color: Color, isDeletable: Bool = false) {
        self.init(
            name: item.name,
            size: item.size,
            totalCapacity: totalCapacity,
            color: color,
            isDeletable: isDeletable,
            path: item.path
        )
    }
    
    var percentage: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(size) / Double(totalCapacity) * 100
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var hasDetails: Bool {
        !subcategories.isEmpty || !items.isEmpty
    }

    /// Whether this node can be expanded further into sub-folders.
    var isDrillable: Bool {
        path != nil || hasDetails
    }
}
