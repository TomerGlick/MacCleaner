import SwiftUI

struct MainWindowView: View {
    @StateObject private var coordinator = ApplicationCoordinator.shared
    @StateObject private var viewModel = StorageViewModel()
    @State private var showingScanView = false
    @State private var showingPreferences = false
    @State private var showingApplications = false
    @State private var showingBackups = false
    @State private var showingFileBrowser = false
    @State private var selectedTab: MainTab = .storage
    
    enum MainTab {
        case storage
        case files
        case cleanup
        case applications
        case backups
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with app title
            VStack(spacing: 0) {
                // App title header
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Mac Storage Cleanup")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Sidebar list
                List(selection: $selectedTab) {
                    Section("Overview") {
                        Label("Storage", systemImage: "internaldrive")
                            .tag(MainTab.storage)
                        
                        Label("Files", systemImage: "folder")
                            .tag(MainTab.files)
                    }
                    
                    Section("Cleanup") {
                        Label("Cleanup Candidates", systemImage: "trash")
                            .tag(MainTab.cleanup)
                    }
                    
                    Section("Management") {
                        Label("Applications", systemImage: "app")
                            .tag(MainTab.applications)
                        
                        Label("Backups", systemImage: "archivebox")
                            .tag(MainTab.backups)
                    }
                }
                
                Spacer()
                
                Divider()
                
                // Settings button at bottom
                Button(action: {
                    showingPreferences = true
                }) {
                    Label("Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding()
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            // Main content based on selected tab
            Group {
                switch selectedTab {
                case .storage:
                    storageView
                case .files:
                    FileBrowserView()
                case .cleanup:
                    cleanupView
                case .applications:
                    ApplicationsListView()
                case .backups:
                    BackupManagementView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        showingScanView = true
                    }) {
                        Label("Scan Storage", systemImage: "magnifyingglass")
                    }
                }
            }
        }
        .sheet(isPresented: $showingScanView) {
            ScanView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingPreferences) {
            PreferencesWindow()
        }
        .onChange(of: coordinator.globalErrors) { errors in
            if let firstError = errors.first {
                // Show alert for first error
                showErrorAlert(firstError)
            }
        }
    }
    
    private func showErrorAlert(_ error: AppError) {
        // This would typically use a custom alert system
        // For now, we'll just dismiss the error
        coordinator.dismissError(error)
    }
    
    // MARK: - Storage View
    
    private var storageView: some View {
        VStack(spacing: 0) {
            // Header with storage summary
            StorageHeaderView(viewModel: viewModel)
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Main content area
            if viewModel.categoryData.isEmpty && !viewModel.isLoading {
                // Empty state with scan button
                VStack(spacing: 20) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Storage Analysis")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Scan your Mac to see storage breakdown")
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        Task {
                            await viewModel.loadStorageData()
                        }
                    }) {
                        Label("Scan Storage", systemImage: "magnifyingglass")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isLoading {
                // Loading state with cancel button
                VStack(spacing: 20) {
                    ProgressView("Analyzing storage...")
                        .progressViewStyle(.circular)
                    
                    Button("Cancel") {
                        viewModel.cancelScan()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Storage visualization
                    StorageVisualizationView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                        .padding()
                    
                    Divider()
                    
                    // Category breakdown or detail view
                    if let selectedCategory = viewModel.selectedCategory {
                        CategoryDetailView(viewModel: viewModel, category: selectedCategory)
                            .frame(width: 600)
                            .transition(.move(edge: .trailing))
                    } else {
                        CategoryBreakdownView(viewModel: viewModel)
                            .frame(width: 300)
                            .padding()
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            
            Divider()
            
            // Bottom disk space bar
            DiskSpaceBar(viewModel: viewModel)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.selectedCategory?.id)
    }
    
    // MARK: - Cleanup View
    
    private var cleanupView: some View {
        CleanupCandidatesView(category: .caches, storageViewModel: viewModel)
    }
}

#Preview {
    MainWindowView()
        .frame(width: 1000, height: 700)
}
