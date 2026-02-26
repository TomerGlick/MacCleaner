import Foundation

/// Cleanup interval options for scheduled cleanup
public enum CleanupInterval: String, Codable {
    case daily
    case weekly
    case monthly
    
    /// Returns the time interval in seconds for the cleanup interval
    public var timeInterval: TimeInterval {
        switch self {
        case .daily:
            return 24 * 60 * 60  // 1 day
        case .weekly:
            return 7 * 24 * 60 * 60  // 7 days
        case .monthly:
            return 30 * 24 * 60 * 60  // 30 days (approximate)
        }
    }
}

/// User preferences for the application
public struct UserPreferences: Codable {
    public var enableScheduledCleanup: Bool
    public var scheduledCleanupInterval: CleanupInterval
    public var scheduledCategories: Set<CleanupCategory>
    public var createBackupsByDefault: Bool
    public var moveToTrashByDefault: Bool
    public var oldFileThresholdDays: Int
    public var largeFileSizeThresholdMB: Int
    public var debugMode: Bool
    
    /// Default preferences
    public static let `default` = UserPreferences(
        enableScheduledCleanup: false,
        scheduledCleanupInterval: .weekly,
        scheduledCategories: [.systemCaches, .applicationCaches, .temporaryFiles],
        createBackupsByDefault: true,
        moveToTrashByDefault: true,
        oldFileThresholdDays: 365,
        largeFileSizeThresholdMB: 100,
        debugMode: false
    )
    
    /// Safe categories that can be included in scheduled cleanup
    public static let safeCategories: Set<CleanupCategory> = [
        .systemCaches,
        .applicationCaches,
        .browserCaches,
        .temporaryFiles
    ]
    
    /// Validates that scheduled categories only include safe categories
    public var validatedScheduledCategories: Set<CleanupCategory> {
        return scheduledCategories.intersection(UserPreferences.safeCategories)
    }
    
    public init(
        enableScheduledCleanup: Bool,
        scheduledCleanupInterval: CleanupInterval,
        scheduledCategories: Set<CleanupCategory>,
        createBackupsByDefault: Bool,
        moveToTrashByDefault: Bool,
        oldFileThresholdDays: Int,
        largeFileSizeThresholdMB: Int,
        debugMode: Bool = false
    ) {
        self.enableScheduledCleanup = enableScheduledCleanup
        self.scheduledCleanupInterval = scheduledCleanupInterval
        self.scheduledCategories = scheduledCategories
        self.createBackupsByDefault = createBackupsByDefault
        self.moveToTrashByDefault = moveToTrashByDefault
        self.oldFileThresholdDays = oldFileThresholdDays
        self.largeFileSizeThresholdMB = largeFileSizeThresholdMB
        self.debugMode = debugMode
    }
}
