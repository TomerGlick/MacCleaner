import SwiftUI
import MacStorageCleanupCore

/// View for uninstalling an application with details and confirmation
struct ApplicationUninstallView: View {
    @StateObject private var viewModel: ApplicationUninstallViewModel
    let onDismiss: () -> Void
    let onUninstallComplete: () -> Void
    
    init(application: Application, onDismiss: @escaping () -> Void, onUninstallComplete: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ApplicationUninstallViewModel(application: application))
        self.onDismiss = onDismiss
        self.onUninstallComplete = onUninstallComplete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if let result = viewModel.uninstallResult {
                uninstallResultView(result: result)
            } else {
                uninstallDetailsView
            }
        }
        .frame(width: 600, height: 500)
        .alert("Confirm Uninstall", isPresented: $viewModel.showConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.cancelConfirmation()
            }
            Button("Uninstall", role: .destructive) {
                Task {
                    await viewModel.performUninstall()
                }
            }
        } message: {
            Text("Are you sure you want to uninstall \(viewModel.application.name)? This action cannot be undone.")
        }
        .task {
            await viewModel.loadAssociatedFiles()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Image(systemName: "app.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.application.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Version \(viewModel.application.version)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    // MARK: - Uninstall Details View
    
    private var uninstallDetailsView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Application details
                    applicationDetailsSection
                    
                    Divider()
                    
                    // Associated files
                    associatedFilesSection
                    
                    Divider()
                    
                    // Space to be freed
                    spaceSection
                    
                    // Warning if running
                    if viewModel.application.isRunning {
                        runningWarningSection
                    }
                    
                    // Error message
                    if let errorMessage = viewModel.errorMessage {
                        errorSection(message: errorMessage)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Spacer()
                
                Button(action: {
                    viewModel.requestUninstall()
                }) {
                    HStack {
                        if viewModel.isUninstalling {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "trash")
                        }
                        Text(viewModel.isUninstalling ? "Uninstalling..." : "Uninstall")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!viewModel.canUninstall)
            }
            .padding()
        }
    }
    
    // MARK: - Application Details Section
    
    private var applicationDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Details")
                .font(.headline)
            
            detailRow(label: "Location", value: viewModel.application.bundleURL.path)
            detailRow(label: "Bundle Identifier", value: viewModel.application.bundleIdentifier)
            detailRow(
                label: "Size",
                value: ByteCountFormatter.string(fromByteCount: viewModel.application.size, countStyle: .file)
            )
            
            if let lastUsed = viewModel.application.lastUsedDate {
                detailRow(label: "Last Used", value: formatDate(lastUsed))
            }
            
            if viewModel.application.isRunning {
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Running")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Associated Files Section
    
    private var associatedFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Associated Files")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Remove associated files", isOn: $viewModel.removeAssociatedFiles)
                    .toggleStyle(.switch)
            }
            
            if viewModel.isLoadingAssociatedFiles {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching for associated files...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.associatedFiles.isEmpty {
                Text("No associated files found")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(viewModel.associatedFiles.count) associated files found")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    // Show first few files
                    ForEach(viewModel.associatedFiles.prefix(5), id: \.url) { file in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundColor(.secondary)
                                .frame(width: 16)
                            Text(file.url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    
                    if viewModel.associatedFiles.count > 5 {
                        Text("and \(viewModel.associatedFiles.count - 5) more...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 20)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    // MARK: - Space Section
    
    private var spaceSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total Space to Free")
                    .font(.headline)
                Text("This includes the application and all selected associated files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(viewModel.formattedTotalSpace)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Running Warning Section
    
    private var runningWarningSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Application is Running")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("Please quit \(viewModel.application.name) before uninstalling.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Error Section
    
    private func errorSection(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundColor(.red)
            
            Text(message)
                .font(.body)
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Uninstall Result View
    
    private func uninstallResultView(result: UninstallResult) -> some View {
        VStack(spacing: 24) {
            Spacer()
            
            if result.applicationRemoved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                
                Text("Uninstall Complete")
                    .font(.title)
                    .fontWeight(.semibold)
                
                VStack(spacing: 12) {
                    resultRow(
                        label: "Application Removed",
                        value: result.applicationRemoved ? "Yes" : "No",
                        color: result.applicationRemoved ? .green : .red
                    )
                    
                    if viewModel.removeAssociatedFiles {
                        resultRow(
                            label: "Associated Files Removed",
                            value: "\(result.associatedFilesRemoved)",
                            color: .primary
                        )
                    }
                    
                    resultRow(
                        label: "Space Freed",
                        value: ByteCountFormatter.string(fromByteCount: result.totalSpaceFreed, countStyle: .file),
                        color: .blue
                    )
                    
                    if !result.errors.isEmpty {
                        resultRow(
                            label: "Errors",
                            value: "\(result.errors.count)",
                            color: .orange
                        )
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)
                
                Text("Uninstall Failed")
                    .font(.title)
                    .fontWeight(.semibold)
                
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            Spacer()
            
            Button(action: {
                if result.applicationRemoved {
                    onUninstallComplete()
                }
                onDismiss()
            }) {
                Text("Done")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }
    
    // MARK: - Helper Views
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }
    
    private func resultRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    ApplicationUninstallView(
        application: Application(
            bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
            name: "Xcode",
            version: "15.0",
            bundleIdentifier: "com.apple.dt.Xcode",
            size: 15_000_000_000,
            lastUsedDate: Date().addingTimeInterval(-86400 * 2),
            isRunning: false
        ),
        onDismiss: {},
        onUninstallComplete: {}
    )
}

#Preview("Running App") {
    ApplicationUninstallView(
        application: Application(
            bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
            name: "Safari",
            version: "17.0",
            bundleIdentifier: "com.apple.Safari",
            size: 250_000_000,
            lastUsedDate: Date(),
            isRunning: true
        ),
        onDismiss: {},
        onUninstallComplete: {}
    )
}
