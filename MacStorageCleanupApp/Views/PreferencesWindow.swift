import SwiftUI
import MacStorageCleanupCore

/// Preferences window for configuring application settings
struct PreferencesWindow: View {
    @StateObject private var viewModel = PreferencesViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TabView {
            // Backup preferences
            backupPreferencesTab
                .tabItem {
                    Label("Backup", systemImage: "archivebox")
                }
            
            // Cleanup preferences
            cleanupPreferencesTab
                .tabItem {
                    Label("Cleanup", systemImage: "trash")
                }
            
            // Threshold preferences
            thresholdPreferencesTab
                .tabItem {
                    Label("Thresholds", systemImage: "slider.horizontal.3")
                }
            
            // Scheduled cleanup preferences
            scheduledCleanupTab
                .tabItem {
                    Label("Scheduled", systemImage: "calendar")
                }
            
            // About tab
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 550)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.savePreferences()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Backup Preferences Tab
    
    private var backupPreferencesTab: some View {
        Form {
            Section {
                Toggle("Create backups before deletion by default", isOn: $viewModel.createBackupsByDefault)
                    .help("When enabled, files will be backed up before deletion operations")
            } header: {
                Text("Backup Settings")
                    .font(.headline)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backup Location")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(viewModel.backupLocation)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        
                        Spacer()
                        
                        Button("Change...") {
                            viewModel.selectBackupLocation()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Reveal") {
                            viewModel.revealBackupLocation()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text("Storage")
                    .font(.headline)
            }
            
            Section {
                Text("Backups are compressed archives that allow you to restore files if needed. Old backups can be managed from the Backup Management view.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Cleanup Preferences Tab
    
    private var cleanupPreferencesTab: some View {
        Form {
            Section {
                Toggle("Move files to Trash instead of permanent deletion", isOn: $viewModel.moveToTrashByDefault)
                    .help("When enabled, files will be moved to Trash where they can be recovered")
            } header: {
                Text("Deletion Behavior")
                    .font(.headline)
            }
            
            Section {
                Toggle("Debug Mode (simulate deletions)", isOn: $viewModel.debugMode)
                    .help("When enabled, cleanup operations will be simulated without actually deleting files")
            } header: {
                Text("Developer")
                    .font(.headline)
            }
            
            Section {
                Text("Moving files to Trash is safer as it allows recovery. Permanent deletion immediately removes files and cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Threshold Preferences Tab
    
    private var thresholdPreferencesTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Old file threshold:")
                        Spacer()
                        TextField("Days", value: $viewModel.oldFileThresholdDays, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        Text("days")
                    }
                    
                    if let warning = viewModel.oldFileThresholdWarning {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(warning)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Text("Files not accessed for this many days will be flagged as old files. Valid range: 30-1095 days.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Old Files")
                    .font(.headline)
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Large file threshold:")
                        Spacer()
                        TextField("MB", value: $viewModel.largeFileSizeThresholdMB, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        Text("MB")
                    }
                    
                    Text("Files larger than this size will be flagged as large files.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Large Files")
                    .font(.headline)
            }
            
            Section {
                Button("Reset to Defaults") {
                    viewModel.oldFileThresholdDays = 365
                    viewModel.largeFileSizeThresholdMB = 100
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - Scheduled Cleanup Tab
    
    private var scheduledCleanupTab: some View {
        Form {
            Section {
                Toggle("Enable scheduled cleanup", isOn: $viewModel.enableScheduledCleanup)
                    .help("Automatically run cleanup operations at regular intervals")
            } header: {
                Text("Scheduled Cleanup")
                    .font(.headline)
            }
            
            if viewModel.enableScheduledCleanup {
                Section {
                    Picker("Cleanup interval:", selection: $viewModel.scheduledCleanupInterval) {
                        Text("Daily").tag(CleanupInterval.daily)
                        Text("Weekly").tag(CleanupInterval.weekly)
                        Text("Monthly").tag(CleanupInterval.monthly)
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Text("Frequency")
                        .font(.headline)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select categories to include in scheduled cleanup:")
                            .font(.subheadline)
                        
                        ForEach(Array(UserPreferences.safeCategories).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { category in
                            Toggle(category.displayName, isOn: Binding(
                                get: { viewModel.scheduledCategories.contains(category) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.scheduledCategories.insert(category)
                                    } else {
                                        viewModel.scheduledCategories.remove(category)
                                    }
                                }
                            ))
                        }
                        
                        if let warning = viewModel.scheduledCategoriesWarning {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text(warning)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 4)
                        }
                    }
                } header: {
                    Text("Categories")
                        .font(.headline)
                }
                
                Section {
                    Text("Only safe categories (caches and temporary files) can be included in scheduled cleanup. Other categories require manual confirmation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
    
    // MARK: - About Tab
    
    private var aboutTab: some View {
        VStack(spacing: 24) {
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Mac Storage Cleanup")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Version \(appVersion)")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("A powerful tool to clean up your Mac and free up storage space.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                
                Text("Features:")
                    .font(.headline)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    bulletPoint("Clean system and application caches")
                    bulletPoint("Remove temporary files and logs")
                    bulletPoint("Find and manage large files")
                    bulletPoint("Scheduled automatic cleanup")
                    bulletPoint("Safe file deletion with backup support")
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
            
            Text("© 2026 Mac Storage Cleanup")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.blue)
            Text(text)
                .font(.body)
        }
    }
    
    private var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return "\(version) (\(build))"
        }
        return "1.0.0"
    }
}

// MARK: - Preview

#Preview {
    PreferencesWindow()
}
