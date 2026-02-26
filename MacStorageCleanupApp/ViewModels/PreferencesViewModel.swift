import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class PreferencesViewModel: ObservableObject {
    @Published var preferences: UserPreferences
    
    // Backup preferences
    @Published var createBackupsByDefault: Bool
    @Published var backupLocation: String
    
    // Cleanup preferences
    @Published var moveToTrashByDefault: Bool
    @Published var debugMode: Bool
    
    // Threshold preferences
    @Published var oldFileThresholdDays: Int
    @Published var largeFileSizeThresholdMB: Int
    
    // Scheduled cleanup preferences
    @Published var enableScheduledCleanup: Bool
    @Published var scheduledCleanupInterval: CleanupInterval
    @Published var scheduledCategories: Set<CleanupCategory>
    
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "MacStorageCleanup.UserPreferences"
    
    init() {
        // Load preferences from UserDefaults or use defaults
        let loadedPreferences: UserPreferences
        if let data = userDefaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            loadedPreferences = decoded
        } else {
            loadedPreferences = .default
        }
        
        // Initialize all properties first
        self.preferences = loadedPreferences
        self.createBackupsByDefault = loadedPreferences.createBackupsByDefault
        self.backupLocation = NSHomeDirectory() + "/Library/Application Support/MacStorageCleanup/Backups"
        self.moveToTrashByDefault = loadedPreferences.moveToTrashByDefault
        self.debugMode = loadedPreferences.debugMode
        self.oldFileThresholdDays = loadedPreferences.oldFileThresholdDays
        self.largeFileSizeThresholdMB = loadedPreferences.largeFileSizeThresholdMB
        self.enableScheduledCleanup = loadedPreferences.enableScheduledCleanup
        self.scheduledCleanupInterval = loadedPreferences.scheduledCleanupInterval
        self.scheduledCategories = loadedPreferences.scheduledCategories
    }
    
    func savePreferences() {
        // Update preferences from published properties
        preferences.createBackupsByDefault = createBackupsByDefault
        preferences.moveToTrashByDefault = moveToTrashByDefault
        preferences.debugMode = debugMode
        preferences.oldFileThresholdDays = clampedOldFileThreshold
        preferences.largeFileSizeThresholdMB = largeFileSizeThresholdMB
        preferences.enableScheduledCleanup = enableScheduledCleanup
        preferences.scheduledCleanupInterval = scheduledCleanupInterval
        preferences.scheduledCategories = validatedScheduledCategories
        
        // Save to UserDefaults
        if let encoded = try? JSONEncoder().encode(preferences) {
            userDefaults.set(encoded, forKey: preferencesKey)
        }
        
        // Also save debug mode separately for CleanupEngine access
        userDefaults.set(debugMode, forKey: "debugMode")
    }
    
    func resetToDefaults() {
        preferences = .default
        
        // Update published properties
        createBackupsByDefault = preferences.createBackupsByDefault
        backupLocation = getBackupLocation()
        moveToTrashByDefault = preferences.moveToTrashByDefault
        debugMode = preferences.debugMode
        oldFileThresholdDays = preferences.oldFileThresholdDays
        largeFileSizeThresholdMB = preferences.largeFileSizeThresholdMB
        enableScheduledCleanup = preferences.enableScheduledCleanup
        scheduledCleanupInterval = preferences.scheduledCleanupInterval
        scheduledCategories = preferences.scheduledCategories
        
        savePreferences()
    }
    
    // MARK: - Computed Properties
    
    var clampedOldFileThreshold: Int {
        min(max(oldFileThresholdDays, 30), 1095)
    }
    
    var validatedScheduledCategories: Set<CleanupCategory> {
        scheduledCategories.intersection(UserPreferences.safeCategories)
    }
    
    var oldFileThresholdWarning: String? {
        if oldFileThresholdDays < 30 {
            return "Minimum threshold is 30 days"
        } else if oldFileThresholdDays > 1095 {
            return "Maximum threshold is 1095 days (3 years)"
        }
        return nil
    }
    
    var scheduledCategoriesWarning: String? {
        let unsafeCategories = scheduledCategories.subtracting(UserPreferences.safeCategories)
        if !unsafeCategories.isEmpty {
            return "Some selected categories are not safe for automatic cleanup and will be excluded"
        }
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func getBackupLocation() -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let backupDir = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("MacStorageCleanup")
            .appendingPathComponent("Backups")
        return backupDir.path
    }
    
    func selectBackupLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select backup location"
        
        if panel.runModal() == .OK, let url = panel.url {
            backupLocation = url.path
        }
    }
    
    func revealBackupLocation() {
        let url = URL(fileURLWithPath: backupLocation)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
