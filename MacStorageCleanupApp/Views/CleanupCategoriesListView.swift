import SwiftUI

/// View that displays all cleanup categories and allows navigation to detailed cleanup candidate views
struct CleanupCategoriesListView: View {
    @State private var selectedCategory: CleanupCandidateData.CleanupCategoryType?
    @State private var showingCleanupView = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cleanup Categories")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Category list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(CleanupCandidateData.CleanupCategoryType.allCases, id: \.self) { category in
                        CleanupCategoryRowView(category: category) {
                            selectedCategory = category
                            showingCleanupView = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCleanupView) {
            if let category = selectedCategory {
                CleanupCandidatesView(category: category)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
    }
}

struct CleanupCategoryRowView: View {
    let category: CleanupCandidateData.CleanupCategoryType
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)
                
                // Category info
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(.headline)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .buttonStyle(.plain)
    }
    
    private var iconName: String {
        switch category {
        case .caches:
            return "folder.fill"
        case .temporaryFiles:
            return "clock.fill"
        case .largeFiles:
            return "doc.fill.badge.ellipsis"
        case .oldFiles:
            return "calendar.badge.clock"
        case .logs:
            return "doc.text.fill"
        case .downloads:
            return "arrow.down.circle.fill"
        case .duplicates:
            return "doc.on.doc.fill"
        }
    }
}

#Preview {
    CleanupCategoriesListView()
        .frame(width: 600, height: 500)
}
