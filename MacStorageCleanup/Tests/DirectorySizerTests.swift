import XCTest
@testable import MacStorageCleanupCore

final class DirectorySizerTests: XCTestCase {
    var tempDirectory: URL!
    var sizer: DirectorySizer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sizer = DirectorySizer()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirectorySizerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        sizer = nil
        try super.tearDownWithError()
    }

    private func write(_ bytes: Int, to relativePath: String) throws {
        let url = tempDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: bytes).write(to: url)
    }

    /// The old implementation passed `.skipsHiddenFiles`, so everything inside `~/.gradle`
    /// and every dotfile in a cache was invisible to sizing.
    func testHiddenFilesAreCounted() throws {
        try write(8192, to: ".hidden-file")
        try write(8192, to: ".hidden-dir/payload.bin")

        let measured = sizer.allocatedSize(of: tempDirectory)

        XCTAssertGreaterThanOrEqual(measured.bytes, 16384)
        XCTAssertEqual(measured.measurement, .enumerated)
        XCTAssertFalse(measured.needsFullDiskAccess)
    }

    func testNestedFilesAreSummed() throws {
        try write(4096, to: "a/b/one.bin")
        try write(4096, to: "a/b/c/two.bin")
        try write(4096, to: "three.bin")

        XCTAssertGreaterThanOrEqual(sizer.allocatedSize(of: tempDirectory).bytes, 12288)
    }

    func testMissingDirectoryIsZeroNotAnError() {
        let missing = tempDirectory.appendingPathComponent("does-not-exist")
        let measured = sizer.allocatedSize(of: missing)

        XCTAssertEqual(measured.bytes, 0)
        XCTAssertFalse(measured.needsFullDiskAccess)
    }

    /// An unreadable directory must report "permission needed", not "0 bytes" — the
    /// whole point of the distinct state.
    func testUnreadableDirectoryReportsPermissionNeeded() throws {
        let locked = tempDirectory.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try write(4096, to: "locked/payload.bin")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        // Running as root defeats the permission bits; skip rather than assert falsely.
        try XCTSkipIf(getuid() == 0, "Permission checks are meaningless as root")

        let measured = sizer.allocatedSize(of: locked)

        XCTAssertTrue(measured.needsFullDiskAccess)
        XCTAssertTrue(measured.isUnderstated)
    }

    func testSymlinkedDirectoryIsNotFollowed() throws {
        let outside = tempDirectory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(count: 1_000_000).write(to: outside.appendingPathComponent("big.bin"))

        let inside = tempDirectory.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: inside.appendingPathComponent("link"),
            withDestinationURL: outside
        )

        // The 1 MB behind the symlink must not be attributed to `inside`.
        XCTAssertLessThan(sizer.allocatedSize(of: inside).bytes, 1_000_000)
    }

    func testRootIsAMountPointAndReportsUsedBytes() {
        let root = URL(fileURLWithPath: "/")

        XCTAssertTrue(sizer.isMountPoint(root))

        let used = sizer.mountUsedBytes(at: root)
        XCTAssertNotNil(used)
        XCTAssertGreaterThan(used ?? 0, 0)

        // `size(of:)` must pick statfs for a mount point rather than walking the disk.
        XCTAssertEqual(sizer.size(of: root).measurement, .statfs)
    }

    func testTemporaryDirectoryIsNotAMountPoint() {
        XCTAssertFalse(sizer.isMountPoint(tempDirectory))
    }

    func testZeroBudgetYieldsPartialMeasurement() throws {
        for index in 0..<4000 {
            try write(16, to: "bulk/file-\(index).bin")
        }

        let impatient = DirectorySizer(budget: 0)
        XCTAssertEqual(impatient.allocatedSize(of: tempDirectory).measurement, .partial)
    }
}
