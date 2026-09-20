import Foundation

/// Cleanup interval options for scheduled cleanup
public enum CleanupInterval: String, Codable, Equatable {
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
public struct UserPreferences: Codable, Equatable {
    public var showMenuBarIcon: Bool
    public var launchAtLogin: Bool
    public var enableScheduledCleanup: Bool
    public var scheduledCleanupInterval: CleanupInterval
    public var scheduledCategories: Set<CleanupCategory>
    public var createBackupsByDefault: Bool
    public var moveToTrashByDefault: Bool
    public var oldFileThresholdDays: Int
    public var largeFileSizeThresholdMB: Int
    public var debugMode: Bool
    /// Whether cleanup scans include developer tool caches.
    ///
    /// Scanning them costs nothing on a machine that has none — the paths simply do not
    /// exist — so this is a "hide the noise" switch, not a performance one. Chromium app
    /// caches are never gated by it; those matter to every user.
    public var scanIncludeDeveloperCaches: Bool
    /// Whether cleanup scans include AI coding agent caches.
    public var scanIncludeAIAgentCaches: Bool
    /// Roots for the opt-in per-project build artifact scan.
    ///
    /// Empty by default and deliberately so: this is the only scan that walks the user's
    /// own source tree rather than a cache directory, so it never runs until the user
    /// names the folders it may look at.
    public var projectArtifactScanRoots: [String]
    
    /// Default preferences
    public static let `default` = UserPreferences(
        showMenuBarIcon: true,
        launchAtLogin: false,
        enableScheduledCleanup: false,
        scheduledCleanupInterval: .weekly,
        scheduledCategories: [.systemCaches, .applicationCaches, .temporaryFiles],
        createBackupsByDefault: true,
        moveToTrashByDefault: true,
        oldFileThresholdDays: 365,
        largeFileSizeThresholdMB: 100,
        debugMode: false,
        scanIncludeDeveloperCaches: true,
        scanIncludeAIAgentCaches: true,
        projectArtifactScanRoots: []
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
        showMenuBarIcon: Bool = true,
        launchAtLogin: Bool = false,
        enableScheduledCleanup: Bool,
        scheduledCleanupInterval: CleanupInterval,
        scheduledCategories: Set<CleanupCategory>,
        createBackupsByDefault: Bool,
        moveToTrashByDefault: Bool,
        oldFileThresholdDays: Int,
        largeFileSizeThresholdMB: Int,
        debugMode: Bool = false,
        scanIncludeDeveloperCaches: Bool = true,
        scanIncludeAIAgentCaches: Bool = true,
        projectArtifactScanRoots: [String] = []
    ) {
        self.showMenuBarIcon = showMenuBarIcon
        self.launchAtLogin = launchAtLogin
        self.enableScheduledCleanup = enableScheduledCleanup
        self.scheduledCleanupInterval = scheduledCleanupInterval
        self.scheduledCategories = scheduledCategories
        self.createBackupsByDefault = createBackupsByDefault
        self.moveToTrashByDefault = moveToTrashByDefault
        self.oldFileThresholdDays = oldFileThresholdDays
        self.largeFileSizeThresholdMB = largeFileSizeThresholdMB
        self.debugMode = debugMode
        self.scanIncludeDeveloperCaches = scanIncludeDeveloperCaches
        self.scanIncludeAIAgentCaches = scanIncludeAIAgentCaches
        self.projectArtifactScanRoots = projectArtifactScanRoots
    }

    enum CodingKeys: String, CodingKey {
        case showMenuBarIcon
        case launchAtLogin
        case enableScheduledCleanup
        case scheduledCleanupInterval
        case scheduledCategories
        case createBackupsByDefault
        case moveToTrashByDefault
        case oldFileThresholdDays
        case largeFileSizeThresholdMB
        case debugMode
        case scanIncludeDeveloperCaches
        case scanIncludeAIAgentCaches
        case projectArtifactScanRoots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UserPreferences.default

        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        enableScheduledCleanup = try container.decodeIfPresent(Bool.self, forKey: .enableScheduledCleanup) ?? defaults.enableScheduledCleanup
        scheduledCleanupInterval = try container.decodeIfPresent(CleanupInterval.self, forKey: .scheduledCleanupInterval) ?? defaults.scheduledCleanupInterval
        scheduledCategories = try container.decodeIfPresent(Set<CleanupCategory>.self, forKey: .scheduledCategories) ?? defaults.scheduledCategories
        createBackupsByDefault = try container.decodeIfPresent(Bool.self, forKey: .createBackupsByDefault) ?? defaults.createBackupsByDefault
        moveToTrashByDefault = try container.decodeIfPresent(Bool.self, forKey: .moveToTrashByDefault) ?? defaults.moveToTrashByDefault
        oldFileThresholdDays = try container.decodeIfPresent(Int.self, forKey: .oldFileThresholdDays) ?? defaults.oldFileThresholdDays
        largeFileSizeThresholdMB = try container.decodeIfPresent(Int.self, forKey: .largeFileSizeThresholdMB) ?? defaults.largeFileSizeThresholdMB
        debugMode = try container.decodeIfPresent(Bool.self, forKey: .debugMode) ?? defaults.debugMode
        scanIncludeDeveloperCaches = try container.decodeIfPresent(Bool.self, forKey: .scanIncludeDeveloperCaches) ?? defaults.scanIncludeDeveloperCaches
        scanIncludeAIAgentCaches = try container.decodeIfPresent(Bool.self, forKey: .scanIncludeAIAgentCaches) ?? defaults.scanIncludeAIAgentCaches
        projectArtifactScanRoots = try container.decodeIfPresent([String].self, forKey: .projectArtifactScanRoots) ?? defaults.projectArtifactScanRoots
    }
}
