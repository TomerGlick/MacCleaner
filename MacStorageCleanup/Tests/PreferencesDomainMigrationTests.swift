import XCTest
@testable import MacStorageCleanupCore

/// Covers the bundle identifier rename in 1.4.0.
///
/// `UserDefaults.standard` is keyed by bundle identifier, so renaming the bundle moves the
/// entire preferences domain. Without a migration a returning user finds every setting back
/// at its default and nothing says why — the kind of data loss that looks like a bug in
/// saving rather than a rename.
final class PreferencesDomainMigrationTests: XCTestCase {
    private var currentSuiteName: String!
    private var legacySuiteName: String!
    private var currentDefaults: UserDefaults!
    private var legacyDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let unique = UUID().uuidString
        currentSuiteName = "test.current.\(unique)"
        legacySuiteName = "test.legacy.\(unique)"
        currentDefaults = try XCTUnwrap(UserDefaults(suiteName: currentSuiteName))
        legacyDefaults = try XCTUnwrap(UserDefaults(suiteName: legacySuiteName))
    }

    override func tearDownWithError() throws {
        currentDefaults.removePersistentDomain(forName: currentSuiteName)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        currentDefaults = nil
        legacyDefaults = nil
        try super.tearDownWithError()
    }

    private func makeStore() -> UserDefaultsPreferencesStore {
        UserDefaultsPreferencesStore(userDefaults: currentDefaults, legacyDomainDefaults: legacyDefaults)
    }

    private func seedLegacyDomain(with preferences: UserPreferences, key: String) throws {
        legacyDefaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }

    // MARK: - Migration

    func testPreferencesAreInheritedFromTheOldBundleDomain() throws {
        var saved = UserPreferences.default
        saved.moveToTrashByDefault = false
        saved.oldFileThresholdDays = 180
        saved.projectArtifactScanRoots = ["/Users/someone/Develop"]
        try seedLegacyDomain(with: saved, key: PreferencesStorageConstants.primaryKey)

        let loaded = try makeStore().load()

        XCTAssertFalse(loaded.moveToTrashByDefault)
        XCTAssertEqual(loaded.oldFileThresholdDays, 180)
        XCTAssertEqual(loaded.projectArtifactScanRoots, ["/Users/someone/Develop"])
    }

    /// Inherited once, then owned. The old domain belongs to a bundle that no longer runs,
    /// so it must not be consulted again and quietly undo later edits.
    func testInheritedPreferencesAreWrittenToTheCurrentDomain() throws {
        var saved = UserPreferences.default
        saved.debugMode = true
        try seedLegacyDomain(with: saved, key: PreferencesStorageConstants.primaryKey)

        let store = makeStore()
        _ = try store.load()

        XCTAssertNotNil(currentDefaults.data(forKey: PreferencesStorageConstants.primaryKey))

        // A later change must survive, rather than being overwritten by the old domain.
        var updated = try store.load()
        updated.debugMode = false
        try store.save(updated)

        XCTAssertFalse(try store.load().debugMode)
    }

    func testCurrentDomainWinsOverTheLegacyDomain() throws {
        var legacy = UserPreferences.default
        legacy.oldFileThresholdDays = 180
        try seedLegacyDomain(with: legacy, key: PreferencesStorageConstants.primaryKey)

        var current = UserPreferences.default
        current.oldFileThresholdDays = 400
        let store = makeStore()
        try store.save(current)

        XCTAssertEqual(try store.load().oldFileThresholdDays, 400)
    }

    /// The pre-1.2 encoded blob, in a domain that is also pre-rename: both migrations have
    /// to compose rather than one masking the other.
    func testLegacyEncodedKeyInTheLegacyDomainIsMigrated() throws {
        var saved = UserPreferences.default
        saved.largeFileSizeThresholdMB = 512
        try seedLegacyDomain(with: saved, key: PreferencesStorageConstants.legacyEncodedPreferencesKey)

        XCTAssertEqual(try makeStore().load().largeFileSizeThresholdMB, 512)
    }

    func testStandaloneLegacyKeysInTheLegacyDomainAreMigrated() throws {
        legacyDefaults.set(false, forKey: PreferencesStorageConstants.legacyShowMenuBarIconKey)
        legacyDefaults.set(true, forKey: PreferencesStorageConstants.legacyDebugModeKey)

        let loaded = try makeStore().load()

        XCTAssertFalse(loaded.showMenuBarIcon)
        XCTAssertTrue(loaded.debugMode)
    }

    func testAFreshInstallGetsDefaults() throws {
        XCTAssertEqual(try makeStore().load(), .default)
    }

    /// Guards against the store reading its own domain as if it were the legacy one, which
    /// would make `load()` recurse through a pointless migration on every launch.
    func testTheLegacyDomainIsIgnoredWhenItIsTheCurrentDomain() throws {
        let store = UserDefaultsPreferencesStore(
            userDefaults: currentDefaults,
            legacyDomainDefaults: currentDefaults
        )

        XCTAssertEqual(try store.load(), .default)
    }
}
