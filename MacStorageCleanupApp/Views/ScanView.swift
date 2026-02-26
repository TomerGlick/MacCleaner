import SwiftUI
import MacStorageCleanupCore

/// View for initiating scans and displaying real-time scan progress
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: StorageViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isScanning {
                // Scanning in progress
                scanProgressView
            } else if viewModel.lastScanResult != nil {
                // Scan completed
                scanResultsView
            } else {
                // Initial state - ready to scan
                scanInitiationView
            }
        }
        .padding(30)
        .frame(maxWidth: 500)
    }
    
    // MARK: - Scan Initiation View
    
    private var scanInitiationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Scan Your Mac")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Analyze your storage to find files you can clean up")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .padding(.vertical, 8)
            
            // Scan configuration options
            VStack(alignment: .leading, spacing: 12) {
                Text("Scan Options")
                    .font(.headline)
                
                Toggle("Include system caches", isOn: $viewModel.scanIncludeSystemCaches)
                Toggle("Include application caches", isOn: $viewModel.scanIncludeAppCaches)
                Toggle("Include developer tool caches", isOn: $viewModel.scanIncludeDeveloperCaches)
                Toggle("Include AI agent caches", isOn: $viewModel.scanIncludeAIAgentCaches)
                Toggle("Include temporary files", isOn: $viewModel.scanIncludeTempFiles)
                Toggle("Include large files (>100MB)", isOn: $viewModel.scanIncludeLargeFiles)
                Toggle("Include old files (>1 year)", isOn: $viewModel.scanIncludeOldFiles)
                Toggle("Include log files", isOn: $viewModel.scanIncludeLogFiles)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Button(action: {
                Task {
                    await viewModel.startScan()
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Scan")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Scan Progress View
    
    private var scanProgressView: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Scanning...")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Progress information
            VStack(spacing: 16) {
                // Progress bar
                ProgressView(value: viewModel.scanProgress.percentComplete, total: 1.0)
                    .progressViewStyle(.linear)
                
                // Percentage
                Text("\(Int(viewModel.scanProgress.percentComplete * 100))%")
                    .font(.title3)
                    .fontWeight(.medium)
                    .monospacedDigit()
                
                // Current directory
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Directory:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.scanProgress.currentPath)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Files scanned count
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundColor(.secondary)
                    Text("\(viewModel.scanProgress.filesScanned) files scanned")
                        .font(.body)
                        .monospacedDigit()
                }
            }
            
            Button(action: {
                viewModel.cancelScan()
                dismiss()
            }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Cancel Scan")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
    
    // MARK: - Scan Results View
    
    private var scanResultsView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Scan Complete")
                .font(.title2)
                .fontWeight(.semibold)
            
            if let result = viewModel.lastScanResult {
                VStack(spacing: 16) {
                    // Summary statistics
                    VStack(spacing: 12) {
                        resultRow(
                            icon: "doc.text",
                            label: "Files Scanned",
                            value: "\(result.filesScanned)"
                        )
                        
                        resultRow(
                            icon: "clock",
                            label: "Duration",
                            value: formatDuration(result.duration)
                        )
                        
                        if result.errorCount > 0 {
                            resultRow(
                                icon: "exclamationmark.triangle",
                                label: "Errors",
                                value: "\(result.errorCount)",
                                color: .orange
                            )
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Category breakdown
                    if !result.categorySummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Found Items by Category")
                                .font(.headline)
                            
                            ForEach(result.categorySummary.sorted(by: { $0.value.size > $1.value.size }), id: \.key) { category, summary in
                                HStack {
                                    Text(category.displayName)
                                        .font(.body)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(summary.count) items")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(ByteCountFormatter.string(fromByteCount: summary.size, countStyle: .file))
                                            .font(.body)
                                            .fontWeight(.medium)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    Task {
                        await viewModel.startScan()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Scan Again")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: {
                    viewModel.dismissScanResults()
                    dismiss()
                }) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func resultRow(icon: String, label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(color)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - CleanupCategory Extension

extension CleanupCategory {
    var displayName: String {
        switch self {
        case .systemCaches:
            return "System Caches"
        case .applicationCaches:
            return "Application Caches"
        case .browserCaches:
            return "Browser Caches"
        case .temporaryFiles:
            return "Temporary Files"
        case .largeFiles:
            return "Large Files"
        case .oldFiles:
            return "Old Files"
        case .logFiles:
            return "Log Files"
        case .downloads:
            return "Downloads"
        case .duplicates:
            return "Duplicates"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        // Initial state
        ScanView(viewModel: {
            let vm = StorageViewModel.preview
            return vm
        }())
        .frame(width: 500, height: 600)
    }
}
