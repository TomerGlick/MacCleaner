import Foundation

/// Protocol for managing cache file identification and operations
public protocol CacheManager {
    func findSystemCaches() async -> [FileMetadata]
    func findApplicationCaches() async -> [FileMetadata]
    func findBrowserCaches() async -> [BrowserCache]
    func findDeveloperCaches() async -> [DeveloperCache]
    func findAIAgentCaches() async -> [AIAgentCache]
    func clearCaches(caches: [FileMetadata]) async throws -> CleanupResult
}

/// Represents a developer tool cache location
public struct DeveloperCache: Equatable, Hashable {
    public let tool: DeveloperTool
    public let cacheLocation: URL
    public let size: Int64
    public let description: String
    
    public init(tool: DeveloperTool, cacheLocation: URL, size: Int64, description: String) {
        self.tool = tool
        self.cacheLocation = cacheLocation
        self.size = size
        self.description = description
    }
}

/// Supported developer tools for cache management
public enum DeveloperTool: String, CaseIterable {
    case xcode
    case xcodeSimulators
    case xcodeDerivedData
    case xcodeArchives
    case xcodeDeviceSupport
    case androidStudio
    case intellijIdea
    case visualStudioCode
    case jetbrainsToolbox
    case cocoapods
    case carthage
    case swiftPackageManager
    case gradle
    case maven
    case npm
    case yarn
    case pip
    case homebrew
    
    public var displayName: String {
        switch self {
        case .xcode: return "Xcode Caches"
        case .xcodeSimulators: return "Xcode Simulators"
        case .xcodeDerivedData: return "Xcode DerivedData"
        case .xcodeArchives: return "Xcode Archives"
        case .xcodeDeviceSupport: return "iOS Device Support"
        case .xcodeSimulators: return "Xcode Simulators"
        case .xcodeDerivedData: return "Xcode DerivedData"
        case .xcodeArchives: return "Xcode Archives"
        case .androidStudio: return "Android Studio"
        case .intellijIdea: return "IntelliJ IDEA"
        case .visualStudioCode: return "VS Code"
        case .jetbrainsToolbox: return "JetBrains Toolbox"
        case .cocoapods: return "CocoaPods"
        case .carthage: return "Carthage"
        case .swiftPackageManager: return "Swift Package Manager"
        case .gradle: return "Gradle"
        case .maven: return "Maven"
        case .npm: return "npm"
        case .yarn: return "Yarn"
        case .pip: return "pip"
        case .homebrew: return "Homebrew"
        }
    }
    
    /// Returns the cache directory paths for this tool
    public func cachePaths(homeDir: String) -> [String] {
        switch self {
        case .xcode:
            return ["\(homeDir)/Library/Caches/com.apple.dt.Xcode"]
        case .xcodeSimulators:
            return [
                "\(homeDir)/Library/Developer/CoreSimulator/Caches",
                "\(homeDir)/Library/Developer/CoreSimulator/Devices",
                "/Library/Developer/CoreSimulator/Volumes",
                "/Library/Developer/CoreSimulator/Profiles/Runtimes",
                "/Library/Developer/CoreSimulator/Cryptex/Images/bundle",
                "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime"
            ]
        case .xcodeDerivedData:
            return ["\(homeDir)/Library/Developer/Xcode/DerivedData"]
        case .xcodeArchives:
            return ["\(homeDir)/Library/Developer/Xcode/Archives"]
        case .xcodeDeviceSupport:
            return ["\(homeDir)/Library/Developer/Xcode/iOS DeviceSupport"]
        case .androidStudio:
            return [
                "\(homeDir)/Library/Caches/Google/AndroidStudio*",
                "\(homeDir)/Library/Application Support/Google/AndroidStudio*/caches"
            ]
        case .intellijIdea:
            return [
                "\(homeDir)/Library/Caches/JetBrains/IntelliJIdea*",
                "\(homeDir)/Library/Application Support/JetBrains/IntelliJIdea*/caches"
            ]
        case .visualStudioCode:
            return [
                "\(homeDir)/Library/Caches/com.microsoft.VSCode",
                "\(homeDir)/Library/Application Support/Code/CachedData"
            ]
        case .jetbrainsToolbox:
            return ["\(homeDir)/Library/Caches/JetBrains/Toolbox"]
        case .cocoapods:
            return ["\(homeDir)/Library/Caches/CocoaPods"]
        case .carthage:
            return ["\(homeDir)/Library/Caches/org.carthage.CarthageKit"]
        case .swiftPackageManager:
            return ["\(homeDir)/Library/Caches/org.swift.swiftpm"]
        case .gradle:
            return ["\(homeDir)/.gradle/caches"]
        case .maven:
            return ["\(homeDir)/.m2/repository"]
        case .npm:
            return ["\(homeDir)/.npm"]
        case .yarn:
            return ["\(homeDir)/Library/Caches/Yarn"]
        case .pip:
            return ["\(homeDir)/Library/Caches/pip"]
        case .homebrew:
            return ["\(homeDir)/Library/Caches/Homebrew"]
        }
    }
}

