import Foundation
import os.log

/// Protocol for managing cache file identification and operations
public protocol CacheManager: AnyObject {
    /// Roots for the opt-in per-project build artifact scan. Empty disables it.
    ///
    /// This is the only scan that walks the user's own source tree, so it never runs
    /// against a default location — the user names the roots.
    var projectScanRoots: [URL] { get set }

    func findSystemCaches() async -> [FileMetadata]
    func findApplicationCaches() async -> [FileMetadata]
    func findBrowserCaches() async -> [BrowserCache]
    func findDeveloperCaches() async -> [DeveloperCache]

    /// Chromium/Electron caches under `~/Library/Application Support`, for every app.
    ///
    /// Separate from `findDeveloperCaches()` on purpose: these rows are Chrome, Slack and
    /// Spotify as much as they are Claude or VS Code, so they must not disappear when a
    /// user turns developer cache scanning off.
    func findApplicationDataCaches() async -> [DeveloperCache]

    func findAIAgentCaches() async -> [AIAgentCache]
    func clearCaches(caches: [FileMetadata]) async throws -> CleanupResult
}

/// Whether reclaiming a cache needs administrator rights.
public enum CacheScope: String, Equatable, Hashable, Sendable {
    case user
    case system
}

/// How risky it is to delete a cache entry.
public enum CacheSafety: String, Equatable, Hashable, Sendable {
    /// Scratch data. Nothing is lost and nothing is re-downloaded.
    case alwaysSafe
    /// The tool rebuilds or re-downloads this on next use. Costs time, not work.
    case regenerates
    /// Could break a build or lose a device definition. Never selected by default.
    case needsConfirmation
}

/// How to reclaim a cache. Tool-owned caches must go through the tool's own command so
/// its internal index stays consistent; `rm -rf` leaves phantom entries that the IDE
/// then re-creates or errors on.
public enum ReclaimMethod: Equatable, Hashable, Sendable {
    case removeItem
    case command(String, [String])
}

/// Represents a developer tool cache location
public struct DeveloperCache: Equatable, Hashable {
    public let tool: DeveloperTool
    public let cacheLocation: URL
    public let size: Int64
    public let description: String

    /// Human-readable label — "iPhone 17 Pro · iOS 26.5", never a bare UUID.
    public let displayName: String
    /// Version this entry belongs to, when the tool keeps one directory per version.
    public let version: String?
    /// False marks a superseded version, which is what makes multi-version accumulation
    /// visible instead of hiding it behind one total per tool.
    public let isNewestVersion: Bool
    /// Project files that pin this version. Non-empty means "do not offer for deletion".
    public let referencedBy: [URL]
    public let scope: CacheScope
    public let reclaimMethod: ReclaimMethod
    public let safety: CacheSafety
    public let measurement: SizeMeasurement
    /// The size is understated because the path is TCC-protected.
    public let needsFullDiskAccess: Bool
    /// UI grouping label. Falls back to the tool's display name when nil — set it when a
    /// tool produces rows that belong under a finer heading ("Claude", "Android SDK").
    public let groupHint: String?
    public init(
        tool: DeveloperTool,
        cacheLocation: URL,
        size: Int64,
        description: String,
        displayName: String? = nil,
        version: String? = nil,
        isNewestVersion: Bool = true,
        referencedBy: [URL] = [],
        scope: CacheScope = .user,
        reclaimMethod: ReclaimMethod = .removeItem,
        safety: CacheSafety = .regenerates,
        measurement: SizeMeasurement = .enumerated,
        needsFullDiskAccess: Bool = false,
        groupHint: String? = nil
    ) {
        self.tool = tool
        self.cacheLocation = cacheLocation
        self.size = size
        self.description = description
        self.displayName = displayName ?? description
        self.version = version
        self.isNewestVersion = isNewestVersion
        self.referencedBy = referencedBy
        self.scope = scope
        self.reclaimMethod = reclaimMethod
        self.safety = safety
        self.measurement = measurement
        self.needsFullDiskAccess = needsFullDiskAccess
        self.groupHint = groupHint
    }

    /// Heading this row belongs under in the candidates list.
    public var groupLabel: String {
        groupHint ?? tool.displayName
    }

