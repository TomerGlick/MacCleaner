import Foundation
import MacStorageCleanupCore

/// Service for managing user preferences persistence
class PreferencesService {
    static let shared = PreferencesService()
    
    private let store: PreferencesStore
    
    private init(store: PreferencesStore = UserDefaultsPreferencesStore()) {
        self.store = store
    }
    
    // MARK: - Load Preferences
    
    /// Loads user preferences from UserDefaults
    /// - Returns: Loaded preferences or default preferences if none exist
    func loadPreferences() -> UserPreferences {
        if let loaded = try? store.load() {
            return validatePreferences(loaded)
        }

        return .default
    }
    
    // MARK: - Save Preferences
    
    /// Saves user preferences to UserDefaults
    /// - Parameter preferences: The preferences to save
    func savePreferences(_ preferences: UserPreferences) {
        try? store.save(validatePreferences(preferences))
    }
    
    // MARK: - Reset Preferences
    
    /// Resets preferences to default values
    func resetToDefaults() {
        try? store.reset()
    }
    
    // MARK: - Individual Preference Updates
    
    /// Updates a specific preference value
    /// - Parameters:
    ///   - keyPath: The key path to the preference property
    ///   - value: The new value
    func updatePreference<T>(_ keyPath: WritableKeyPath<UserPreferences, T>, value: T) {
        var preferences = loadPreferences()
        preferences[keyPath: keyPath] = value
        savePreferences(preferences)
    }
    
    // MARK: - Preference Getters
    
    var enableScheduledCleanup: Bool {
        get { loadPreferences().enableScheduledCleanup }
        set { updatePreference(\.enableScheduledCleanup, value: newValue) }
    }
    
    var scheduledCleanupInterval: CleanupInterval {
        get { loadPreferences().scheduledCleanupInterval }
        set { updatePreference(\.scheduledCleanupInterval, value: newValue) }
    }
    
    var scheduledCategories: Set<CleanupCategory> {
        get { loadPreferences().scheduledCategories }
        set { updatePreference(\.scheduledCategories, value: newValue) }
    }
    
    var createBackupsByDefault: Bool {
        get { loadPreferences().createBackupsByDefault }
        set { updatePreference(\.createBackupsByDefault, value: newValue) }
    }
    
    var moveToTrashByDefault: Bool {
        get { loadPreferences().moveToTrashByDefault }
        set { updatePreference(\.moveToTrashByDefault, value: newValue) }
    }
    
    var oldFileThresholdDays: Int {
        get { loadPreferences().oldFileThresholdDays }
        set { 
            // Clamp to valid range [30, 1095]
            let clampedValue = min(max(newValue, 30), 1095)
            updatePreference(\.oldFileThresholdDays, value: clampedValue)
        }
    }
    
    var largeFileSizeThresholdMB: Int {
        get { loadPreferences().largeFileSizeThresholdMB }
        set { updatePreference(\.largeFileSizeThresholdMB, value: newValue) }
    }

    var scanIncludeDeveloperCaches: Bool {
        get { loadPreferences().scanIncludeDeveloperCaches }
        set { updatePreference(\.scanIncludeDeveloperCaches, value: newValue) }
    }

    var scanIncludeAIAgentCaches: Bool {
        get { loadPreferences().scanIncludeAIAgentCaches }
        set { updatePreference(\.scanIncludeAIAgentCaches, value: newValue) }
    }

    var projectArtifactScanRoots: [String] {
        get { loadPreferences().projectArtifactScanRoots }
        set { updatePreference(\.projectArtifactScanRoots, value: newValue) }
    }
    
    // MARK: - Validation
    
    /// Validates preferences and returns corrected version if needed
    /// - Parameter preferences: Preferences to validate
    /// - Returns: Validated preferences
    func validatePreferences(_ preferences: UserPreferences) -> UserPreferences {
        var validated = preferences
        
        // Clamp old file threshold to valid range
        validated.oldFileThresholdDays = min(max(preferences.oldFileThresholdDays, 30), 1095)
        
        // Ensure scheduled categories only include safe categories
        validated.scheduledCategories = preferences.scheduledCategories.intersection(UserPreferences.safeCategories)
        
        return validated
    }
}
