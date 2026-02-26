import SwiftUI

struct StorageHeaderView: View {
    @ObservedObject var viewModel: StorageViewModel
    
    var body: some View {
        HStack(spacing: 40) {
            // Total Capacity
            StorageStatView(
                title: "Total Capacity",
                value: viewModel.formattedTotalCapacity,
                color: .secondary
            )
            
            // Used Space
            StorageStatView(
                title: "Used Space",
                value: viewModel.formattedUsedSpace,
                percentage: viewModel.usedPercentage,
                color: .blue
            )
            
            // Available Space
            StorageStatView(
                title: "Available Space",
                value: viewModel.formattedAvailableSpace,
                percentage: viewModel.availablePercentage,
                color: .green
            )
            
            Spacer()
        }
    }
}

struct StorageStatView: View {
    let title: String
    let value: String
    var percentage: Double?
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                
                if let percentage = percentage {
                    Text("(\(String(format: "%.1f", percentage))%)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

#Preview {
    StorageHeaderView(viewModel: StorageViewModel.preview)
        .padding()
        .frame(width: 800)
}
