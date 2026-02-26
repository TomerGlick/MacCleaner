import SwiftUI

struct CategoryBreakdownView: View {
    @ObservedObject var viewModel: StorageViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Categories")
                .font(.title3)
                .fontWeight(.semibold)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(viewModel.categoryData) { category in
                            CategoryRowView(category: category) {
                                viewModel.selectCategory(category)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CategoryRowView: View {
    let category: StorageCategoryData
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Category color indicator
                    Circle()
                        .fill(category.color)
                        .frame(width: 12, height: 12)
                    
                    Text(category.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if category.isDeletable {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .help("Can be cleaned")
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text(category.formattedSize)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(String(format: "%.1f", category.percentage))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)
                            .cornerRadius(2)
                        
                        Rectangle()
                            .fill(category.color)
                            .frame(width: geometry.size.width * (category.percentage / 100), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CategoryBreakdownView(viewModel: StorageViewModel.preview)
        .frame(width: 300, height: 600)
        .padding()
}
