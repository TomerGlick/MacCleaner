import SwiftUI

struct StorageCategoryData: Identifiable {
    let id = UUID()
    let name: String
    let size: Int64
    let totalCapacity: Int64
    let color: Color
    var subcategories: [StorageCategoryData] = []
    var items: [StorageItemData] = []
    
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
