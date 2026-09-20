import XCTest
@testable import MacStorageCleanupApp

/// Version comparison is where an update checker quietly fails: it reports "up to date"
/// forever and nobody notices, because nothing looks broken.
final class AppVersionTests: XCTestCase {
    func testParsesPlainVersions() {
        XCTAssertEqual(AppVersion("1.4.0")?.components, [1, 4, 0])
        XCTAssertEqual(AppVersion("1.4")?.components, [1, 4])
        XCTAssertEqual(AppVersion("2")?.components, [2])
    }

    /// This project tags bare versions, but a "v" prefix is common enough that silently
    /// failing to parse it would disable update checks with no error anywhere.
    func testToleratesATagPrefix() {
        XCTAssertEqual(AppVersion("v1.4.0")?.components, [1, 4, 0])
        XCTAssertEqual(AppVersion("V1.4.0")?.components, [1, 4, 0])
    }

    func testRejectsNonVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("nightly-build"))
    }

    /// The case that makes string comparison wrong: "1.10.0" < "1.9.0" alphabetically, so
    /// a user on 1.9.0 would never be offered 1.10.0.
    func testComparesNumericallyNotAlphabetically() {
        XCTAssertTrue(AppVersion("1.10.0")! > AppVersion("1.9.0")!)
        XCTAssertTrue(AppVersion("2.0.0")! > AppVersion("1.99.99")!)
        XCTAssertTrue(AppVersion("1.4.10")! > AppVersion("1.4.9")!)
    }

    /// Trailing zeros are padding, not precision: 1.4 and 1.4.0 are the same release.
    func testMissingComponentsCountAsZero() {
        XCTAssertFalse(AppVersion("1.4")! < AppVersion("1.4.0")!)
        XCTAssertFalse(AppVersion("1.4.0")! < AppVersion("1.4")!)
        XCTAssertTrue(AppVersion("1.4.1")! > AppVersion("1.4")!)
    }

    func testPrereleaseSuffixIsIgnored() {
        XCTAssertEqual(AppVersion("1.4.0-beta.1")?.components, [1, 4, 0])
        XCTAssertEqual(AppVersion("2.0-rc1")?.components, [2, 0])
    }

    /// A prerelease must never outrank the release it precedes. Parsing the trailing ".1"
    /// of "1.4.0-beta.1" as a fourth component made it compare as newer than 1.4.0, which
    /// would have offered users a downgrade-shaped "update".
    func testPrereleaseDoesNotOutrankItsRelease() {
        XCTAssertFalse(AppVersion("1.4.0-beta.1")! > AppVersion("1.4.0")!)
    }
}

@MainActor
final class UpdateCheckServiceTests: XCTestCase {
    private struct StubFetcher: ReleaseFetching {
        var release: ReleaseInfo?
        var error: Error?

        func latestRelease() async throws -> ReleaseInfo {
            if let error { throw error }
            return release!
        }
    }

    private let releaseURL = URL(string: "https://github.com/TomerGlick/MacCleaner/releases/tag/1.5.0")!

    private func makeService(latest: String, current: String) -> UpdateCheckService {
        UpdateCheckService(
            fetcher: StubFetcher(release: ReleaseInfo(version: latest, url: releaseURL)),
            currentVersion: current
        )
    }

    func testNewerReleaseIsReported() async {
        let service = makeService(latest: "1.5.0", current: "1.4.0")

        await service.check()

        XCTAssertEqual(service.availableUpdate?.version, "1.5.0")
    }

    func testSameVersionIsNotAnUpdate() async {
        let service = makeService(latest: "1.4.0", current: "1.4.0")

        await service.check()

        XCTAssertNil(service.availableUpdate)
    }

    /// Running a build newer than the published release — a maintainer's own machine —
    /// must not be told to "update" backwards.
    func testOlderReleaseIsNotAnUpdate() async {
        let service = makeService(latest: "1.3.0", current: "1.4.0")

        await service.check()

        XCTAssertNil(service.availableUpdate)
    }

    /// A network failure is not the user's problem: stay silent and retry later.
    func testAFailedCheckReportsNothing() async {
        let service = UpdateCheckService(
            fetcher: StubFetcher(error: UpdateCheckError.badResponse),
            currentVersion: "1.4.0"
        )

        await service.check()

        XCTAssertNil(service.availableUpdate)
        XCTAssertFalse(service.isChecking)
    }

    /// An unparseable tag must not be treated as newer, or every launch would claim an
    /// update exists.
    func testUnparseableTagIsNotAnUpdate() async {
        let service = makeService(latest: "latest", current: "1.4.0")

        await service.check()

        XCTAssertNil(service.availableUpdate)
    }

    func testIsCheckingIsClearedAfterwards() async {
        let service = makeService(latest: "1.5.0", current: "1.4.0")

        await service.check()

        XCTAssertFalse(service.isChecking)
    }
}
