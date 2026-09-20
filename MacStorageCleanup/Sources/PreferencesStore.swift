import Foundation

public enum PreferencesStorageConstants {
    public static let primaryKey = "MacStorageCleanup.UserPreferences"
    public static let legacyEncodedPreferencesKey = "com.macstoragecleanup.preferences"
    public static let legacyShowMenuBarIconKey = "showMenuBarIcon"
    public static let legacyLaunchAtLoginKey = "launchAtLogin"
    public static let legacyDebugModeKey = "debugMode"

    /// The bundle identifier the app shipped under up to 1.3.0.
    ///
    /// `UserDefaults.standard` is keyed by bundle identifier, so renaming the bundle moves
    /// the whole preferences domain and a returning user would silently find every setting
    /// back at its default. Their old domain is read once and copied forward.
    public static let legacyBundleDomain = "com.example.MacStorageCleanup"
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
    /// The pre-rename preferences domain, read only when the current one is empty.
    private let legacyDomainDefaults: UserDefaults?
    private let preferencesKey = PreferencesStorageConstants.primaryKey

    public init(
        userDefaults: UserDefaults = .standard,
        legacyDomainDefaults: UserDefaults? = UserDefaults(suiteName: PreferencesStorageConstants.legacyBundleDomain)
    ) {
        self.userDefaults = userDefaults
        self.legacyDomainDefaults = legacyDomainDefaults
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

        // Nothing in this domain: the user may be arriving from the pre-rename bundle
        // identifier, so look there before falling back to defaults.
        if let inherited = try preferencesFromLegacyDomain() {
            try save(inherited)
            return inherited
        }

        let migratedPreferences = mergeLegacyStandaloneValues(into: .default)
        if migratedPreferences != .default {
            try save(migratedPreferences)
        }

        return migratedPreferences
    }

    /// Preferences carried over from the bundle identifier used up to 1.3.0, if any.
    private func preferencesFromLegacyDomain() throws -> UserPreferences? {
        guard let legacyDomainDefaults,
              legacyDomainDefaults != userDefaults else { return nil }

        if let data = legacyDomainDefaults.data(forKey: preferencesKey)
            ?? legacyDomainDefaults.data(forKey: PreferencesStorageConstants.legacyEncodedPreferencesKey) {
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(UserPreferences.self, from: data)
            return mergeLegacyStandaloneValues(into: decoded, from: legacyDomainDefaults)
        }

        // No encoded blob, but the very old standalone keys may still be there.
        let merged = mergeLegacyStandaloneValues(into: .default, from: legacyDomainDefaults)
        return merged == .default ? nil : merged
    }
    
    public func reset() throws {
        try save(.default)
    }

    private func decodePreferences(from data: Data) throws -> UserPreferences {
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UserPreferences.self, from: data)
        return mergeLegacyStandaloneValues(into: decoded)
    }

    private func mergeLegacyStandaloneValues(
        into preferences: UserPreferences,
        from source: UserDefaults? = nil
    ) -> UserPreferences {
        let defaults = source ?? userDefaults
        var merged = preferences

        if let showMenuBarIcon = defaults.object(forKey: PreferencesStorageConstants.legacyShowMenuBarIconKey) as? Bool {
            merged.showMenuBarIcon = showMenuBarIcon
        }

        if let launchAtLogin = defaults.object(forKey: PreferencesStorageConstants.legacyLaunchAtLoginKey) as? Bool {
            merged.launchAtLogin = launchAtLogin
        }

        if let debugMode = defaults.object(forKey: PreferencesStorageConstants.legacyDebugModeKey) as? Bool {
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
