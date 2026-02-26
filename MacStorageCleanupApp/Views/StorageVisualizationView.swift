import SwiftUI
import Charts

struct StorageVisualizationView: View {
    @ObservedObject var viewModel: StorageViewModel
    @State private var selectedCategoryName: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Storage Breakdown")
                .font(.title2)
                .fontWeight(.semibold)
            
            if viewModel.isLoading {
                ProgressView("Loading storage data...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if #available(macOS 14.0, *) {
                    // Pie chart visualization (macOS 14+)
                    Chart(viewModel.categoryData) { category in
                        SectorMark(
                            angle: .value("Size", category.size),
                            innerRadius: .ratio(0.5),
                            angularInset: 2
                        )
                        .foregroundStyle(category.color)
                        .cornerRadius(4)
                        .opacity(selectedCategoryName == nil || selectedCategoryName == category.name ? 1.0 : 0.5)
                    }
                    .chartLegend(position: .bottom, spacing: 12)
                    .chartAngleSelection(value: $selectedCategoryName)
                    .onChange(of: selectedCategoryName) { oldValue, newValue in
                        if let categoryName = newValue,
                           let category = viewModel.categoryData.first(where: { $0.name == categoryName }) {
                            viewModel.selectCategory(category)
                        }
                    }
                    .frame(height: 350)
                    .padding()
                } else {
                    // Bar chart for macOS 13
                    Chart(viewModel.categoryData) { category in
                        BarMark(
                            x: .value("Size", category.size),
                            y: .value("Category", category.name)
                        )
                        .foregroundStyle(category.color)
                        .cornerRadius(4)
                    }
                    .chartXAxis {
                        AxisMarks(position: .bottom)
                    }
                    .frame(height: 350)
                    .padding()
                }
            }
        }
    }
}

#Preview {
    StorageVisualizationView(viewModel: StorageViewModel.preview)
        .frame(width: 500, height: 500)
}
