import XCTest
@testable import MacStorageCleanupCore

/// Covers the rules that decide what starts out checked, and the mapping from a path to
/// the tool command that owns it.
final class DeveloperCacheSafetyTests: XCTestCase {
    private func makeCache(
        tool: DeveloperTool = .androidNDK,
        safety: CacheSafety,
        isNewestVersion: Bool = true,
        referencedBy: [URL] = []
    ) -> DeveloperCache {
        DeveloperCache(
            tool: tool,
            cacheLocation: URL(fileURLWithPath: "/tmp/example"),
            size: 1024,
            description: "example",
            isNewestVersion: isNewestVersion,
            referencedBy: referencedBy,
            safety: safety
        )
    }

    // MARK: - Default selection

    func testAlwaysSafeIsSelectedByDefault() {
        XCTAssertTrue(makeCache(safety: .alwaysSafe).isDefaultSelected)
    }

    func testNewestRegeneratingVersionIsNotSelected() {
        XCTAssertFalse(makeCache(safety: .regenerates, isNewestVersion: true).isDefaultSelected)
    }

    func testSupersededUnreferencedVersionIsSelected() {
        XCTAssertTrue(makeCache(safety: .regenerates, isNewestVersion: false).isDefaultSelected)
    }

    /// A project can pin an old NDK and never touch it, so a reference outranks age.
    func testSupersededButReferencedVersionIsNotSelected() {
        let cache = makeCache(
            safety: .regenerates,
            isNewestVersion: false,
            referencedBy: [URL(fileURLWithPath: "/Users/someone/app/build.gradle")]
        )

        XCTAssertFalse(cache.isDefaultSelected)
    }

    func testNeedsConfirmationIsNeverSelected() {
        XCTAssertFalse(makeCache(safety: .needsConfirmation, isNewestVersion: false).isDefaultSelected)
    }

    // MARK: - Grouping

    func testGroupLabelFallsBackToToolDisplayName() {
        XCTAssertEqual(makeCache(safety: .alwaysSafe).groupLabel, DeveloperTool.androidNDK.displayName)
    }

    func testGroupHintOverridesToolDisplayName() {
        let cache = DeveloperCache(
            tool: .electronAppData,
            cacheLocation: URL(fileURLWithPath: "/tmp/example"),
            size: 1024,
            description: "example",
            groupHint: "Claude"
        )

        XCTAssertEqual(cache.groupLabel, "Claude")
    }

    // MARK: - Scanner ownership

    func testScannerOwnedToolsAreExcludedFromTheGenericLoop() {
        XCTAssertTrue(DeveloperTool.androidNDK.isScannerOwned)
        XCTAssertTrue(DeveloperTool.gradle.isScannerOwned)
        XCTAssertTrue(DeveloperTool.simulatorRuntimeVolumes.isScannerOwned)
        XCTAssertFalse(DeveloperTool.npm.isScannerOwned)
        XCTAssertFalse(DeveloperTool.xcodeDerivedData.isScannerOwned)
    }

    /// The mounted runtime volumes must not also appear as a plain path, or their bytes
    /// are counted twice.
    func testSimulatorPathsDoNotIncludeTheMountedVolumes() {
        let paths = DeveloperTool.xcodeSimulators.cachePaths(homeDir: "/Users/test")
        XCTAssertFalse(paths.contains("/Library/Developer/CoreSimulator/Volumes"))
    }

    func testAndroidSDKRootHonorsEnvironmentOverride() {
        // Without a real SDK on disk the resolver filters everything out, which is the
        // correct behaviour — it only ever returns roots that exist.
        let roots = DeveloperTool.androidSDKRoots(homeDir: "/nonexistent-home")
        XCTAssertTrue(roots.allSatisfy { FileManager.default.fileExists(atPath: $0) })
    }

    // MARK: - Scan separation

    /// Chromium app caches must survive the developer toggle being off: for most users
    /// that is where their reclaimable space actually is.
    func testApplicationDataCachesAreSeparateFromDeveloperCaches() async {
        let manager = DefaultCacheManager()

        let appData = await manager.findApplicationDataCaches()
        let developer = await manager.findDeveloperCaches()

        XCTAssertTrue(appData.allSatisfy { $0.tool == .electronAppData })
        XCTAssertTrue(developer.allSatisfy { $0.tool != .electronAppData })

        // The two sweeps can legitimately claim the same path — `Code/CachedData` is both
        // a VS Code tool path and a Chromium cache subpath. That overlap is resolved where
        // the rows are merged, in favour of the developer row, so the scans themselves are
        // allowed to be greedy. What must hold is that neither scan reports a path twice.
        XCTAssertEqual(Set(appData.map(\.cacheLocation.path)).count, appData.count)
        XCTAssertEqual(Set(developer.map(\.cacheLocation.path)).count, developer.count)
    }

    // MARK: - Tool-owned reclaim

    private func makeEngine() -> DefaultCleanupEngine {
        DefaultCleanupEngine(
            safeListManager: DefaultSafeListManager(),
            backupManager: DefaultBackupManager()
        )
    }

    func testSimulatorDeviceUsesSimctlDelete() {
        let uuid = UUID().uuidString
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/\(uuid)")

        let reclaim = makeEngine().toolReclaimCommand(for: url)

        XCTAssertEqual(reclaim?.executable, "/usr/bin/xcrun")
        XCTAssertEqual(reclaim?.arguments, ["simctl", "delete", uuid])
    }

    func testSimulatorRuntimeVolumeUsesRuntimeDeleteAndForbidsDirectRemoval() {
        let url = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes/iOS_23F77")

        let reclaim = makeEngine().toolReclaimCommand(for: url)

        XCTAssertEqual(reclaim?.arguments, ["simctl", "runtime", "delete", "23F77"])
        // Never `rm` a mount point — unmounting is simctl's job.
        XCTAssertEqual(reclaim?.allowsDirectRemovalFallback, false)
    }

    func testUnrelatedPathHasNoToolCommand() {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Caches/com.apple.dt.Xcode")
        XCTAssertNil(makeEngine().toolReclaimCommand(for: url))
    }

    func testDeviceDirectoryThatIsNotAUUIDIsNotTreatedAsADevice() {
        let url = URL(fileURLWithPath: "\(NSHomeDirectory())/Library/Developer/CoreSimulator/Devices/README")
        XCTAssertNil(makeEngine().toolReclaimCommand(for: url))
    }
}
