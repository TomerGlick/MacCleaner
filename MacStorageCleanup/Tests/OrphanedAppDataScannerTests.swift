import XCTest
@testable import MacStorageCleanupCore

final class OrphanedAppDataScannerTests: XCTestCase {
    var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrphanedAppDataScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
        home = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeDirectory(_ relativePath: String, modified: Date) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // A byte of payload, so a size of zero in a result means "we did not measure it".
        try Data(repeating: 0x41, count: 2048).write(to: url.appendingPathComponent("payload.bin"))
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    private func makeFile(_ relativePath: String, modified: Date) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 512).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    private func scanner(installed: Set<String> = []) -> OrphanedAppDataScanner {
        OrphanedAppDataScanner(
            sizer: DirectorySizer(),
            installed: InstalledApplicationIndex(bundleIdentifiers: installed),
            homeDir: home.path
        )
    }

    private var longAgo: Date { Date(timeIntervalSinceNow: -400 * 24 * 60 * 60) }
    private var yesterday: Date { Date(timeIntervalSinceNow: -24 * 60 * 60) }

    // MARK: - Finding leftovers

    func testFindsDataForAnApplicationThatIsNotInstalled() throws {
        try makeDirectory("Library/Application Support/com.acme.Widget", modified: longAgo)

        let results = scanner().scan()

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bundleIdentifier, "com.acme.Widget")
        XCTAssertEqual(results.first?.kind, .applicationSupport)
        XCTAssertEqual(results.first?.displayName, "Widget")
        XCTAssertGreaterThan(results.first?.size ?? 0, 0)
    }

    func testReportsEachLocationSeparately() throws {
        try makeDirectory("Library/Caches/com.acme.Widget", modified: longAgo)
        try makeDirectory("Library/Containers/com.acme.Widget", modified: longAgo)
        try makeFile("Library/Preferences/com.acme.Widget.plist", modified: longAgo)
        try makeDirectory("Library/Saved Application State/com.acme.Widget.savedState", modified: longAgo)

        let kinds = Set(scanner().scan().map(\.kind))

        XCTAssertEqual(kinds, [.caches, .container, .preferences, .savedState])
    }

    // MARK: - Not offering data that is still owned

    func testSkipsDataForAnInstalledApplication() throws {
        try makeDirectory("Library/Caches/com.acme.Widget", modified: longAgo)

        let results = scanner(installed: ["com.acme.Widget"]).scan()

        XCTAssertTrue(results.isEmpty)
    }

    func testSkipsHelperDataBelongingToAnInstalledApplication() throws {
        try makeDirectory("Library/Caches/com.acme.Widget.Helper", modified: longAgo)

        let results = scanner(installed: ["com.acme.Widget"]).scan()

        XCTAssertTrue(results.isEmpty, "A helper's data belongs to the app that ships it")
    }

    func testSkipsSuiteDataWhenOnlyAMemberAppIsInstalled() throws {
        try makeDirectory("Library/Application Support/com.acme.suite", modified: longAgo)

        let results = scanner(installed: ["com.acme.suite.Widget"]).scan()

        XCTAssertTrue(results.isEmpty, "A suite folder is shared by the apps beneath it")
    }

    func testMatchesInstalledIdentifiersCaseInsensitively() throws {
        try makeDirectory("Library/Caches/com.acme.Widget", modified: longAgo)

        let results = scanner(installed: ["COM.ACME.WIDGET"]).scan()

        XCTAssertTrue(results.isEmpty)
    }

    func testSkipsRecentlyWrittenData() throws {
        try makeDirectory("Library/Caches/com.acme.Widget", modified: yesterday)

        let results = scanner().scan()

        XCTAssertTrue(results.isEmpty, "Something still writes here, so it is not abandoned")
    }

    func testSkipsAppleIdentifiers() throws {
        try makeDirectory("Library/Caches/com.apple.Something", modified: longAgo)
        try makeFile("Library/Preferences/com.apple.finder.plist", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty, "Apple identifiers often own no app bundle at all")
    }

    func testSkipsThisApplicationsOwnData() throws {
        try makeDirectory("Library/Caches/com.tomerglick.MacStorageCleanup", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty)
    }

    func testIgnoresFoldersThatAreNotNamedAfterABundleIdentifier() throws {
        try makeDirectory("Library/Application Support/Adobe", modified: longAgo)
        try makeDirectory("Library/Application Support/Google", modified: longAgo)
        try makeDirectory("Library/Caches/Firefox", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty, "A product name names no owner we can check")
    }

    func testIgnoresTwoPartNamesThatAreMoreLikelyFoldersThanIdentifiers() throws {
        try makeDirectory("Library/Application Support/Backups.backupdb", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty)
    }

    func testIgnoresHiddenEntries() throws {
        try makeDirectory("Library/Caches/.com.acme.Widget", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty)
    }

    func testIgnoresGroupContainerIdentifiers() throws {
        try makeDirectory("Library/Application Support/group.com.acme.Widget", modified: longAgo)

        XCTAssertTrue(scanner().scan().isEmpty, "No single app owns a group identifier")
    }

    func testPreferencesFileWithoutPlistSuffixIsIgnored() throws {
        try makeFile("Library/Preferences/com.acme.Widget.other", modified: longAgo)

        let kinds = scanner().scan().map(\.kind)

        XCTAssertFalse(kinds.contains(.preferences))
    }

    // MARK: - Identifier parsing

    func testBundleIdentifierParsing() {
        XCTAssertEqual(OrphanedAppDataScanner.bundleIdentifier(from: "com.acme.Widget", suffix: ""), "com.acme.Widget")
        XCTAssertEqual(OrphanedAppDataScanner.bundleIdentifier(from: "com.acme.Widget.plist", suffix: ".plist"), "com.acme.Widget")
        XCTAssertNil(OrphanedAppDataScanner.bundleIdentifier(from: "com.acme", suffix: ""))
        XCTAssertNil(OrphanedAppDataScanner.bundleIdentifier(from: "Adobe", suffix: ""))
        XCTAssertNil(OrphanedAppDataScanner.bundleIdentifier(from: "com..Widget", suffix: ""))
        XCTAssertNil(OrphanedAppDataScanner.bundleIdentifier(from: "com.acme.Widget", suffix: ".plist"))
        XCTAssertNil(OrphanedAppDataScanner.bundleIdentifier(from: "com.acme.Widget 2", suffix: ""))
    }

    func testKindsThatCarryUserDataAreLabelledAsSuch() {
        XCTAssertTrue(OrphanedDataKind.container.carriesUserData)
        XCTAssertTrue(OrphanedDataKind.applicationSupport.carriesUserData)
        XCTAssertFalse(OrphanedDataKind.caches.carriesUserData)
        XCTAssertFalse(OrphanedDataKind.savedState.carriesUserData)
    }
}
