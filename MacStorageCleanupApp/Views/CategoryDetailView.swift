import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var viewModel: StorageViewModel
    let category: StorageCategoryData
    
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
                
                if viewModel.navigationPath.count > 1 {
                    Button("Show All") {
                        viewModel.navigateToRoot()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 4)

            // Breadcrumb trail
            if viewModel.navigationPath.count > 1 {
                BreadcrumbView(viewModel: viewModel)
            }
            
            // Category header
            HStack {
                Circle()
                    .fill(category.color)
                    .frame(width: 16, height: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if let path = category.path {
                        Text(path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                    }
                }
                
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

            // Inline progress while sub-folder sizes are measured
            if viewModel.isLoadingDetails {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)

                    Text("Measuring folder contents…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Cancel") {
                        viewModel.cancelDetailLoad()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            // Content area
            ScrollView {
                VStack(spacing: 16) {
                    // Sub-folders
                    if !category.subcategories.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Folders")
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
                            Text(category.subcategories.isEmpty ? "Items" : "Files")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            ForEach(category.items) { item in
                                ItemRowView(
                                    item: item,
                                    onSelect: item.type == .file ? nil : {
                                        viewModel.selectItem(item, in: category)
                                    },
                                    onReveal: {
                                        revealInFinder(item.path)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Empty state
                    if !category.hasDetails && !viewModel.isLoadingDetails {
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
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

// MARK: - Breadcrumb

struct BreadcrumbView: View {
    @ObservedObject var viewModel: StorageViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button("All") {
                    viewModel.navigateToRoot()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)

                ForEach(Array(viewModel.navigationPath.enumerated()), id: \.element.id) { index, crumb in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    Button(crumb.name) {
                        viewModel.navigate(toDepth: index)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(index == viewModel.navigationPath.count - 1 ? .primary : .accentColor)
                    .lineLimit(1)
                }
            }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(subcategory.path ?? subcategory.name)
    }
}

struct ItemRowView: View {
    let item: StorageItemData
    var onSelect: (() -> Void)?
    var onReveal: (() -> Void)?
    
    var body: some View {
        Group {
            if let onSelect {
                Button(action: onSelect) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .contextMenu {
            if let onReveal {
                Button("Reveal in Finder", action: onReveal)
            }
        }
    }

    private var rowContent: some View {
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
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if onSelect != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
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
