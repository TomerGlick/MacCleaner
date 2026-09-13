import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class PreferencesViewModel: ObservableObject {
    @Published var preferences: UserPreferences
    
    // General preferences
    @Published var showMenuBarIcon: Bool
    @Published var launchAtLogin: Bool
    
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
    
    private let preferencesService: PreferencesService
    
    init(preferencesService: PreferencesService = .shared) {
        self.preferencesService = preferencesService
        let loadedPreferences = preferencesService.loadPreferences()
        
        // Initialize all properties first
        self.preferences = loadedPreferences
        self.showMenuBarIcon = loadedPreferences.showMenuBarIcon
        self.launchAtLogin = loadedPreferences.launchAtLogin
        self.createBackupsByDefault = loadedPreferences.createBackupsByDefault
        self.backupLocation = PreferencesViewModel.defaultBackupLocation()
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
        preferences.showMenuBarIcon = showMenuBarIcon
        preferences.launchAtLogin = launchAtLogin
        preferences.createBackupsByDefault = createBackupsByDefault
        preferences.moveToTrashByDefault = moveToTrashByDefault
        preferences.debugMode = debugMode
        preferences.oldFileThresholdDays = clampedOldFileThreshold
        preferences.largeFileSizeThresholdMB = largeFileSizeThresholdMB
        preferences.enableScheduledCleanup = enableScheduledCleanup
        preferences.scheduledCleanupInterval = scheduledCleanupInterval
        preferences.scheduledCategories = validatedScheduledCategories
        preferences = preferencesService.validatePreferences(preferences)
        
        // Keep published properties aligned with any validation/clamping.
        showMenuBarIcon = preferences.showMenuBarIcon
        launchAtLogin = preferences.launchAtLogin
        oldFileThresholdDays = preferences.oldFileThresholdDays
        scheduledCategories = preferences.scheduledCategories

        preferencesService.savePreferences(preferences)
        
        // Update menu bar visibility
        if showMenuBarIcon {
            MenuBarManager.shared.setupMenuBar()
        } else {
            MenuBarManager.shared.removeMenuBar()
        }
    }
    
    func resetToDefaults() {
        preferencesService.resetToDefaults()
        preferences = preferencesService.loadPreferences()
        
        // Update published properties
        showMenuBarIcon = preferences.showMenuBarIcon
        launchAtLogin = preferences.launchAtLogin
        createBackupsByDefault = preferences.createBackupsByDefault
        backupLocation = getBackupLocation()
        moveToTrashByDefault = preferences.moveToTrashByDefault
        debugMode = preferences.debugMode
        oldFileThresholdDays = preferences.oldFileThresholdDays
        largeFileSizeThresholdMB = preferences.largeFileSizeThresholdMB
        enableScheduledCleanup = preferences.enableScheduledCleanup
        scheduledCleanupInterval = preferences.scheduledCleanupInterval
        scheduledCategories = preferences.scheduledCategories

        if showMenuBarIcon {
            MenuBarManager.shared.setupMenuBar()
        } else {
            MenuBarManager.shared.removeMenuBar()
        }
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
        Self.defaultBackupLocation()
    }

    private static func defaultBackupLocation() -> String {
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
