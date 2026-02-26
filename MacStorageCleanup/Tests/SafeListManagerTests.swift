import XCTest
@testable import MacStorageCleanup

/// Unit tests for SafeListManager
final class SafeListManagerTests: XCTestCase {
    
    var safeListManager: SafeListManager!
    
    override func setUp() {
        super.setUp()
        safeListManager = DefaultSafeListManager()
    }
    
    override func tearDown() {
        safeListManager = nil
        super.tearDown()
    }
    
    // MARK: - Protected System Directories Tests
    
    func testSystemDirectoryIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/System"))
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Library"))
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Library/Frameworks"))
    }
    
    func testLibraryAppleIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/Library/Apple"))
        XCTAssertTrue(safeListManager.isProtected(path: "/Library/Apple/System"))
    }
    
    func testUsrBinIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/usr/bin"))
        XCTAssertTrue(safeListManager.isProtected(path: "/usr/bin/ls"))
    }
    
    func testUsrSbinIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/usr/sbin"))
        XCTAssertTrue(safeListManager.isProtected(path: "/usr/sbin/systemsetup"))
    }
    
    func testPrivateVarDbIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/private/var/db"))
        XCTAssertTrue(safeListManager.isProtected(path: "/private/var/db/dslocal"))
    }
    
    func testBinDirectoryIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/bin"))
        XCTAssertTrue(safeListManager.isProtected(path: "/bin/bash"))
    }
    
    func testSbinDirectoryIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/sbin"))
        XCTAssertTrue(safeListManager.isProtected(path: "/sbin/mount"))
    }
    
    // MARK: - Protected User Directories Tests
    
    func testUserKeychainsIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Keychains"))
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Keychains/login.keychain"))
    }
    
    func testUserMailIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Mail"))
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Mail/V10"))
    }
    
    func testUserMessagesIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Messages"))
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Messages/Archive"))
    }
    
    func testUserPhotosIsProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Photos"))
        XCTAssertTrue(safeListManager.isProtected(path: "~/Library/Photos/Libraries"))
    }
    
    // MARK: - System Applications Tests
    
    func testSystemApplicationsAreProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Safari.app"))
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Mail.app"))
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Messages.app"))
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Photos.app"))
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Applications/Calculator.app"))
    }
    
    func testSystemApplicationContentsAreProtected() {
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Safari.app/Contents/MacOS/Safari"))
        XCTAssertTrue(safeListManager.isProtected(path: "/Applications/Mail.app/Contents/Resources/icon.icns"))
    }
    
    // MARK: - Non-Protected Paths Tests
    
    func testUserCachesAreNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Caches"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Caches/com.apple.Safari"))
    }
    
    func testUserApplicationSupportIsNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Application Support"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Application Support/MyApp"))
    }
    
    func testUserLogsAreNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Logs"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Library/Logs/MyApp"))
    }
    
    func testThirdPartyApplicationsAreNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "/Applications/Chrome.app"))
        XCTAssertFalse(safeListManager.isProtected(path: "/Applications/VSCode.app"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Applications/MyApp.app"))
    }
    
    func testUsrLocalIsNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "/usr/local"))
        XCTAssertFalse(safeListManager.isProtected(path: "/usr/local/bin"))
    }
    
    func testTmpDirectoriesAreNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "/tmp"))
        XCTAssertFalse(safeListManager.isProtected(path: "/var/tmp"))
    }
    
    func testUserDocumentsAreNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: "~/Documents"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Downloads"))
        XCTAssertFalse(safeListManager.isProtected(path: "~/Desktop"))
    }
    
    // MARK: - URL-based Tests
    
    func testIsProtectedWithURL() {
        let protectedURL = URL(fileURLWithPath: "/System/Library")
        XCTAssertTrue(safeListManager.isProtected(url: protectedURL))
        
        let nonProtectedURL = URL(fileURLWithPath: "~/Library/Caches")
        XCTAssertFalse(safeListManager.isProtected(url: nonProtectedURL))
    }
    
    // MARK: - macOS Version-Specific Tests
    
    func testUpdateSafeListForBigSur() {
        let bigSurVersion = OperatingSystemVersion(majorVersion: 11, minorVersion: 0, patchVersion: 0)
        safeListManager.updateSafeList(for: bigSurVersion)
        
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Volumes/Data"))
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Volumes/Preboot"))
    }
    
    func testUpdateSafeListForMonterey() {
        let montereyVersion = OperatingSystemVersion(majorVersion: 12, minorVersion: 0, patchVersion: 0)
        safeListManager.updateSafeList(for: montereyVersion)
        
        XCTAssertTrue(safeListManager.isProtected(path: "/System/Library/CoreServices"))
    }
    
    func testUpdateSafeListForVentura() {
        let venturaVersion = OperatingSystemVersion(majorVersion: 13, minorVersion: 0, patchVersion: 0)
        safeListManager.updateSafeList(for: venturaVersion)
        
        XCTAssertTrue(safeListManager.isProtected(path: "/Library/Apple/System"))
    }
    
    // MARK: - Edge Cases
    
    func testEmptyPathIsNotProtected() {
        XCTAssertFalse(safeListManager.isProtected(path: ""))
    }
    
    func testRootPathIsNotProtected() {
        // Root itself is not protected, only specific subdirectories
        XCTAssertFalse(safeListManager.isProtected(path: "/"))
    }
    
    func testPathWithTrailingSlash() {
        XCTAssertTrue(safeListManager.isProtected(path: "/System/"))
        XCTAssertTrue(safeListManager.isProtected(path: "/usr/bin/"))
    }
    
    func testCaseSensitivity() {
        // macOS file system is case-insensitive by default, but paths should match exactly
        XCTAssertTrue(safeListManager.isProtected(path: "/System"))
        // Note: This test assumes case-sensitive matching in the implementation
    }
}
