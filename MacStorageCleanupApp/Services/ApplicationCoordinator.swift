import Foundation
import MacStorageCleanupCore

/// Main application coordinator that manages all components and state
@MainActor
class ApplicationCoordinator: ObservableObject {
    // MARK: - Published State
    
    @Published var preferences: UserPreferences
    @Published var isInitialized = false
    @Published var globalErrors: [AppError] = []
    
    // MARK: - Core Components
    
    let fileScanner: FileScanner
    let storageAnalyzer: StorageAnalyzer
    let cleanupEngine: CleanupEngine
    let applicationManager: ApplicationManager
    let cacheManager: CacheManager
    let backupManager: BackupManager
    let safeListManager: SafeListManager
    let scheduledCleanupCoordinator: ScheduledCleanupCoordinator
    
    // MARK: - Services
    
    let notificationService: NotificationService
    let loggingService: LoggingService
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "MacStorageCleanup.UserPreferences"
    
    // MARK: - Singleton
    
    static let shared = ApplicationCoordinator()
    
    // MARK: - Initialization
    
    private init() {
        // Load preferences
        if let data = userDefaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            self.preferences = decoded
        } else {
            self.preferences = .default
        }
        
        // Initialize core components
        self.safeListManager = DefaultSafeListManager()
        self.fileScanner = DefaultFileScanner(safeListManager: safeListManager)
        self.storageAnalyzer = DefaultStorageAnalyzer()
        self.backupManager = DefaultBackupManager()
        self.cleanupEngine = DefaultCleanupEngine(
            safeListManager: safeListManager,
            backupManager: backupManager
        )
        self.applicationManager = DefaultApplicationManager()
        self.cacheManager = DefaultCacheManager()
        
        // Initialize preferences store
        let preferencesStore = UserDefaultsPreferencesStore()
        
        // Initialize scheduled cleanup coordinator
        self.scheduledCleanupCoordinator = BackgroundScheduledCleanupCoordinator(
            fileScanner: fileScanner,
            storageAnalyzer: storageAnalyzer,
            cleanupEngine: cleanupEngine,
            preferencesStore: preferencesStore
        )
        
        // Initialize services
        self.notificationService = NotificationService.shared
        self.loggingService = LoggingService.shared
        
