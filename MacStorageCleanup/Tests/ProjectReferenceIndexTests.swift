import XCTest
@testable import MacStorageCleanupCore

final class ProjectReferenceIndexTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReferenceIndexTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testParsesGradleWrapperDistributionURL() throws {
        let url = try write(
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.7.1-bin.zip\n",
            to: "app/gradle/wrapper/gradle-wrapper.properties"
        )

        let parsed = ProjectReferenceIndex.parse(file: url, named: "gradle-wrapper.properties")

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.0, .gradleDistribution)
        XCTAssertEqual(parsed.first?.1, "9.7.1")
    }

    func testParsesNDKAndBuildToolsFromGradleScript() throws {
        let url = try write(
            """
            android {
                ndkVersion "27.0.12077973"
                buildToolsVersion = "34.0.0"
            }
            """,
            to: "app/build.gradle"
        )

        let parsed = ProjectReferenceIndex.parse(file: url, named: "build.gradle")

        XCTAssertTrue(parsed.contains { $0.0 == .androidNDK && $0.1 == "27.0.12077973" })
        XCTAssertTrue(parsed.contains { $0.0 == .androidBuildTools && $0.1 == "34.0.0" })
    }

    /// `ndk.dir` points at a directory; the version is its last component.
    func testParsesNDKDirectoryFromLocalProperties() throws {
        let url = try write(
            "ndk.dir=/Users/someone/Library/Android/sdk/ndk/26.1.10909125\n",
            to: "app/local.properties"
        )

        let parsed = ProjectReferenceIndex.parse(file: url, named: "local.properties")

        XCTAssertEqual(parsed.first?.0, .androidNDK)
        XCTAssertEqual(parsed.first?.1, "26.1.10909125")
    }

    func testParsesNDKVersionFromCIConfig() throws {
        let url = try write(
            """
            env:
              ANDROID_NDK_VERSION: 25.2.9519653
            """,
            to: ".github/workflows/build.yml"
        )

        let parsed = ProjectReferenceIndex.parse(file: url, named: "build.yml")

        XCTAssertTrue(parsed.contains { $0.0 == .androidNDK && $0.1 == "25.2.9519653" })
    }

    func testIgnoresUnrelatedFiles() throws {
        let url = try write("ndkVersion \"27.0.0\"", to: "README.md")
        XCTAssertTrue(ProjectReferenceIndex.parse(file: url, named: "README.md").isEmpty)
    }

    func testBuildFindsReferencesAndLookupMatchesExactly() throws {
        try write(
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.7.1-bin.zip\n",
            to: "app/gradle/wrapper/gradle-wrapper.properties"
        )

        let index = ProjectReferenceIndex.build(roots: [tempDirectory])

        XCTAssertFalse(index.isEmpty)
        XCTAssertEqual(index.references(kind: .gradleDistribution, version: "9.7.1").count, 1)
        // A version nothing pins is what makes a row safe to offer.
        XCTAssertTrue(index.references(kind: .gradleDistribution, version: "9.2.1").isEmpty)
    }

    /// Build output is where the entry count explodes, and it never holds the pins we want.
    func testBuildSkipsBuildOutputDirectories() throws {
        try write(
            "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.0-bin.zip\n",
            to: "node_modules/pkg/gradle/wrapper/gradle-wrapper.properties"
        )

        let index = ProjectReferenceIndex.build(roots: [tempDirectory])

        XCTAssertTrue(index.references(kind: .gradleDistribution, version: "8.0").isEmpty)
    }
}
