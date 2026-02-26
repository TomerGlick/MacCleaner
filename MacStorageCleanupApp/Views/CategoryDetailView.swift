import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var viewModel: StorageViewModel
    let category: StorageCategoryData
    @State private var showingFileBrowser = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with back navigation
            HStack {
                Button(action: {
                    viewModel.navigateBack()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Browse Files button - uncomment when FileBrowserView is added to project
                // if isBrowsableCategory {
                //     Button(action: {
                //         showingFileBrowser = true
                //     }) {
                //         HStack(spacing: 4) {
                //             Image(systemName: "folder.badge.gearshape")
                //             Text("Browse Files")
                //         }
                //     }
                //     .buttonStyle(.borderedProminent)
                // }
                
                if viewModel.navigationPath.count > 1 {
                    Button("Show All") {
                        viewModel.navigateToRoot()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 8)
            
            // Category header
            HStack {
                Circle()
                    .fill(category.color)
                    .frame(width: 16, height: 16)
                
                Text(category.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(category.formattedSize)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("\(String(format: "%.1f", category.percentage))% of disk")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Content area
            ScrollView {
                VStack(spacing: 16) {
                    // Subcategories
                    if !category.subcategories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Subcategories")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(category.subcategories) { subcategory in
                                SubcategoryRowView(
                                    subcategory: subcategory,
                                    onSelect: {
                                        viewModel.selectCategory(subcategory)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Individual items
                    if !category.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.subcategories.isEmpty ? "Items" : "Large Items")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(category.items) { item in
                                ItemRowView(item: item)
                            }
                        }
                    }
                    
                    // Empty state
                    if !category.hasDetails {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("No details available")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if category.name == "System" {
                                Text("System files are managed by macOS and cannot be modified.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
                .padding()
            }
        }
        .padding()
        // File browser integration - uncomment when FileBrowserView is added to project
        // .sheet(isPresented: $showingFileBrowser) {
        //     FileBrowserView(startPath: categoryPath)
        //         .frame(minWidth: 900, minHeight: 600)
        // }
    }
    
    // MARK: - Helpers
    
    private var isBrowsableCategory: Bool {
        ["Documents", "Downloads", "Applications", "Caches"].contains(category.name)
    }
    
    private var categoryPath: URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        
        switch category.name {
        case "Documents":
            return homeDir.appendingPathComponent("Documents")
        case "Downloads":
            return homeDir.appendingPathComponent("Downloads")
        case "Applications":
            return URL(fileURLWithPath: "/Applications")
        case "Caches":
            return homeDir.appendingPathComponent("Library/Caches")
        default:
            return nil
        }
    }
}

struct SubcategoryRowView: View {
    let subcategory: StorageCategoryData
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Circle()
                    .fill(subcategory.color)
                    .frame(width: 10, height: 10)
                
                Text(subcategory.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(subcategory.formattedSize)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct ItemRowView: View {
    let item: StorageItemData
    
    var body: some View {
        HStack {
            // Icon based on type
            Image(systemName: iconName)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var iconName: String {
        switch item.type {
        case .application:
            return "app.fill"
        case .directory:
            return "folder.fill"
        case .file:
            return "doc.fill"
        }
    }
    
    private var iconColor: Color {
        switch item.type {
        case .application:
            return .blue
        case .directory:
            return .blue
        case .file:
            return .gray
        }
    }
}

#Preview {
    let vm = StorageViewModel.preview
    let category = vm.categoryData[0]
    
    return CategoryDetailView(viewModel: vm, category: category)
        .frame(width: 600, height: 500)
}
