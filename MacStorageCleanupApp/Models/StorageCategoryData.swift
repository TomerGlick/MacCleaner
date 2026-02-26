import SwiftUI

struct StorageCategoryData: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let totalCapacity: Int64
    let color: Color
    let isDeletable: Bool
    var subcategories: [StorageCategoryData]
    var items: [StorageItemData]
    
    init(name: String, size: Int64, totalCapacity: Int64, color: Color, isDeletable: Bool = false, subcategories: [StorageCategoryData] = [], items: [StorageItemData] = []) {
        self.name = name
        self.size = size
        self.totalCapacity = totalCapacity
        self.color = color
        self.isDeletable = isDeletable
        self.subcategories = subcategories
        self.items = items
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
}
