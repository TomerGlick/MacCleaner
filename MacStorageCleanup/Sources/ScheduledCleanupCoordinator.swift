import Foundation
import UserNotifications

/// Protocol for posting notifications
public protocol NotificationPoster {
    func postNotification(title: String, body: String)
}

/// Implementation using UserNotifications framework
public final class UserNotificationPoster: NotificationPoster {
    public init() {
        requestNotificationPermissions()
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("Failed to request notification permissions: \(error.localizedDescription)")
            }
            if !granted {
                NSLog("Notification permissions not granted")
            }
        }
    }
    
    public func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "scheduled-cleanup-\(UUID().uuidString)",
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("Failed to post notification: \(error.localizedDescription)")
            }
        }
    }
}

/// Mock implementation for testing
public final class MockNotificationPoster: NotificationPoster {
    public var postedNotifications: [(title: String, body: String)] = []
    
    public func postNotification(title: String, body: String) {
        postedNotifications.append((title, body))
    }
}

/// Protocol for scheduled cleanup coordination
public protocol ScheduledCleanupCoordinator {
    /// Configures scheduled cleanup with user preferences
    func configure(preferences: UserPreferences) throws
    
    /// Starts scheduled cleanup based on current preferences
    func start() throws
    
    /// Stops scheduled cleanup
    func stop()
    
    /// Executes a scheduled cleanup operation
    func executeScheduledCleanup() async throws -> ScheduledCleanupResult
}

/// Result of a scheduled cleanup operation
public struct ScheduledCleanupResult {
    public let executionDate: Date
    public let filesRemoved: Int
    public let spaceFreed: Int64
    public let categoriesCleaned: Set<CleanupCategory>
    public let errors: [CleanupError]
    public let duration: TimeInterval
}

/// Implementation of scheduled cleanup coordinator using NSBackgroundActivityScheduler
public final class BackgroundScheduledCleanupCoordinator: ScheduledCleanupCoordinator {
    private let fileScanner: FileScanner
    private let storageAnalyzer: StorageAnalyzer
    private let cleanupEngine: CleanupEngine
    private let preferencesStore: PreferencesStore
    private let notificationPoster: NotificationPoster
    
    private var scheduler: NSBackgroundActivityScheduler?
    private var isRunning = false
    
    public init(
        fileScanner: FileScanner,
        storageAnalyzer: StorageAnalyzer,
        cleanupEngine: CleanupEngine,
        preferencesStore: PreferencesStore,
        notificationPoster: NotificationPoster = UserNotificationPoster()
    ) {
        self.fileScanner = fileScanner
        self.storageAnalyzer = storageAnalyzer
        self.cleanupEngine = cleanupEngine
        self.preferencesStore = preferencesStore
        self.notificationPoster = notificationPoster
    }
    
    public func configure(preferences: UserPreferences) throws {
        // Save preferences
        try preferencesStore.save(preferences)
        
        // Stop existing scheduler if running
        stop()
        
        // Start new scheduler if enabled
        if preferences.enableScheduledCleanup {
            try start()
        }
    }
    
    public func start() throws {
        guard !isRunning else { return }
        
        let preferences = try preferencesStore.load()
        guard preferences.enableScheduledCleanup else {
            throw ScheduledCleanupError.scheduledCleanupDisabled
        }
        
        // Create scheduler
        let scheduler = NSBackgroundActivityScheduler(identifier: "com.macstoragecleanup.scheduled")
        scheduler.interval = preferences.scheduledCleanupInterval.timeInterval
        scheduler.repeats = true
        scheduler.qualityOfService = .utility
        scheduler.tolerance = preferences.scheduledCleanupInterval.timeInterval * 0.1  // 10% tolerance
        
        // Set up activity handler
        scheduler.schedule { [weak self] completion in
            guard let self = self else {
                completion(.finished)
                return
            }
            
            Task {
                do {
                    _ = try await self.executeScheduledCleanup()
                    // Logging and notifications are handled in executeScheduledCleanup
                    completion(.finished)
                } catch {
                    // Error logging and notifications are handled in executeScheduledCleanup
                    completion(.finished)
                }
            }
        }
        
        self.scheduler = scheduler
        self.isRunning = true
    }
    
    public func stop() {
        scheduler?.invalidate()
        scheduler = nil
        isRunning = false
    }
    
