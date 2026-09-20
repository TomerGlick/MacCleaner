// swift-tools-version: 5.9
import PackageDescription

let coreSources = [
    "ApplicationManager.swift",
    "BackupManager.swift",
    "CacheManager.swift",
    "CleanupCategorizer.swift",
    "CleanupEngine.swift",
    "DeveloperCacheScanner.swift",
    "DirectorySizer.swift",
    "ProjectArtifactScanner.swift",
    "ProjectReferenceIndex.swift",
    "FileScanner.swift",
    "PreferencesStore.swift",
    "SafeListManager.swift",
    "ScheduledCleanupCoordinator.swift",
    "StorageAnalyzer.swift",
    "Models/Application.swift",
    "Models/AnalysisResult.swift",
    "Models/Backup.swift",
    "Models/CleanupCategory.swift",
    "Models/DownloadsFileType.swift",
    "Models/Errors.swift",
    "Models/FileMetadata.swift",
    "Models/LogFileInfo.swift",
    "Models/ScanResult.swift",
    "Models/UserPreferences.swift",
    "Utilities/FileChecksum.swift"
]

let package = Package(
    name: "MacStorageCleanup",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacStorageCleanup",
            targets: ["MacStorageCleanup"]
        ),
        .library(
            name: "MacStorageCleanupCore",
            targets: ["MacStorageCleanupCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "MacStorageCleanupCore",
            dependencies: [],
            path: "Sources",
            exclude: ["main.swift"],
            sources: coreSources
        ),
        .executableTarget(
            name: "MacStorageCleanup",
            dependencies: ["MacStorageCleanupCore"],
            path: "Sources",
            exclude: coreSources,
            sources: ["main.swift"]
        ),
        .testTarget(
            name: "MacStorageCleanupTests",
            dependencies: [
                "MacStorageCleanupCore",
                "SwiftCheck"
            ],
            path: "Tests"
        )
    ]
)