/// Represents an AI agent cache location
public struct AIAgentCache: Equatable, Hashable {
    public let agent: AIAgent
    public let cacheLocation: URL
    public let size: Int64
    public let description: String
    
    public init(agent: AIAgent, cacheLocation: URL, size: Int64, description: String) {
        self.agent = agent
        self.cacheLocation = cacheLocation
        self.size = size
        self.description = description
    }
}

/// Supported AI agents for cache management
public enum AIAgent: String, CaseIterable {
    case cursor
    case github_copilot
    case codeium
    case tabnine
    case kiro
    case continue_dev
    case aider
    case openai_cli
    
    public var displayName: String {
        switch self {
        case .cursor: return "Cursor"
        case .github_copilot: return "GitHub Copilot"
        case .codeium: return "Codeium"
        case .tabnine: return "Tabnine"
        case .kiro: return "Kiro"
        case .continue_dev: return "Continue.dev"
        case .aider: return "Aider"
        case .openai_cli: return "OpenAI CLI"
        }
    }
    
    /// Returns the cache directory paths for this agent
    public func cachePaths(homeDir: String) -> [String] {
        switch self {
        case .cursor:
            return [
                "\(homeDir)/Library/Application Support/Cursor/Cache",
                "\(homeDir)/Library/Application Support/Cursor/CachedData",
                "\(homeDir)/Library/Caches/com.todesktop.230313mzl4w4u92"
            ]
        case .github_copilot:
            return [
                "\(homeDir)/Library/Application Support/GitHub Copilot",
                "\(homeDir)/.vscode/extensions/github.copilot-*/dist"
            ]
        case .codeium:
            return [
                "\(homeDir)/Library/Application Support/Codeium",
                "\(homeDir)/.codeium"
            ]
        case .tabnine:
            return [
                "\(homeDir)/Library/Application Support/TabNine",
                "\(homeDir)/.tabnine"
            ]
        case .kiro:
            return [
                "\(homeDir)/.kiro/cache",
                "\(homeDir)/Library/Caches/Kiro"
            ]
        case .continue_dev:
            return ["\(homeDir)/.continue"]
        case .aider:
            return ["\(homeDir)/.aider"]
        case .openai_cli:
            return ["\(homeDir)/.openai"]
        }
    }
}

/// Represents a browser-specific cache location
public struct BrowserCache: Equatable, Hashable {
    public let browser: Browser
    public let cacheLocation: URL
    public let size: Int64
    
    public init(browser: Browser, cacheLocation: URL, size: Int64) {
        self.browser = browser
        self.cacheLocation = cacheLocation
        self.size = size
    }
}

/// Supported browsers for cache management
public enum Browser: String, CaseIterable {
    case safari
    case chrome
    case firefox
    case edge
    
    /// Returns the cache directory path for this browser
    public var cachePath: String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        switch self {
        case .safari:
            return "\(homeDir)/Library/Caches/com.apple.Safari"
        case .chrome:
            return "\(homeDir)/Library/Caches/Google/Chrome"
        case .firefox:
            return "\(homeDir)/Library/Caches/Firefox"
        case .edge:
            return "\(homeDir)/Library/Caches/Microsoft Edge"
        }
    }
}

