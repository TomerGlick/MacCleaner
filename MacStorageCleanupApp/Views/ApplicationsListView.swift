import SwiftUI
import MacStorageCleanupCore

/// View for displaying all discovered applications with sorting capabilities
struct ApplicationsListView: View {
    @StateObject private var viewModel = ApplicationsViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with sort controls
            headerView
            
            Divider()
            
            // Content
            if viewModel.isLoading {
                loadingView
            } else if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            } else if viewModel.applications.isEmpty {
                emptyStateView
            } else {
                applicationsList
            }
        }
        .sheet(isPresented: $viewModel.showUninstallView) {
            if let application = viewModel.selectedApplication {
                ApplicationUninstallView(
                    application: application,
                    onDismiss: {
                        viewModel.dismissUninstallView()
                    },
                    onUninstallComplete: {
                        viewModel.refreshAfterUninstall()
                    }
                )
            }
        }
        .task {
            await viewModel.loadApplications()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Installed Applications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Sort controls
            Menu {
                Button(action: { viewModel.sortOrder = .name }) {
                    Label("Name", systemImage: viewModel.sortOrder == .name ? "checkmark" : "")
                }
                Button(action: { viewModel.sortOrder = .size }) {
                    Label("Size", systemImage: viewModel.sortOrder == .size ? "checkmark" : "")
                }
                Button(action: { viewModel.sortOrder = .lastUsed }) {
                    Label("Last Used", systemImage: viewModel.sortOrder == .lastUsed ? "checkmark" : "")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sort by:")
                    Text(sortOrderLabel)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .menuStyle(.borderlessButton)
            
            Button(action: {
                Task {
                    await viewModel.loadApplications()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh applications list")
        }
        .padding()
    }
    
    private var sortOrderLabel: String {
        switch viewModel.sortOrder {
        case .name: return "Name"
        case .size: return "Size"
        case .lastUsed: return "Last Used"
        }
    }
    
    // MARK: - Applications List
    
    private var applicationsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.sortedApplications, id: \.bundleIdentifier) { application in
                    ApplicationRow(application: application)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectApplication(application)
                        }
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Discovering applications...")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Error Loading Applications")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                Task {
                    await viewModel.loadApplications()
                }
            }) {
                Text("Try Again")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "app.dashed")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Applications Found")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("No applications were found in /Applications or ~/Applications")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Application Row

struct ApplicationRow: View {
    let application: Application
    
    var body: some View {
        HStack(spacing: 16) {
            // App icon placeholder
            Image(systemName: "app.fill")
                .font(.system(size: 32))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
            
            // App info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(application.name)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    if application.isRunning {
                        Text("Running")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 12) {
                    Text("Version \(application.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let lastUsed = application.lastUsedDate {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Last used \(formatRelativeDate(lastUsed))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Size
            Text(ByteCountFormatter.string(fromByteCount: application.size, countStyle: .file))
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(.primary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Preview

#Preview {
    ApplicationsListView()
        .frame(width: 800, height: 600)
}

#Preview("With Data") {
    let view = ApplicationsListView()
    return view
        .frame(width: 800, height: 600)
}
