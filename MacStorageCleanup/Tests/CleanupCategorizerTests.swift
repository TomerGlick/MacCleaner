import XCTest
@testable import MacStorageCleanupCore

final class CleanupCategorizerTests: XCTestCase {
    func testCategorizeBrowserCaches_RecognizesFirefoxAndEdgeCaseInsensitively() {
        let firefoxFile = createFileMetadata(
            path: "/Users/test/Library/Caches/FireFox/Profiles/default/cache2/entries/data",
            size: 1024,
            fileType: .cache
        )
        let edgeFile = createFileMetadata(
            path: "/Users/test/Library/Caches/Microsoft Edge/Default/Cache/Cache_Data",
            size: 2048,
            fileType: .cache
        )

        let firefoxCategories = categorize(firefoxFile)
        let edgeCategories = categorize(edgeFile)

        XCTAssertTrue(firefoxCategories.contains(.browserCaches))
        XCTAssertFalse(firefoxCategories.contains(.applicationCaches))
        XCTAssertTrue(edgeCategories.contains(.browserCaches))
        XCTAssertFalse(edgeCategories.contains(.applicationCaches))
    }

    func testCategorizeTemporaryFiles_RecognizesApplicationSupportTmpSubdirectories() {
        let tempSupportFile = createFileMetadata(
            path: "/Users/test/Library/Application Support/MyApp/tmp/cache/data.sqlite",
            size: 4096,
            fileType: .other("sqlite")
        )

        let categories = categorize(tempSupportFile)

        XCTAssertTrue(categories.contains(.temporaryFiles))
    }

    func testCategorizeOldFiles_UsesProvidedNowForExactBoundary() {
        let referenceNow = Date()
        let exactBoundaryFile = createFileMetadata(
            path: "/Users/test/Documents/boundary.txt",
            size: 512,
            accessedDate: referenceNow.addingTimeInterval(-(365 * 24 * 60 * 60)),
            fileType: .document
        )

        let categories = CleanupCategorizer.categorize(
            file: exactBoundaryFile,
            options: defaultOptions(),
            now: referenceNow
        )

        XCTAssertTrue(categories.contains(.oldFiles))
    }

    func testCategorizeOldFiles_DoesNotMarkFutureAccessDatesAsOld() {
        let referenceNow = Date()
        let futureAccessFile = createFileMetadata(
            path: "/Users/test/Documents/future.txt",
            size: 1024,
            accessedDate: referenceNow.addingTimeInterval(60),
            fileType: .document
        )

        let categories = CleanupCategorizer.categorize(
            file: futureAccessFile,
            options: defaultOptions(),
            now: referenceNow
        )

        XCTAssertFalse(categories.contains(.oldFiles))
    }

    func testCategorizeOldFiles_ProtectedFilesAreExcludedWhenConfigured() {
        let protectedFile = createFileMetadata(
            path: "/Users/test/Library/Keychains/login.keychain-db",
            size: 2048,
            accessedDate: Date().addingTimeInterval(-(400 * 24 * 60 * 60)),
            fileType: .other("keychain-db")
        )

        let categories = CleanupCategorizer.categorize(
            file: protectedFile,
            options: defaultOptions(excludeProtectedOldFiles: true),
            safeListManager: StubSafeListManager(protectedPaths: [protectedFile.url.path])
        )

        XCTAssertFalse(categories.contains(.oldFiles))
    }

    func testCategorizeOldFiles_ProtectedFilesRemainOldWhenExclusionDisabled() {
        let protectedFile = createFileMetadata(
            path: "/Users/test/Library/Keychains/login.keychain-db",
            size: 2048,
            accessedDate: Date().addingTimeInterval(-(400 * 24 * 60 * 60)),
            fileType: .other("keychain-db")
        )

        let categories = CleanupCategorizer.categorize(
            file: protectedFile,
            options: defaultOptions(excludeProtectedOldFiles: false),
            safeListManager: StubSafeListManager(protectedPaths: [protectedFile.url.path])
        )

        XCTAssertTrue(categories.contains(.oldFiles))
    }

    func testCategorizeOldFiles_AppBundlePathsExcludedOnlyWhenConfigured() {
        let oldAppBundleFile = createFileMetadata(
            path: "/Applications/MyApp.app/Contents/MacOS/MyApp",
            size: 10 * 1024 * 1024,
            accessedDate: Date().addingTimeInterval(-(400 * 24 * 60 * 60)),
            fileType: .application
        )

        let excludedCategories = CleanupCategorizer.categorize(
            file: oldAppBundleFile,
            options: defaultOptions(excludeProtectedOldFiles: true)
        )
        let includedCategories = CleanupCategorizer.categorize(
            file: oldAppBundleFile,
            options: defaultOptions(excludeProtectedOldFiles: false)
        )

        XCTAssertFalse(excludedCategories.contains(.oldFiles))
        XCTAssertTrue(includedCategories.contains(.oldFiles))
    }

    private func categorize(_ file: FileMetadata) -> Set<CleanupCategory> {
        CleanupCategorizer.categorize(file: file, options: defaultOptions())
    }

    private func defaultOptions(excludeProtectedOldFiles: Bool = false) -> CleanupCategorizationOptions {
        CleanupCategorizationOptions(
            largeFileThresholdBytes: 100 * 1024 * 1024,
            oldFileThresholdSeconds: 365 * 24 * 60 * 60,
            excludeProtectedOldFiles: excludeProtectedOldFiles
        )
    }

    private func createFileMetadata(
        path: String,
        size: Int64,
        accessedDate: Date = Date(),
        fileType: FileType = .other("")
    ) -> FileMetadata {
        FileMetadata(
            url: URL(fileURLWithPath: path),
            size: size,
            createdDate: Date(),
            modifiedDate: Date(),
            accessedDate: accessedDate,
            fileType: fileType,
            isInUse: false,
            permissions: FilePermissions(isReadable: true, isWritable: true, isDeletable: true)
        )
    }
}

private struct StubSafeListManager: SafeListManager {
    let protectedPaths: Set<String>

    func isProtected(url: URL) -> Bool {
        protectedPaths.contains(url.path)
    }

    func isProtected(path: String) -> Bool {
        protectedPaths.contains(path)
    }

    func updateSafeList(for macOSVersion: OperatingSystemVersion) {}
}
