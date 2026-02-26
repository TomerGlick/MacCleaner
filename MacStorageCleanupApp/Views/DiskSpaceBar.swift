import SwiftUI

struct DiskSpaceBar: View {
    @ObservedObject var viewModel: StorageViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Disk icon
            Image(systemName: "internaldrive.fill")
                .foregroundColor(.secondary)
            
            // Disk space bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                    
                    // Used space
                    RoundedRectangle(cornerRadius: 4)
                        .fill(usedSpaceColor)
                        .frame(width: geometry.size.width * usedPercentage)
                }
            }
            .frame(height: 8)
            
            // Text info
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(viewModel.formattedAvailableSpace) available")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("\(viewModel.formattedUsedSpace) of \(viewModel.formattedTotalCapacity) used")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var usedPercentage: CGFloat {
        guard viewModel.totalCapacity > 0 else { return 0 }
        return CGFloat(viewModel.usedSpace) / CGFloat(viewModel.totalCapacity)
    }
    
    private var usedSpaceColor: Color {
        let percentage = viewModel.usedPercentage
        if percentage > 90 {
            return .red
        } else if percentage > 75 {
            return .orange
        } else {
            return .blue
        }
    }
}
