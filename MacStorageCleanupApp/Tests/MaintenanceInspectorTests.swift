import XCTest
import MacStorageCleanupCore
@testable import MacStorageCleanupApp

/// The inspector only reads, so these tests run it against a fabricated home directory and
/// assert on what it reports. Nothing here deletes anything, which is the point of having
/// inspection be a separate type from the service that acts on it.
final class MaintenanceInspectorTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaintenanceInspectorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        home = nil
        try super.tearDownWithError()
    }

    private var inspector: MaintenanceInspector {
        MaintenanceInspector(
            home: home,
            sizer: DirectorySizer(),
            cutoff: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60),
            limit: 1000
        )
    }

    @discardableResult
    private func makeDirectory(_ relativePath: String, modified: Date? = nil) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1024).write(to: url.appendingPathComponent("payload.bin"))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    private func write(_ data: Data, to relativePath: String) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
        return url
    }

    @discardableResult
    private func writePlist(_ contents: [String: Any], to relativePath: String) throws -> URL {
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
        return try write(data, to: relativePath)
    }

    private var longAgo: Date { Date(timeIntervalSinceNow: -400 * 24 * 60 * 60) }

    // MARK: - Saved window state

    func testReportsOnlyStaleSavedState() throws {
        try makeDirectory("Library/Saved Application State/com.acme.Old.savedState", modified: longAgo)
        try makeDirectory("Library/Saved Application State/com.acme.Recent.savedState", modified: Date())

        let report = inspector.savedApplicationState()

        XCTAssertEqual(report.itemCount, 1)
        XCTAssertEqual(report.findings.first?.label, "com.acme.Old")
        XCTAssertGreaterThan(report.reclaimableBytes, 0)
    }

    func testSavedStateIsEmptyWhenTheFolderDoesNotExist() {
        XCTAssertTrue(inspector.savedApplicationState().isEmpty)
        XCTAssertNotNil(inspector.savedApplicationState().note)
    }

    // MARK: - Launch agents

    func testReportsLaunchAgentWhoseProgramIsMissing() throws {
        try writePlist(
            ["Label": "com.acme.agent", "Program": "/nowhere/acme-agent"],
            to: "Library/LaunchAgents/com.acme.agent.plist"
        )

        let report = inspector.brokenLaunchAgents()

        XCTAssertEqual(report.itemCount, 1)
        XCTAssertTrue(report.findings[0].label.contains("/nowhere/acme-agent"))
    }

    func testKeepsLaunchAgentWhoseProgramExists() throws {
        try writePlist(
            ["Label": "com.acme.agent", "ProgramArguments": ["/bin/sh", "-c", "true"]],
            to: "Library/LaunchAgents/com.acme.agent.plist"
        )

        XCTAssertTrue(inspector.brokenLaunchAgents().isEmpty)
    }

    func testLeavesAgentsThatNameACommandRatherThanAPath() throws {
        try writePlist(
            ["Label": "com.acme.agent", "ProgramArguments": ["acme-agent", "--daemon"]],
            to: "Library/LaunchAgents/com.acme.agent.plist"
        )

        let report = inspector.brokenLaunchAgents()

        XCTAssertTrue(report.isEmpty, "launchd resolves a bare command against its own path, and we cannot")
        XCTAssertNotNil(report.note)
    }

    func testLeavesBundleRelativeAgentsAlone() throws {
        try writePlist(
            ["Label": "com.acme.agent", "BundleProgram": "Contents/MacOS/Agent"],
            to: "Library/LaunchAgents/com.acme.agent.plist"
        )

        XCTAssertTrue(inspector.brokenLaunchAgents().isEmpty)
    }

    func testProgramPathPrefersProgramOverArguments() {
        XCTAssertEqual(
            MaintenanceInspector.programPath(from: ["Program": "/usr/bin/true", "ProgramArguments": ["/bin/false"]]),
            "/usr/bin/true"
        )
        XCTAssertEqual(MaintenanceInspector.programPath(from: ["ProgramArguments": ["/bin/false", "-x"]]), "/bin/false")
        XCTAssertNil(MaintenanceInspector.programPath(from: ["Label": "com.acme.agent"]))
        XCTAssertNil(MaintenanceInspector.programPath(from: ["ProgramArguments": [String]()]))
    }

    // MARK: - Finder metadata

    func testFindsDSStoreFilesOutsideLibrary() throws {
        try write(Data(repeating: 0, count: 64), to: "Documents/Projects/.DS_Store")
        try write(Data(repeating: 0, count: 64), to: "Library/Preferences/.DS_Store")
        try write(Data(repeating: 0, count: 64), to: "Documents/app/node_modules/.DS_Store")

        let report = inspector.finderMetadata()

        XCTAssertEqual(report.itemCount, 1)
        XCTAssertTrue(report.findings[0].label.hasSuffix("Projects"))
    }

    func testSweepStopsAndSaysSoWhenItRunsOutOfTime() throws {
        try write(Data(repeating: 0, count: 64), to: "Documents/.DS_Store")

        let expired = MaintenanceInspector(
            home: home,
            sizer: DirectorySizer(),
            cutoff: Date(),
            limit: 1000,
            deadline: Date(timeIntervalSinceNow: -1)
        )

        let report = expired.finderMetadata()

        XCTAssertTrue(report.isEmpty)
        XCTAssertTrue(report.note?.contains("Stopped after") ?? false, "A partial answer has to say it is partial")
    }

    // MARK: - Login items

    func testReportsLoginItemWhoseTargetIsGone() throws {
        let missing = home.appendingPathComponent("Applications/Gone.app")
        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
        let bookmark = try missing.bookmarkData(options: .suitableForBookmarkFile)
        try FileManager.default.removeItem(at: missing)

        try writePlist(
            ["SessionItems": ["CustomListItems": [["Name": "Gone", "Bookmark": bookmark]]]],
            to: "Library/Preferences/com.apple.loginitems.plist"
        )

        let report = inspector.legacyLoginItems()

        XCTAssertEqual(report.itemCount, 1)
        XCTAssertTrue(report.findings[0].label.hasPrefix("Gone"))
        XCTAssertNil(report.findings[0].url, "An audit points at System Settings, not at a file to delete")
    }

    func testKeepsLoginItemWhoseTargetStillExists() throws {
        let present = home.appendingPathComponent("Applications/Here.app")
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        let bookmark = try present.bookmarkData(options: .suitableForBookmarkFile)

        try writePlist(
            ["SessionItems": ["CustomListItems": [["Name": "Here", "Bookmark": bookmark]]]],
            to: "Library/Preferences/com.apple.loginitems.plist"
        )

        XCTAssertTrue(inspector.legacyLoginItems().isEmpty)
    }

    func testLoginItemAuditAlwaysSaysWhatItCannotSee() {
        let report = inspector.legacyLoginItems()

        XCTAssertTrue(report.note?.contains("System Settings") ?? false)
    }

    // MARK: - Databases

    func testDatabaseTaskIsEmptyWhenTheDatabaseIsAbsent() {
        XCTAssertTrue(inspector.quarantineHistory().isEmpty)
        XCTAssertTrue(inspector.notificationHistory().isEmpty)
    }

    func testCountsOnlyRowsOlderThanTheCutoffInAppleEpoch() throws {
        let database = home.appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
        try FileManager.default.createDirectory(
            at: database.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let old = Date(timeIntervalSinceNow: -400 * 24 * 60 * 60).timeIntervalSinceReferenceDate
        let recent = Date().timeIntervalSinceReferenceDate
        try runSQL(database, """
        CREATE TABLE LSQuarantineEvent (LSQuarantineTimeStamp REAL);
        INSERT INTO LSQuarantineEvent VALUES (\(old)), (\(old)), (\(recent));
        """)

        let report = inspector.quarantineHistory()

        XCTAssertEqual(report.itemCount, 2)
        XCTAssertEqual(report.databaseURL, database)
        XCTAssertEqual(report.reclaimableBytes, 0, "Compaction frees an amount only measurable afterwards")
    }

    /// Apple's private databases do not agree on an epoch, and guessing wrong does not
    /// fail — it silently matches every row in the table.
    func testCountsOnlyRowsOlderThanTheCutoffInUnixEpoch() throws {
        let database = home.appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
        try FileManager.default.createDirectory(
            at: database.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let old = Date(timeIntervalSinceNow: -400 * 24 * 60 * 60).timeIntervalSince1970
        let recent = Date().timeIntervalSince1970
        try runSQL(database, """
        CREATE TABLE LSQuarantineEvent (LSQuarantineTimeStamp REAL);
        INSERT INTO LSQuarantineEvent VALUES (\(old)), (\(recent));
        """)

        XCTAssertEqual(inspector.quarantineHistory().itemCount, 1)
    }

    func testAnUnreadableGroupContainerDoesNotBlameFullDiskAccess() {
        let groupContainer = URL(fileURLWithPath: "/Users/someone/Library/Group Containers/group.com.apple.usernoted/db2/db")
        let ordinary = URL(fileURLWithPath: "/Users/someone/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")

        XCTAssertFalse(
            MaintenanceInspector.unreadableNote(for: groupContainer).contains("Full Disk Access"),
            "Full Disk Access does not open another app's group container, so it must not be offered as the fix"
        )
        XCTAssertTrue(MaintenanceInspector.unreadableNote(for: ordinary).contains("Full Disk Access"))
    }

    private func runSQL(_ database: URL, _ statement: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [database.path, statement]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
