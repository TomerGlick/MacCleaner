import XCTest
import MacStorageCleanupCore
@testable import MacStorageCleanupApp

/// Covers the traffic-light mapping and the selection note shown under each row.
///
/// The dot and the checkbox must never disagree: a row the app ticks for the user has
/// promised something about what deleting it costs, and the dot is that promise made
/// visible.
final class CleanupCandidateRiskTests: XCTestCase {
    private func makeCandidate(
        safety: CacheSafety? = nil,
        isNewestVersion: Bool = true,
        referencedBy: [URL] = [],
        requiresAdmin: Bool = false,
        needsFullDiskAccess: Bool = false
    ) -> CleanupCandidateData {
        CleanupCandidateData(
            path: "/tmp/example",
            name: "example",
            size: 1024,
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache,
            category: .caches,
            safety: safety,
            isNewestVersion: isNewestVersion,
            referencedBy: referencedBy,
            requiresAdmin: requiresAdmin,
            needsFullDiskAccess: needsFullDiskAccess
        )
    }

    // MARK: - Risk mapping

    func testAlwaysSafeIsGreen() {
        XCTAssertEqual(makeCandidate(safety: .alwaysSafe).riskLevel, .safe)
    }

    func testRegeneratesIsAmber() {
        XCTAssertEqual(makeCandidate(safety: .regenerates).riskLevel, .moderate)
    }

    func testNeedsConfirmationIsRed() {
        XCTAssertEqual(makeCandidate(safety: .needsConfirmation).riskLevel, .risky)
    }

    /// System, browser and generic app caches arrive with no safety tier. They are caches,
    /// so amber — never green, which would over-promise on data we never classified.
    func testUnclassifiedCacheIsAmberNotGreen() {
        XCTAssertEqual(makeCandidate(safety: nil).riskLevel, .moderate)
    }

    /// A directory we could not read is unmeasured, and that is its own reason to look.
    func testUnreadablePathIsRedEvenWhenItsTierIsSafe() {
        let candidate = makeCandidate(safety: .alwaysSafe, needsFullDiskAccess: true)

        XCTAssertEqual(candidate.riskLevel, .risky)
    }

    func testRiskLevelsOrderSafestFirst() {
        XCTAssertLessThan(CleanupCandidateData.RiskLevel.safe, .moderate)
        XCTAssertLessThan(CleanupCandidateData.RiskLevel.moderate, .risky)
        // A group heading takes the max, so ordering is what makes "worst wins" work.
        let mixed: [CleanupCandidateData.RiskLevel] = [.safe, .risky, .moderate]
        XCTAssertEqual(mixed.max(), .risky)
    }

    func testEveryLevelHasADistinctColourAndLabel() {
        let levels = CleanupCandidateData.RiskLevel.allCases

        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(Set(levels.map(\.label)).count, 3)
        XCTAssertTrue(levels.allSatisfy { !$0.explanation.isEmpty })
    }

    // MARK: - Agreement between the dot and the checkbox

    /// Nothing green may be left unticked, and nothing red may be ticked. This is the
    /// invariant that keeps the legend honest.
    func testGreenIsAlwaysTickedAndRedIsNever() {
        let green = makeCandidate(safety: .alwaysSafe)
        XCTAssertEqual(green.riskLevel, .safe)

        let red = makeCandidate(safety: .needsConfirmation, isNewestVersion: false)
        XCTAssertEqual(red.riskLevel, .risky)

        // Mirrors DeveloperCache.isDefaultSelected, which is what fills `isSelected`.
        XCTAssertTrue(DeveloperCache(
            tool: .gradleScratch,
            cacheLocation: URL(fileURLWithPath: "/tmp/example"),
            size: 1024,
            description: "example",
            safety: .alwaysSafe
        ).isDefaultSelected)

        XCTAssertFalse(DeveloperCache(
            tool: .androidAVD,
            cacheLocation: URL(fileURLWithPath: "/tmp/example"),
            size: 1024,
            description: "example",
            isNewestVersion: false,
            safety: .needsConfirmation
        ).isDefaultSelected)
    }

    // MARK: - Selection note

    func testPinnedVersionNamesTheProjectFiles() {
        let candidate = makeCandidate(
            safety: .regenerates,
            isNewestVersion: false,
            referencedBy: [URL(fileURLWithPath: "/Users/someone/app/build.gradle.kts")]
        )

        XCTAssertEqual(candidate.safetyNote, "Pinned by build.gradle.kts")
    }

    func testManyReferencesAreSummarised() {
        let candidate = makeCandidate(
            safety: .regenerates,
            isNewestVersion: false,
            referencedBy: (1...5).map { URL(fileURLWithPath: "/p/\($0)/build.gradle") }
        )

        XCTAssertEqual(candidate.safetyNote, "Pinned by build.gradle, build.gradle and 3 more")
    }

    /// Permission trumps everything else: reporting a size for a path we could not read
    /// would be the one actively misleading thing the row could say.
    func testPermissionNoteWinsOverAPin() {
        let candidate = makeCandidate(
            safety: .regenerates,
            referencedBy: [URL(fileURLWithPath: "/p/build.gradle")],
            needsFullDiskAccess: true
        )

        XCTAssertEqual(candidate.safetyNote, "Permission needed — grant Full Disk Access to measure this")
    }

    func testAdminNoteIsShownForSystemScopedRows() {
        let candidate = makeCandidate(safety: .needsConfirmation, requiresAdmin: true)

        XCTAssertEqual(candidate.safetyNote, "Needs administrator rights")
    }
}
