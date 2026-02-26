import Foundation

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
    private let preferencesKey = "com.macstoragecleanup.preferences"
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    public func save(_ preferences: UserPreferences) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(preferences)
        userDefaults.set(data, forKey: preferencesKey)
        userDefaults.synchronize()
    }
    
    public func load() throws -> UserPreferences {
        guard let data = userDefaults.data(forKey: preferencesKey) else {
            // Return default preferences if none exist
            return .default
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(UserPreferences.self, from: data)
    }
    
    public func reset() throws {
        try save(.default)
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