/// Default implementation of CacheManager
public class DefaultCacheManager: CacheManager {
    private let fileManager = FileManager.default
    private let safeListManager: SafeListManager
    
    public init(safeListManager: SafeListManager = DefaultSafeListManager()) {
        self.safeListManager = safeListManager
    }
    
    /// Find system caches in ~/Library/Caches
    public func findSystemCaches() async -> [FileMetadata] {
        // Use actual home directory, not sandboxed container
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        print("DEBUG CacheManager: NSHomeDirectory = \(NSHomeDirectory())")
        print("DEBUG CacheManager: homeDir = \(homeDir.path)")
        
        let cachesDir = homeDir.appendingPathComponent("Library/Caches")
        
        print("DEBUG CacheManager: Scanning \(cachesDir.path)")
        
        // Return top-level cache directories instead of individual files
        let results = await scanCacheDirectoriesOnly(cachesDir, fileType: .cache)
        print("DEBUG CacheManager: Found \(results.count) cache directories")
        return results
    }
    
    /// Find application-specific caches
    public func findApplicationCaches() async -> [FileMetadata] {
        // This is now redundant with findSystemCaches, return empty array
        return []
    }
    
    /// Find browser-specific caches
    public func findBrowserCaches() async -> [BrowserCache] {
        var browserCaches: [BrowserCache] = []
        let homeDir = NSHomeDirectory()
        
        for browser in Browser.allCases {
            let cachePath = browser.cachePath.replacingOccurrences(of: "~", with: homeDir)
            let cacheURL = URL(fileURLWithPath: cachePath)
            
            // Check if the cache directory exists
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: cachePath, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            // Calculate total size of browser cache
            let size = await calculateDirectorySize(cacheURL)
            
            let browserCache = BrowserCache(
                browser: browser,
                cacheLocation: cacheURL,
                size: size
            )
            browserCaches.append(browserCache)
        }
        
        return browserCaches
    }
    
    /// Find developer tool caches
    public func findDeveloperCaches() async -> [DeveloperCache] {
        var developerCaches: [DeveloperCache] = []
        let homeDir = NSHomeDirectory()
        
        for tool in DeveloperTool.allCases {
            let cachePaths = tool.cachePaths(homeDir: homeDir)
            
            for cachePath in cachePaths {
                // Handle wildcard paths (e.g., AndroidStudio*)
                let expandedPaths = expandWildcardPath(cachePath)
                
                for expandedPath in expandedPaths {
                    let cacheURL = URL(fileURLWithPath: expandedPath)
                    
                    // Check if the cache directory exists
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        continue
                    }
                    
                    // Special handling for AssetsV2 - scan subdirectories
                    if expandedPath.contains("AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime") {
                        do {
                            let contents = try fileManager.contentsOfDirectory(atPath: expandedPath)
                            for item in contents where item.hasSuffix(".asset") {
                                let assetPath = expandedPath + "/" + item
                                let assetURL = URL(fileURLWithPath: assetPath)
                                
                                let size = await calculateDirectorySize(assetURL)
                                guard size > 0 else { continue }
                                
                                var description = "\(tool.displayName) - \(item)"
                                if let version = readSimulatorVersion(at: assetPath) {
                                    description = "\(version) - SimulatorRuntimeAsset"
                                }
                                
                                let developerCache = DeveloperCache(
                                    tool: tool,
                                    cacheLocation: assetURL,
                                    size: size,
                                    description: description
                                )
                                developerCaches.append(developerCache)
                            }
                        } catch {
                            print("Error scanning AssetsV2: \(error)")
                        }
                        continue
                    }
                    
                    // Special handling for CoreSimulator Devices - scan subdirectories
                    if expandedPath.contains("CoreSimulator/Devices") && !expandedPath.contains("Caches") {
                        do {
                            let contents = try fileManager.contentsOfDirectory(atPath: expandedPath)
                            for item in contents where !item.hasPrefix(".") {
                                let devicePath = expandedPath + "/" + item
                                var isDir: ObjCBool = false
                                guard fileManager.fileExists(atPath: devicePath, isDirectory: &isDir), isDir.boolValue else {
                                    continue
                                }
                                
                                let deviceURL = URL(fileURLWithPath: devicePath)
                                let size = await calculateDirectorySize(deviceURL)
                                guard size > 0 else { continue }
                                
                                var description = "Simulator Device - \(item)"
                                if let deviceInfo = readSimulatorDeviceInfo(at: devicePath) {
                                    description = "\(deviceInfo.name) - \(deviceInfo.runtime)"
                                }
                                
                                let developerCache = DeveloperCache(
                                    tool: tool,
                                    cacheLocation: deviceURL,
                                    size: size,
                                    description: description
                                )
                                developerCaches.append(developerCache)
                            }
                        } catch {
                            print("Error scanning Devices: \(error)")
                        }
                        continue
                    }
                    
                    // Calculate total size of cache
                    let size = await calculateDirectorySize(cacheURL)
                    
                    // Skip if empty
                    guard size > 0 else { continue }
                    
                    // Special handling for other simulator runtime assets
                    var description = "\(tool.displayName) - \(cacheURL.lastPathComponent)"
                    if tool == .xcodeSimulators {
                        // Check if this is a simulator runtime directory
                        if let version = readSimulatorVersion(at: expandedPath) {
                            description = "\(version) - SimulatorRuntimeAsset"
                        }
                    }
                    
                    let developerCache = DeveloperCache(
                        tool: tool,
                        cacheLocation: cacheURL,
                        size: size,
                        description: description
                    )
                    developerCaches.append(developerCache)
                }
            }
        }
        
