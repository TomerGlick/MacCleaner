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
    /// Whether the app checks GitHub Releases for a newer version.
    ///
    /// This is the app's only outbound network request. On by default because a directly
    /// distributed app has no other way to tell you a fix exists, and switchable off for
    /// anyone who would rather it stayed entirely offline.
    public var checkForUpdatesAutomatically: Bool
    /// When the last check ran, so launching repeatedly does not hammer the API.
    public var lastUpdateCheck: Date?
    /// The newest version seen, so a known update survives a relaunch without a request.
    public var latestKnownVersion: String?
    /// Folders where the user keeps source code.
    ///
    /// Used to find which toolchain versions a project pins, so an NDK or Gradle version
    /// still in use is never offered for deletion. When empty the app falls back to
    /// guessing conventional folder names, which is only ever a guess — asking is the
    /// whole point of this setting.
    public var projectFolders: [String]
    /// Whether the user has been offered the chance to name their project folders. Asked
    /// once; declining is a valid answer and must not be re-asked on every scan.
    public var hasPromptedForProjectFolders: Bool
    /// Whether regenerable build output inside `projectFolders` is offered for cleanup.
    /// Separate from the folders themselves: pointing the app at your code so it can read
    /// version pins is a much smaller ask than letting it offer that code's output for
    /// deletion.
    public var scanProjectBuildArtifacts: Bool
    /// Whether the user has been offered the privileged helper that lets "Free RAM" run
    /// without a password. Asked once on launch; "Not now" is an answer, and Preferences
    /// keeps the offer available.
    public var hasPromptedForMemoryHelper: Bool
    
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
        checkForUpdatesAutomatically: true,
        lastUpdateCheck: nil,
        latestKnownVersion: nil,
        projectFolders: [],
        hasPromptedForProjectFolders: false,
        scanProjectBuildArtifacts: false,
        hasPromptedForMemoryHelper: false
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
        checkForUpdatesAutomatically: Bool = true,
        lastUpdateCheck: Date? = nil,
        latestKnownVersion: String? = nil,
        projectFolders: [String] = [],
        hasPromptedForProjectFolders: Bool = false,
        scanProjectBuildArtifacts: Bool = false,
        hasPromptedForMemoryHelper: Bool = false
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
        self.checkForUpdatesAutomatically = checkForUpdatesAutomatically
        self.lastUpdateCheck = lastUpdateCheck
        self.latestKnownVersion = latestKnownVersion
        self.projectFolders = projectFolders
        self.hasPromptedForProjectFolders = hasPromptedForProjectFolders
        self.scanProjectBuildArtifacts = scanProjectBuildArtifacts
        self.hasPromptedForMemoryHelper = hasPromptedForMemoryHelper
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
        case checkForUpdatesAutomatically
        case lastUpdateCheck
        case latestKnownVersion
        case projectFolders
        case hasPromptedForProjectFolders
        case scanProjectBuildArtifacts
        case hasPromptedForMemoryHelper
        /// Pre-1.5 name, when the folders existed only to drive the build artifact scan.
        case projectArtifactScanRoots
    }

    /// Written explicitly because `projectArtifactScanRoots` is a read-only compatibility
    /// key with no property behind it, which defeats the synthesized encoder.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(enableScheduledCleanup, forKey: .enableScheduledCleanup)
        try container.encode(scheduledCleanupInterval, forKey: .scheduledCleanupInterval)
        try container.encode(scheduledCategories, forKey: .scheduledCategories)
        try container.encode(createBackupsByDefault, forKey: .createBackupsByDefault)
        try container.encode(moveToTrashByDefault, forKey: .moveToTrashByDefault)
        try container.encode(oldFileThresholdDays, forKey: .oldFileThresholdDays)
        try container.encode(largeFileSizeThresholdMB, forKey: .largeFileSizeThresholdMB)
        try container.encode(debugMode, forKey: .debugMode)
        try container.encode(scanIncludeDeveloperCaches, forKey: .scanIncludeDeveloperCaches)
        try container.encode(scanIncludeAIAgentCaches, forKey: .scanIncludeAIAgentCaches)
        try container.encode(checkForUpdatesAutomatically, forKey: .checkForUpdatesAutomatically)
        try container.encodeIfPresent(lastUpdateCheck, forKey: .lastUpdateCheck)
        try container.encodeIfPresent(latestKnownVersion, forKey: .latestKnownVersion)
        try container.encode(projectFolders, forKey: .projectFolders)
        try container.encode(hasPromptedForProjectFolders, forKey: .hasPromptedForProjectFolders)
        try container.encode(scanProjectBuildArtifacts, forKey: .scanProjectBuildArtifacts)
        try container.encode(hasPromptedForMemoryHelper, forKey: .hasPromptedForMemoryHelper)
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
        checkForUpdatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? defaults.checkForUpdatesAutomatically
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        latestKnownVersion = try container.decodeIfPresent(String.self, forKey: .latestKnownVersion)

        // Folders that were previously set only for the build artifact scan keep working,
        // and keep that scan enabled — the user had already opted into it.
        let legacyRoots = try container.decodeIfPresent([String].self, forKey: .projectArtifactScanRoots)
        projectFolders = try container.decodeIfPresent([String].self, forKey: .projectFolders)
            ?? legacyRoots
            ?? defaults.projectFolders
        hasPromptedForProjectFolders = try container.decodeIfPresent(Bool.self, forKey: .hasPromptedForProjectFolders)
            ?? !(legacyRoots ?? []).isEmpty
        scanProjectBuildArtifacts = try container.decodeIfPresent(Bool.self, forKey: .scanProjectBuildArtifacts)
            ?? !(legacyRoots ?? []).isEmpty
        hasPromptedForMemoryHelper = try container.decodeIfPresent(Bool.self, forKey: .hasPromptedForMemoryHelper)
            ?? defaults.hasPromptedForMemoryHelper
    }
}
