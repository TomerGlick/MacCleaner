import XCTest
@testable import MacStorageCleanupCore

final class ProjectArtifactScannerTests: XCTestCase {
    var tempDirectory: URL!
    var scanner: ProjectArtifactScanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scanner = ProjectArtifactScanner(sizer: DirectorySizer())
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectArtifactScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        scanner = nil
        try super.tearDownWithError()
    }

    private func makeFile(_ relativePath: String, bytes: Int = 4096) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: bytes).write(to: url)
    }

    func testFindsGradleBuildOutputBesideABuildScript() throws {
        try makeFile("MyApp/build.gradle.kts", bytes: 64)
        try makeFile("MyApp/build/classes/output.bin")

        let results = scanner.scan(root: tempDirectory)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.tool, .projectBuildArtifacts)
        XCTAssertEqual(results.first?.cacheLocation.lastPathComponent, "build")
    }

    /// The guard that matters most: a folder named `build` full of the user's own work,
    /// with no project file beside it, must never be offered.
    func testIgnoresBuildFolderWithoutAProjectMarker() throws {
        try makeFile("Photos/build/holiday.bin")

        XCTAssertTrue(scanner.scan(root: tempDirectory).isEmpty)
    }

    func testNodeModulesRequiresPackageJSON() throws {
        try makeFile("WithMarker/package.json", bytes: 32)
        try makeFile("WithMarker/node_modules/left-pad/index.bin")
        try makeFile("NoMarker/node_modules/left-pad/index.bin")

        let results = scanner.scan(root: tempDirectory)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].cacheLocation.path.contains("WithMarker"))
    }

    func testPodsRequirePodfileLock() throws {
        try makeFile("App/Podfile.lock", bytes: 32)
        try makeFile("App/Pods/SomePod/lib.bin")

        let results = scanner.scan(root: tempDirectory)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.cacheLocation.lastPathComponent, "Pods")
    }

    func testDoesNotFollowSymlinksOutOfTheChosenRoot() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: outside.appendingPathComponent("Escaped/build"),
            withIntermediateDirectories: true
        )
        try Data(count: 4096).write(to: outside.appendingPathComponent("Escaped/build/out.bin"))
        try "".write(to: outside.appendingPathComponent("Escaped/build.gradle"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }

        try FileManager.default.createSymbolicLink(
            at: tempDirectory.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        XCTAssertTrue(scanner.scan(root: tempDirectory).isEmpty)
    }

    func testEmptyArtifactDirectoryProducesNoRow() throws {
        try makeFile("MyApp/build.gradle", bytes: 64)
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("MyApp/build"),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(scanner.scan(root: tempDirectory).isEmpty)
    }

    /// Build output costs a cold rebuild, so it is offered but never pre-ticked —
    /// the group checkbox in the list is how a user takes all of it at once.
    func testBuildOutputIsNotCheckedByDefault() throws {
        try makeFile("MyApp/build.gradle.kts", bytes: 64)
        try makeFile("MyApp/build/classes/output.bin")

        let results = scanner.scan(root: tempDirectory)

        XCTAssertEqual(results.first?.safety, .regenerates)
        XCTAssertFalse(results.first?.isDefaultSelected == true)
    }

    /// `xcuserdata` holds breakpoints and user-scoped schemes — env vars, launch
    /// arguments, test config — which do not regenerate and are gitignored, so there is
    /// no second copy. It must never be pre-ticked.
    func testXcuserdataIsNeverPreTicked() throws {
        try makeFile("App/.git/HEAD", bytes: 16)
        try makeFile("App/App.xcodeproj/xcuserdata/tomer.xcuserdatad/xcschemes/App.xcscheme")

        let results = scanner.scan(root: tempDirectory)

        XCTAssertEqual(results.first?.safety, .needsConfirmation)
        XCTAssertFalse(results.first?.isDefaultSelected == true)
    }

    /// Guards the promise `.alwaysSafe` makes: nothing is lost and nothing is re-fetched.
    /// Anything that costs a download or holds user config belongs in another tier.
    func testOnlyScratchDirectoriesClaimAlwaysSafe() {
        let alwaysSafe = ProjectArtifactScanner.artifacts
            .filter { $0.safety == .alwaysSafe }
            .map(\.directoryName)

        XCTAssertEqual(Set(alwaysSafe), [".gradle", ".kotlin"])
    }
}
