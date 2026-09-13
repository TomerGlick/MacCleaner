import Foundation

public enum PreferencesStorageConstants {
    public static let primaryKey = "MacStorageCleanup.UserPreferences"
    public static let legacyEncodedPreferencesKey = "com.macstoragecleanup.preferences"
    public static let legacyShowMenuBarIconKey = "showMenuBarIcon"
    public static let legacyLaunchAtLoginKey = "launchAtLogin"
    public static let legacyDebugModeKey = "debugMode"
}

/// Protocol for storing and retrieving user preferences
public protocol PreferencesStore {
    /// Saves user preferences
    func save(_ preferences: UserPreferences) throws
    
    /// Loads user preferences
    func load() throws -> UserPreferences
    
    /// Resets preferences to default values
    func reset() throws
}

/// UserDefaults-based implementation of PreferencesStore
public final class UserDefaultsPreferencesStore: PreferencesStore {
    private let userDefaults: UserDefaults
    private let preferencesKey = PreferencesStorageConstants.primaryKey
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func save(_ preferences: UserPreferences) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(preferences)
        userDefaults.set(data, forKey: preferencesKey)
        userDefaults.removeObject(forKey: PreferencesStorageConstants.legacyEncodedPreferencesKey)
        userDefaults.removeObject(forKey: PreferencesStorageConstants.legacyShowMenuBarIconKey)
        userDefaults.removeObject(forKey: PreferencesStorageConstants.legacyLaunchAtLoginKey)
        userDefaults.removeObject(forKey: PreferencesStorageConstants.legacyDebugModeKey)
        userDefaults.synchronize()
    }
    
    public func load() throws -> UserPreferences {
        if let data = userDefaults.data(forKey: preferencesKey) {
            return try decodePreferences(from: data)
        }

        if let legacyData = userDefaults.data(forKey: PreferencesStorageConstants.legacyEncodedPreferencesKey) {
            let migratedPreferences = try decodePreferences(from: legacyData)
            try save(migratedPreferences)
            return migratedPreferences
        }

        let migratedPreferences = mergeLegacyStandaloneValues(into: .default)
        if migratedPreferences != .default {
            try save(migratedPreferences)
        }

        return migratedPreferences
    }
    
    public func reset() throws {
        try save(.default)
    }

    private func decodePreferences(from data: Data) throws -> UserPreferences {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UserPreferences.self, from: data)
        return mergeLegacyStandaloneValues(into: decoded)
    }

    private func mergeLegacyStandaloneValues(into preferences: UserPreferences) -> UserPreferences {
        var merged = preferences

        if let showMenuBarIcon = userDefaults.object(forKey: PreferencesStorageConstants.legacyShowMenuBarIconKey) as? Bool {
            merged.showMenuBarIcon = showMenuBarIcon
        }

        if let launchAtLogin = userDefaults.object(forKey: PreferencesStorageConstants.legacyLaunchAtLoginKey) as? Bool {
            merged.launchAtLogin = launchAtLogin
        }

        if let debugMode = userDefaults.object(forKey: PreferencesStorageConstants.legacyDebugModeKey) as? Bool {
            merged.debugMode = debugMode
        }

        return merged
    }
}

/// File-based implementation of PreferencesStore for testing
final class FilePreferencesStore: PreferencesStore {
    private let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    func save(_ preferences: UserPreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL, options: .atomic)
    }
    
    func load() throws -> UserPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(UserPreferences.self, from: data)
    }
    
    func reset() throws {
        try save(.default)
    }
}