        // Complete initialization
        Task {
            await initialize()
        }
    }
    
    // MARK: - Lifecycle
    
    func initialize() async {
        // Update safe list for current macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        safeListManager.updateSafeList(for: osVersion)
        
        // Configure scheduled cleanup if enabled
        if preferences.enableScheduledCleanup {
            do {
                try scheduledCleanupCoordinator.configure(preferences: preferences)
                try scheduledCleanupCoordinator.start()
            } catch {
                print("Failed to configure scheduled cleanup: \(error)")
            }
        }
        
        isInitialized = true
    }
    
    // MARK: - Preferences Management
    
    func updatePreferences(_ newPreferences: UserPreferences) {
        preferences = newPreferences
        savePreferences()
        
        // Update scheduled cleanup configuration
        do {
            if preferences.enableScheduledCleanup {
                try scheduledCleanupCoordinator.configure(preferences: preferences)
                try scheduledCleanupCoordinator.start()
            } else {
                scheduledCleanupCoordinator.stop()
            }
        } catch {
            print("Failed to update scheduled cleanup: \(error)")
        }
    }
    
    func savePreferences() {
        if let encoded = try? JSONEncoder().encode(preferences) {
            userDefaults.set(encoded, forKey: preferencesKey)
        }
    }
    
    // MARK: - Error Handling
    
    func reportError(_ error: AppError) {
        globalErrors.append(error)
        
        // Log error with appropriate level
        switch error.severity {
        case .low:
            loggingService.info("[\(error.category)] \(error.message)")
        case .medium:
            loggingService.warning("[\(error.category)] \(error.message)")
        case .high:
            loggingService.error("[\(error.category)] \(error.message)")
        case .critical:
            loggingService.critical("[\(error.category)] \(error.message)")
        }
        
        // Send notification for critical errors
        if error.severity == .critical {
            notificationService.sendNotification(
                title: "Error",
                body: error.localizedDescription,
                category: "APP_ERROR"
            )
        }
    }
    
    func clearErrors() {
        globalErrors.removeAll()
    }
    
    func dismissError(_ error: AppError) {
        globalErrors.removeAll { $0.id == error.id }
    }
    
    // MARK: - Cleanup Operations
    
    func performCleanup(
        files: [FileMetadata],
        options: CleanupOptions,
        progressHandler: @escaping (CleanupProgress) -> Void
    ) async throws -> MacStorageCleanupCore.CleanupResult {
        // Convert app CleanupOptions to core CleanupOptions
        let coreOptions = MacStorageCleanupCore.CleanupOptions(
            createBackup: options.createBackup,
            moveToTrash: options.moveToTrash,
            skipInUseFiles: true
        )
        
        do {
            let result = try await cleanupEngine.cleanup(
                files: files,
                options: coreOptions,
                progressHandler: progressHandler
            )
            
            // Send success notification if significant space was freed
            if result.spaceFreed > 100_000_000 { // > 100 MB
                notificationService.sendNotification(
                    title: "Cleanup Complete",
                    body: "Freed \(ByteCountFormatter.string(fromByteCount: result.spaceFreed, countStyle: .file))",
                    category: "CLEANUP_COMPLETE"
                )
            }
            
            // Return the core result (types are compatible)
            return result
        } catch {
            reportError(AppError(
                message: "Cleanup failed: \(error.localizedDescription)",
                severity: .high,
                category: .cleanup
            ))
            throw error
        }
    }
    
    // MARK: - Scan Operations
    
    func performScan(
        paths: [URL],
        categories: Set<CleanupCategory>,
        progressHandler: @escaping (ScanProgress) -> Void
    ) async throws -> ScanResult {
        do {
            return try await fileScanner.scan(
                paths: paths,
                categories: categories,
                progressHandler: progressHandler
            )
        } catch {
            reportError(AppError(
                message: "Scan failed: \(error.localizedDescription)",
                severity: .medium,
                category: .scan
            ))
            throw error
        }
    }
    
    // MARK: - Application Management
    
    func discoverApplications() async -> [Application] {
        return await applicationManager.discoverApplications()
    }
    
    func uninstallApplication(
        _ application: Application,
        removeAssociatedFiles: Bool
    ) async throws -> UninstallResult {
        do {
            return try await applicationManager.uninstall(
                application: application,
                removeAssociatedFiles: removeAssociatedFiles
            )
        } catch {
            reportError(AppError(
                message: "Uninstall failed: \(error.localizedDescription)",
                severity: .high,
                category: .uninstall
            ))
            throw error
        }
    }
    
    // MARK: - Backup Management
    
    func listBackups() -> [Backup] {
        return backupManager.listBackups()
    }
    
    func restoreBackup(_ backup: Backup, destination: URL) async throws -> RestoreResult {
        do {
            return try await backupManager.restoreBackup(backup: backup, destination: destination)
        } catch {
            reportError(AppError(
                message: "Restore failed: \(error.localizedDescription)",
                severity: .high,
                category: .backup
            ))
            throw error
        }
    }
    
    func deleteBackup(_ backup: Backup) throws {
        do {
            try backupManager.deleteBackup(backup: backup)
        } catch {
            reportError(AppError(
                message: "Delete backup failed: \(error.localizedDescription)",
                severity: .medium,
                category: .backup
            ))
            throw error
        }
    }
}

// MARK: - Application Error

struct AppError: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let severity: Severity
    let category: Category
    let timestamp = Date()
    
    enum Severity {
        case low
        case medium
        case high
        case critical
    }
    
    enum Category {
        case scan
        case cleanup
        case backup
        case uninstall
        case preferences
        case general
    }
    
    var localizedDescription: String {
        message
    }
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }
}