        return developerCaches
    }
    
    /// Find AI agent caches
    public func findAIAgentCaches() async -> [AIAgentCache] {
        var agentCaches: [AIAgentCache] = []
        let homeDir = NSHomeDirectory()
        
        for agent in AIAgent.allCases {
            let cachePaths = agent.cachePaths(homeDir: homeDir)
            
            for cachePath in cachePaths {
                // Handle wildcard paths
                let expandedPaths = expandWildcardPath(cachePath)
                
                for expandedPath in expandedPaths {
                    let cacheURL = URL(fileURLWithPath: expandedPath)
                    
                    // Check if the cache directory exists
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
                          isDirectory.boolValue else {
                        continue
                    }
                    
                    // Calculate total size of cache
                    let size = await calculateDirectorySize(cacheURL)
                    
                    // Skip if empty
                    guard size > 0 else { continue }
                    
                    let description = "\(agent.displayName) - \(cacheURL.lastPathComponent)"
                    let agentCache = AIAgentCache(
                        agent: agent,
                        cacheLocation: cacheURL,
                        size: size,
                        description: description
                    )
                    agentCaches.append(agentCache)
                }
            }
        }
        
        return agentCaches
    }
    
    /// Clear specified cache files
    public func clearCaches(caches: [FileMetadata]) async throws -> CleanupResult {
        var filesRemoved = 0
        var spaceFreed: Int64 = 0
        var errors: [CleanupError] = []
        
        for cache in caches {
            // Validate against safe-list
            if safeListManager.isProtected(url: cache.url) {
                errors.append(.fileProtected(path: cache.url.path))
                continue
            }
            
            // Check if file is in use
            if cache.isInUse {
                errors.append(.fileInUse(path: cache.url.path))
                continue
            }
            
            // Attempt to remove the file
            do {
                try fileManager.removeItem(at: cache.url)
                filesRemoved += 1
                spaceFreed += cache.size
            } catch {
                errors.append(.unknown(error.localizedDescription))
            }
        }
        
        return CleanupResult(
            filesRemoved: filesRemoved,
            spaceFreed: spaceFreed,
            errors: errors,
            backupLocation: nil
        )
    }
    
    // MARK: - Private Helper Methods
    
    /// Expand wildcard paths (e.g., AndroidStudio* -> AndroidStudio2023.1, AndroidStudio2023.2)
    private func expandWildcardPath(_ path: String) -> [String] {
        // Check if path contains wildcard
        guard path.contains("*") else {
            return [path]
        }
        
        // Split path into directory and pattern
        let pathComponents = (path as NSString).pathComponents
        var expandedPaths: [String] = []
        
        // Find the component with wildcard
        var baseComponents: [String] = []
        var wildcardComponent: String?
        var remainingComponents: [String] = []
        var foundWildcard = false
        
        for component in pathComponents {
            if component.contains("*") && !foundWildcard {
                wildcardComponent = component
                foundWildcard = true
            } else if foundWildcard {
                remainingComponents.append(component)
            } else {
                baseComponents.append(component)
            }
        }
        
        guard let wildcardPattern = wildcardComponent else {
            return [path]
        }
        
        // Build base directory path
        let basePath = NSString.path(withComponents: baseComponents)
        
        // List directory contents
        guard let contents = try? fileManager.contentsOfDirectory(atPath: basePath) else {
            return []
        }
        
        // Convert wildcard pattern to regex
        let regexPattern = wildcardPattern
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".")
        
        guard let regex = try? NSRegularExpression(pattern: "^" + regexPattern + "$") else {
            return []
        }
        
        // Match contents against pattern
        for item in contents {
            let range = NSRange(item.startIndex..<item.endIndex, in: item)
            if regex.firstMatch(in: item, range: range) != nil {
                var matchedComponents = baseComponents + [item] + remainingComponents
                let matchedPath = NSString.path(withComponents: matchedComponents)
                expandedPaths.append(matchedPath)
            }
        }
        
        return expandedPaths
    }
    
    /// Scan a cache directory and return file metadata
    private func scanCacheDirectory(_ directory: URL, fileType: FileType) async -> [FileMetadata] {
        var cacheFiles: [FileMetadata] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return cacheFiles
        }
        
        for case let fileURL as URL in enumerator {
            // Skip if protected by safe-list
            if safeListManager.isProtected(url: fileURL) {
                continue
            }
            
            // Skip directories, only process files
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            
            // Get file attributes
            guard let metadata = getFileMetadata(url: fileURL, fileType: fileType) else {
                continue
            }
            
            cacheFiles.append(metadata)
        }
        
        return cacheFiles
    }
    
    /// Scan cache directory and return only top-level directories as single items
    private func scanCacheDirectoriesOnly(_ directory: URL, fileType: FileType) async -> [FileMetadata] {
        var cacheDirectories: [FileMetadata] = []
        
        print("DEBUG scanCacheDirectoriesOnly: Starting scan of \(directory.path)")
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("DEBUG scanCacheDirectoriesOnly: Failed to read directory")
            return cacheDirectories
        }
        
        print("DEBUG scanCacheDirectoriesOnly: Found \(contents.count) items")
        
        for itemURL in contents {
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                print("DEBUG scanCacheDirectoriesOnly: Skipping \(itemURL.lastPathComponent) - not a directory")
                continue
            }
            
            // Skip if protected by safe-list
            if safeListManager.isProtected(url: itemURL) {
                print("DEBUG scanCacheDirectoriesOnly: Skipping \(itemURL.lastPathComponent) - protected")
                continue
            }
            
            print("DEBUG scanCacheDirectoriesOnly: Calculating size for \(itemURL.lastPathComponent)")
            
            // Calculate total size of this cache directory
            let size = await calculateDirectorySize(itemURL)
            
            print("DEBUG scanCacheDirectoriesOnly: \(itemURL.lastPathComponent) size = \(size)")
            
            // Skip empty directories
            guard size > 0 else { 
                print("DEBUG scanCacheDirectoriesOnly: Skipping \(itemURL.lastPathComponent) - empty")
                continue 
            }
            
            // Get directory attributes
            do {
                let attributes = try fileManager.attributesOfItem(atPath: itemURL.path)
                let createdDate = attributes[.creationDate] as? Date ?? Date()
                let modifiedDate = attributes[.modificationDate] as? Date ?? Date()
                
                // Get access date using stat
                var accessedDate = Date()
                var fileStat = stat()
                if stat(itemURL.path, &fileStat) == 0 {
                    accessedDate = Date(timeIntervalSince1970: TimeInterval(fileStat.st_atimespec.tv_sec))
                }
                
                let permissions = FilePermissions(
                    isReadable: fileManager.isReadableFile(atPath: itemURL.path),
                    isWritable: fileManager.isWritableFile(atPath: itemURL.path),
                    isDeletable: fileManager.isDeletableFile(atPath: itemURL.path)
                )
                
                let metadata = FileMetadata(
                    url: itemURL,
                    size: size,
                    createdDate: createdDate,
                    modifiedDate: modifiedDate,
                    accessedDate: accessedDate,
                    fileType: fileType,
                    isInUse: false,
                    permissions: permissions
                )
                
                cacheDirectories.append(metadata)
            } catch {
                continue
            }
        }
        
        return cacheDirectories
    }
    
    /// Get metadata for a specific file
    private func getFileMetadata(url: URL, fileType: FileType) -> FileMetadata? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            
            let size = attributes[.size] as? Int64 ?? 0
            let createdDate = attributes[.creationDate] as? Date ?? Date()
            let modifiedDate = attributes[.modificationDate] as? Date ?? Date()
            
            // Get access date using stat
            var accessedDate = Date()
            var fileStat = stat()
            if stat(url.path, &fileStat) == 0 {
                accessedDate = Date(timeIntervalSince1970: TimeInterval(fileStat.st_atimespec.tv_sec))
            }
            
            let permissions = FilePermissions(
                isReadable: fileManager.isReadableFile(atPath: url.path),
                isWritable: fileManager.isWritableFile(atPath: url.path),
                isDeletable: fileManager.isDeletableFile(atPath: url.path)
            )
            
            return FileMetadata(
                url: url,
                size: size,
                createdDate: createdDate,
                modifiedDate: modifiedDate,
                accessedDate: accessedDate,
                fileType: fileType,
                isInUse: false,
                permissions: permissions
            )
        } catch {
            return nil
        }
    }
    
    /// Calculate total size of a directory
    private func calculateDirectorySize(_ directory: URL) async -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return totalSize
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            } catch {
                // Skip files we can't read
                continue
            }
        }
        
        return totalSize
    }
    
    /// Read simulator version from .asset plist
    private func readSimulatorVersion(at path: String) -> String? {
        let plistPath = path + "/Info.plist"
        
        guard fileManager.fileExists(atPath: plistPath),
              let plistData = fileManager.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }
        
        // Get SimulatorVersion from MobileAssetProperties
        if let mobileAssetProps = plist["MobileAssetProperties"] as? [String: Any],
           let version = mobileAssetProps["SimulatorVersion"] as? String {
            return version
        }
        
        return nil
    }
    
    /// Read simulator device info from device.plist
    private func readSimulatorDeviceInfo(at path: String) -> (name: String, runtime: String)? {
        let plistPath = path + "/device.plist"
        
        guard fileManager.fileExists(atPath: plistPath),
              let plistData = fileManager.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }
        
        let name = plist["name"] as? String ?? "Unknown Device"
        let runtime = plist["runtime"] as? String ?? "Unknown Runtime"
        
        // Clean up runtime string (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-18-2" -> "iOS 18.2")
        let cleanRuntime = runtime
            .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            .replacingOccurrences(of: "-", with: " ")
        
        return (name: name, runtime: cleanRuntime)
    }
}

/// Result of a cleanup operation
public struct CleanupResult: Equatable {
    public let filesRemoved: Int
    public let spaceFreed: Int64
    public let errors: [CleanupError]
    public let backupLocation: URL?
    
    public init(filesRemoved: Int, spaceFreed: Int64, errors: [CleanupError], backupLocation: URL?) {
        self.filesRemoved = filesRemoved
        self.spaceFreed = spaceFreed
        self.errors = errors
        self.backupLocation = backupLocation
    }
}