    /// Whether this entry should start out checked in the UI.
    ///
    /// Always-safe scratch data, plus superseded versions that no project pins.
    /// Everything else is left for the user to opt into deliberately.
    public var isDefaultSelected: Bool {
        switch safety {
        case .alwaysSafe:
            return true
        case .regenerates:
            return !isNewestVersion && referencedBy.isEmpty
        case .needsConfirmation:
            return false
        }
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
    case uv
    case homebrew
    // Multi-version toolchains and per-item rows produced by `DeveloperCacheScanner`.
    case simulatorRuntimeVolumes
    case androidNDK
    case androidSystemImages
    case androidBuildTools
    case androidPlatforms
    case androidSources
    case androidExtras
    case androidAVD
    case gradleWrapperDists
    case gradleScratch
    case gradleToolchains
    case kotlinNative
    case xcodeCodingAssistant
    case xcodeProducts
    case electronAppData
    case commandLineTools
    case localSnapshots
    case projectBuildArtifacts

    public var displayName: String {
        switch self {
        case .xcode: return "Xcode Caches"
        case .xcodeSimulators: return "Xcode Simulators"
        case .xcodeDerivedData: return "Xcode DerivedData"
        case .xcodeArchives: return "Xcode Archives"
        case .xcodeDeviceSupport: return "iOS Device Support"
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
        case .uv: return "uv (Python)"
        case .homebrew: return "Homebrew"
        case .simulatorRuntimeVolumes: return "Simulator Runtimes"
        case .androidNDK: return "Android NDK"
        case .androidSystemImages: return "Android System Images"
        case .androidBuildTools: return "Android Build Tools"
        case .androidPlatforms: return "Android Platforms"
        case .androidSources: return "Android Sources"
        case .androidExtras: return "Android SDK Extras"
        case .androidAVD: return "Android Emulators (AVD)"
        case .gradleWrapperDists: return "Gradle Distributions"
        case .gradleScratch: return "Gradle Scratch Data"
        case .gradleToolchains: return "Gradle Toolchain JDKs"
        case .kotlinNative: return "Kotlin/Native"
        case .xcodeCodingAssistant: return "Xcode Coding Assistant"
        case .xcodeProducts: return "Xcode Products"
        case .electronAppData: return "App Caches (Electron)"
        case .commandLineTools: return "Command Line Tools"
        case .localSnapshots: return "APFS Local Snapshots"
        case .projectBuildArtifacts: return "Project Build Artifacts"
        }
    }

    /// Tools whose entries are produced by `DeveloperCacheScanner` rather than by the
    /// generic path loop, because they need per-version rows, `statfs` sizing, or a
    /// tool-specific listing command.
    public var isScannerOwned: Bool {
        switch self {
        case .simulatorRuntimeVolumes, .androidNDK, .androidSystemImages, .androidBuildTools,
             .androidPlatforms, .androidSources, .androidExtras, .androidAVD,
             .gradle, .gradleWrapperDists, .gradleScratch, .gradleToolchains,
             .kotlinNative, .xcodeDeviceSupport, .xcodeCodingAssistant, .xcodeProducts,
             .electronAppData, .commandLineTools, .localSnapshots, .projectBuildArtifacts:
            return true
        default:
            return false
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
                // /Library/Developer/CoreSimulator/Volumes is deliberately absent: those are
                // mounted APFS volumes that `DeveloperCacheScanner` sizes via statfs.
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
        case .uv:
            // uv defaults to $XDG_CACHE_HOME/uv (i.e. ~/.cache/uv), overridable via UV_CACHE_DIR.
            let env = ProcessInfo.processInfo.environment
            if let explicit = env["UV_CACHE_DIR"], !explicit.isEmpty {
                return [(explicit as NSString).expandingTildeInPath]
            }
            var paths = ["\(homeDir)/.cache/uv"]
            if let xdg = env["XDG_CACHE_HOME"], !xdg.isEmpty {
                let xdgPath = ((xdg as NSString).expandingTildeInPath as NSString)
                    .appendingPathComponent("uv")
                if !paths.contains(xdgPath) {
                    paths.insert(xdgPath, at: 0)
                }
            }
            return paths
        case .homebrew:
            return ["\(homeDir)/Library/Caches/Homebrew"]

        // Scanner-owned roots. Listed so the paths live in one place, but the generic
        // loop in `findDeveloperCaches()` skips them (see `isScannerOwned`).
        case .simulatorRuntimeVolumes:
            return ["/Library/Developer/CoreSimulator/Volumes"]
        case .androidNDK:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/ndk" }
        case .androidSystemImages:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/system-images" }
        case .androidBuildTools:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/build-tools" }
        case .androidPlatforms:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/platforms" }
        case .androidSources:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/sources" }
        case .androidExtras:
            return DeveloperTool.androidSDKRoots(homeDir: homeDir).map { "\($0)/extras" }
        case .androidAVD:
            return ["\(homeDir)/.android/avd"]
        case .gradleWrapperDists:
            return ["\(homeDir)/.gradle/wrapper/dists"]
        case .gradleScratch:
            return [
                "\(homeDir)/.gradle/.tmp",
                "\(homeDir)/.gradle/daemon",
                "\(homeDir)/.gradle/native",
                "\(homeDir)/.gradle/nodejs",
                "\(homeDir)/.gradle/yarn"
            ]
        case .gradleToolchains:
            return ["\(homeDir)/.gradle/jdks"]
        case .kotlinNative:
            return ["\(homeDir)/.konan"]
        case .xcodeCodingAssistant:
            return ["\(homeDir)/Library/Developer/Xcode/CodingAssistant"]
        case .xcodeProducts:
            return ["\(homeDir)/Library/Developer/Xcode/Products"]
        case .electronAppData:
            return ["\(homeDir)/Library/Application Support"]
        case .commandLineTools:
            return ["/Library/Developer/CommandLineTools"]
        case .localSnapshots:
            return []
        case .projectBuildArtifacts:
            return []
        }
    }

    /// Resolve the Android SDK location. The path is not fixed — respect the
    /// environment before falling back to the default install location.
    public static func androidSDKRoots(homeDir: String = NSHomeDirectory()) -> [String] {
        let env = ProcessInfo.processInfo.environment
        var roots: [String] = []

        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let value = env[key], !value.isEmpty {
                let expanded = (value as NSString).expandingTildeInPath
                if !roots.contains(expanded) {
                    roots.append(expanded)
                }
            }
        }

        let defaultRoot = "\(homeDir)/Library/Android/sdk"
        if !roots.contains(defaultRoot) {
            roots.append(defaultRoot)
        }

        return roots.filter { FileManager.default.fileExists(atPath: $0) }
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
    private let logger = Logger(subsystem: "com.macstoragecleanup.core", category: "cache")
    let sizer: DirectorySizer
    /// Optional roots for the opt-in per-project build artifact scan. Empty disables it.
    public var projectScanRoots: [URL] = []

    public init(safeListManager: SafeListManager = DefaultSafeListManager(), sizer: DirectorySizer = DirectorySizer()) {
        self.safeListManager = safeListManager
        self.sizer = sizer
    }
    
    /// Find system caches in ~/Library/Caches
    public func findSystemCaches() async -> [FileMetadata] {
        // Use actual home directory, not sandboxed container
        let homeDir = URL(fileURLWithPath: NSHomeDirectory())
        
        let cachesDir = homeDir.appendingPathComponent("Library/Caches")
        logger.debug("Scanning system cache directory at \(cachesDir.path, privacy: .public)")
        
        // Return top-level cache directories instead of individual files
        let results = await scanCacheDirectoriesOnly(cachesDir, fileType: .cache)
        logger.debug("Found \(results.count, privacy: .public) top-level cache directories")
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

        for tool in DeveloperTool.allCases where !tool.isScannerOwned {
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
                            logger.error("Error scanning AssetsV2 runtime assets: \(error.localizedDescription, privacy: .public)")
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
                            logger.error("Error scanning CoreSimulator devices: \(error.localizedDescription, privacy: .public)")
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

        // Multi-version toolchains, mounted runtimes and per-item rows. These need
        // version grouping, statfs sizing or a tool listing command, none of which the
        // generic path loop above can express.
        developerCaches.append(contentsOf: await makeScanner().scan())

        return developerCaches
    }

    /// Find Chromium/Electron caches for every app under Application Support
    public func findApplicationDataCaches() async -> [DeveloperCache] {
        await makeScanner().scanApplicationData()
    }

    private func makeScanner() -> DeveloperCacheScanner {
        DeveloperCacheScanner(
            sizer: sizer,
            homeDir: NSHomeDirectory(),
            projectScanRoots: projectScanRoots
        )
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
                let matchedComponents = baseComponents + [item] + remainingComponents
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
        
        while let fileURL = enumerator.nextObject() as? URL {
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
        logger.debug("Scanning top-level cache directories in \(directory.path, privacy: .public)")
        
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            logger.warning("Failed to read cache directory \(directory.path, privacy: .public)")
            return cacheDirectories
        }
        logger.debug("Found \(contents.count, privacy: .public) items while scanning \(directory.lastPathComponent, privacy: .public)")
        
        for itemURL in contents {
            // Check if it's a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            // Skip if protected by safe-list
            if safeListManager.isProtected(url: itemURL) {
                continue
            }
            
            // Calculate total size of this cache directory
            let size = await calculateDirectorySize(itemURL)
            
            // Skip empty directories
            guard size > 0 else {
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
    
    /// Measure a directory, reporting allocated size plus how it was obtained.
    ///
    /// Hidden entries are included and mount points are answered from `statfs`, so this
    /// is both more accurate and dramatically faster than the recursive `attributesOfItem`
    /// walk it replaces.
    func measure(_ directory: URL) -> DirectorySize {
        sizer.size(of: directory)
    }

    /// Calculate total size of a directory
    private func calculateDirectorySize(_ directory: URL) async -> Int64 {
        measure(directory).bytes
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