    public func executeScheduledCleanup() async throws -> ScheduledCleanupResult {
        let startTime = Date()
        let preferences = try preferencesStore.load()
        
        // Validate that only safe categories are included
        let safeCategories = preferences.validatedScheduledCategories
        guard !safeCategories.isEmpty else {
            let error = ScheduledCleanupError.noSafeCategoriesConfigured
            logScheduledCleanupError(error: error)
            postErrorNotification(error: error)
            throw error
        }
        
        do {
            // Scan file system for safe categories only
            let scanResult = try await fileScanner.scan(
                paths: getDefaultScanPaths(),
                categories: safeCategories,
                progressHandler: { _ in }  // No progress reporting for scheduled cleanup
            )
            
            // Analyze results
            let analysisResult = storageAnalyzer.analyze(scanResult: scanResult)
            
            // Collect files from safe categories
            var filesToClean: [FileMetadata] = []
            for category in safeCategories {
                if let categoryFiles = analysisResult.categorizedFiles[category] {
                    filesToClean.append(contentsOf: categoryFiles)
                }
            }
            
            // Execute cleanup without user confirmation (scheduled cleanup)
            let cleanupOptions = CleanupOptions(
                createBackup: false,  // No backup for scheduled cleanup to save space
                moveToTrash: true,    // Always move to trash for safety
                skipInUseFiles: true  // Skip files in use
            )
            
            let cleanupResult = try await cleanupEngine.cleanup(
                files: filesToClean,
                options: cleanupOptions,
                progressHandler: { _ in }  // No progress reporting for scheduled cleanup
            )
            
            let duration = Date().timeIntervalSince(startTime)
            
            let result = ScheduledCleanupResult(
                executionDate: startTime,
                filesRemoved: cleanupResult.filesRemoved,
                spaceFreed: cleanupResult.spaceFreed,
                categoriesCleaned: safeCategories,
                errors: cleanupResult.errors,
                duration: duration
            )
            
            // Log and notify
            logScheduledCleanup(result: result)
            postNotification(result: result)
            
            return result
        } catch {
            // Log and notify on error
            logScheduledCleanupError(error: error)
            postErrorNotification(error: error)
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private func getDefaultScanPaths() -> [URL] {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeURL.appendingPathComponent("Library/Caches"),
            URL(fileURLWithPath: "/tmp"),
            URL(fileURLWithPath: "/var/tmp"),
            homeURL.appendingPathComponent("Library/Application Support")
        ]
    }
    
    private func logScheduledCleanup(result: ScheduledCleanupResult) {
        let log = """
        Scheduled Cleanup Completed:
        - Date: \(result.executionDate)
        - Files Removed: \(result.filesRemoved)
        - Space Freed: \(ByteCountFormatter.string(fromByteCount: result.spaceFreed, countStyle: .file))
        - Categories: \(result.categoriesCleaned.map { $0.rawValue }.joined(separator: ", "))
        - Duration: \(String(format: "%.2f", result.duration))s
        - Errors: \(result.errors.count)
        """
        
        NSLog("%@", log)
        
        // Log individual errors if any
        if !result.errors.isEmpty {
            let errorDetails = result.errors.enumerated().map { index, error in
                "  Error \(index + 1): \(error.localizedDescription)"
            }.joined(separator: "\n")
            NSLog("Error details:\n%@", errorDetails)
        }
        
        // Write to log file
        if let logURL = getLogFileURL() {
            var fullLog = log
            if !result.errors.isEmpty {
                fullLog += "\nErrors:\n"
                fullLog += result.errors.enumerated().map { index, error in
                    "  \(index + 1). \(formatCleanupError(error))"
                }.joined(separator: "\n")
            }
            try? appendToLogFile(logURL: logURL, message: fullLog)
        }
    }
    
    private func formatCleanupError(_ error: CleanupError) -> String {
        switch error {
        case .fileProtected(let path):
            return "File protected: \(path)"
        case .fileInUse(let path):
            return "File in use: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .cancelled:
            return "Operation cancelled"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
    
    private func logScheduledCleanupError(error: Error) {
        let log = """
        Scheduled Cleanup Error:
        - Date: \(Date())
        - Error Type: \(type(of: error))
        - Error: \(error.localizedDescription)
        """
        
        NSLog("%@", log)
        
        // Log additional context for specific error types
        if let scheduledError = error as? ScheduledCleanupError {
            NSLog("Scheduled cleanup specific error: %@", String(describing: scheduledError))
        }
        
        // Write to log file
        if let logURL = getLogFileURL() {
            try? appendToLogFile(logURL: logURL, message: log)
        }
    }
    
    private func getLogFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let logDir = appSupport.appendingPathComponent("MacStorageCleanup/Logs")
        try? fileManager.createDirectory(at: logDir, withIntermediateDirectories: true)
        
        return logDir.appendingPathComponent("scheduled-cleanup.log")
    }
    
    private func appendToLogFile(logURL: URL, message: String) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "\n[\(timestamp)]\n\(message)\n"
        
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try logEntry.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
    
    private func postNotification(result: ScheduledCleanupResult) {
        var body = "Freed \(ByteCountFormatter.string(fromByteCount: result.spaceFreed, countStyle: .file)) by removing \(result.filesRemoved) files"
        
        // Add error count if there were errors
        if !result.errors.isEmpty {
            body += " (\(result.errors.count) error\(result.errors.count == 1 ? "" : "s"))"
        }
        
        notificationPoster.postNotification(
            title: "Scheduled Cleanup Complete",
            body: body
        )
    }
    
    private func postErrorNotification(error: Error) {
        notificationPoster.postNotification(
            title: "Scheduled Cleanup Error",
            body: error.localizedDescription
        )
    }
}

/// Errors specific to scheduled cleanup
public enum ScheduledCleanupError: Error, LocalizedError {
    case scheduledCleanupDisabled
    case noSafeCategoriesConfigured
    case preferencesNotFound
    
    public var errorDescription: String? {
        switch self {
        case .scheduledCleanupDisabled:
            return "Scheduled cleanup is disabled in preferences"
        case .noSafeCategoriesConfigured:
            return "No safe categories configured for scheduled cleanup"
        case .preferencesNotFound:
            return "User preferences not found"
        }
    }
}
