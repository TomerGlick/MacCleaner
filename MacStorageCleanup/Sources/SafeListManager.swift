import Foundation

/// Protocol for managing safe-list of protected files and directories
public protocol SafeListManager {
    /// Check if a URL is protected
    func isProtected(url: URL) -> Bool
    
    /// Check if a path is protected
    func isProtected(path: String) -> Bool
    
    /// Update safe-list based on macOS version
    func updateSafeList(for macOSVersion: OperatingSystemVersion)
}

/// Implementation of SafeListManager with protected paths and patterns
public final class DefaultSafeListManager: SafeListManager {
    private var protectedPaths: Set<String>
    private var protectedUserPaths: Set<String>
    private var systemApplications: Set<String>
    
    public init() {
        // Initialize with default protected paths
        self.protectedPaths = Self.defaultProtectedPaths()
        self.protectedUserPaths = Self.defaultProtectedUserPaths()
        self.systemApplications = Self.defaultSystemApplications()
        
        // Update for current macOS version
        let version = ProcessInfo.processInfo.operatingSystemVersion
        updateSafeList(for: version)
    }
    
    public func isProtected(url: URL) -> Bool {
        return isProtected(path: url.path)
    }
    
    public func isProtected(path: String) -> Bool {
        // Expand tilde in path for user directory
        let expandedPath = (path as NSString).expandingTildeInPath
        
        // Check protected system paths
        for protectedPath in protectedPaths {
            if expandedPath.hasPrefix(protectedPath) {
                return true
            }
        }
        
        // Check protected user paths
        for protectedUserPath in protectedUserPaths {
            let expandedProtectedPath = (protectedUserPath as NSString).expandingTildeInPath
            if expandedPath.hasPrefix(expandedProtectedPath) {
                return true
            }
        }
        
        // Check if it's a system application
        if expandedPath.hasPrefix("/Applications/") || expandedPath.hasPrefix("/System/Applications/") {
            let components = expandedPath.components(separatedBy: "/")
            if let appComponent = components.first(where: { $0.hasSuffix(".app") }) {
                if systemApplications.contains(appComponent) {
                    return true
                }
            }
        }
        
        return false
    }
    
    public func updateSafeList(for macOSVersion: OperatingSystemVersion) {
        // Add version-specific protected paths
        if macOSVersion.majorVersion >= 11 {
            // macOS Big Sur and later
            protectedPaths.insert("/System/Volumes/Data")
            protectedPaths.insert("/System/Volumes/Preboot")
        }
        
        if macOSVersion.majorVersion >= 12 {
            // macOS Monterey and later
            protectedPaths.insert("/System/Library/CoreServices")
        }
        
        if macOSVersion.majorVersion >= 13 {
            // macOS Ventura and later - add any version-specific paths
            protectedPaths.insert("/Library/Apple/System")
        }
    }
    
    // MARK: - Default Protected Paths
    
    private static func defaultProtectedPaths() -> Set<String> {
        return [
            "/System",
            "/Library/Apple",
            "/usr/bin",
            "/usr/sbin",
            "/usr/lib",
            "/usr/libexec",
            "/private/var/db",
            "/private/var/root",
            "/bin",
            "/sbin",
            "/private/etc",
            "/private/var/vm"
        ]
    }
    
    private static func defaultProtectedUserPaths() -> Set<String> {
        return [
            "~/Library/Keychains",
            "~/Library/Mail",
            "~/Library/Messages",
            "~/Library/Photos",
            "~/Library/Safari",
            "~/Library/Calendars",
            "~/Library/Contacts"
        ]
    }
    
    private static func defaultSystemApplications() -> Set<String> {
        return [
            "Safari.app",
            "Mail.app",
            "Messages.app",
            "Photos.app",
            "Calendar.app",
            "Contacts.app",
            "FaceTime.app",
            "Music.app",
            "TV.app",
            "Podcasts.app",
            "Books.app",
            "App Store.app",
            "System Preferences.app",
            "System Settings.app",
            "Finder.app",
            "TextEdit.app",
            "Preview.app",
            "QuickTime Player.app",
            "Notes.app",
            "Reminders.app",
            "Maps.app",
            "News.app",
            "Stocks.app",
            "Home.app",
            "Voice Memos.app",
            "Calculator.app",
            "Dictionary.app",
            "Font Book.app",
            "Time Machine.app"
        ]
    }
}
