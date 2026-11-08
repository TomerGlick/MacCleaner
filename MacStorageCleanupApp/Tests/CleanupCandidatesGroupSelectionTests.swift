import XCTest
import MacStorageCleanupCore
@testable import MacStorageCleanupApp

/// Covers the group checkbox: its tri-state, what it toggles, and the risk it reports.
@MainActor
final class CleanupCandidatesGroupSelectionTests: XCTestCase {
    private func makeCandidate(
        name: String,
        group: String,
        size: Int64 = 1024,
        safety: CacheSafety? = nil,
        isSelected: Bool = false
    ) -> CleanupCandidateData {
        CleanupCandidateData(
            path: "/tmp/\(group)/\(name)",
            name: name,
            size: size,
            modifiedDate: Date(),
            accessedDate: Date(),
            fileType: .cache,
            category: .caches,
            groupLabel: group,
            isSelected: isSelected,
            safety: safety
        )
    }

    private func makeViewModel(
        _ candidates: [CleanupCandidateData],
        category: CleanupCandidateData.CleanupCategoryType = .caches
    ) -> CleanupCandidatesViewModel {
        let viewModel = CleanupCandidatesViewModel(category: category)
        viewModel.candidates = candidates
        viewModel.filteredCandidates = candidates
        return viewModel
    }

    // MARK: - Tri-state

    func testEmptySelectionIsNeitherFullNorPartial() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle"),
            makeCandidate(name: "b", group: "Gradle")
        ])

        XCTAssertFalse(viewModel.isGroupFullySelected("Gradle"))
        XCTAssertFalse(viewModel.isGroupPartiallySelected("Gradle"))
    }

    func testPartialSelectionIsReportedAsMixed() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", isSelected: true),
            makeCandidate(name: "b", group: "Gradle")
        ])

        XCTAssertFalse(viewModel.isGroupFullySelected("Gradle"))
        XCTAssertTrue(viewModel.isGroupPartiallySelected("Gradle"))
    }

    /// Full is full, not mixed — otherwise the checkbox would show a dash at the moment
    /// it should show a tick.
    func testFullSelectionIsNotAlsoPartial() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", isSelected: true),
            makeCandidate(name: "b", group: "Gradle", isSelected: true)
        ])

        XCTAssertTrue(viewModel.isGroupFullySelected("Gradle"))
        XCTAssertFalse(viewModel.isGroupPartiallySelected("Gradle"))
    }

    func testAnEmptyGroupIsNotConsideredFullySelected() {
        let viewModel = makeViewModel([makeCandidate(name: "a", group: "Gradle")])

        XCTAssertFalse(viewModel.isGroupFullySelected("Android SDK"))
    }

    // MARK: - Toggling

    func testTogglingSelectsOnlyTheNamedGroup() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle"),
            makeCandidate(name: "b", group: "Gradle"),
            makeCandidate(name: "c", group: "Android SDK")
        ])

        viewModel.toggleGroupSelection("Gradle")

        XCTAssertTrue(viewModel.isGroupFullySelected("Gradle"))
        XCTAssertFalse(viewModel.isGroupFullySelected("Android SDK"))
        XCTAssertEqual(viewModel.selectedCount, 2)
    }

    func testTogglingAFullySelectedGroupClearsIt() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", isSelected: true),
            makeCandidate(name: "b", group: "Gradle", isSelected: true)
        ])

        viewModel.toggleGroupSelection("Gradle")

        XCTAssertEqual(viewModel.selectedCount, 0)
    }

    /// From mixed, the first click completes the group rather than clearing it — the
    /// less destructive reading of an ambiguous state.
    func testTogglingAPartialGroupCompletesIt() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", isSelected: true),
            makeCandidate(name: "b", group: "Gradle")
        ])

        viewModel.toggleGroupSelection("Gradle")

        XCTAssertTrue(viewModel.isGroupFullySelected("Gradle"))
    }

    /// The toggle must reach the backing array too, or the selection is lost the moment
    /// a filter re-runs.
    func testTogglingUpdatesTheUnfilteredCandidates() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle"),
            makeCandidate(name: "b", group: "Gradle")
        ])

        viewModel.toggleGroupSelection("Gradle")

        XCTAssertTrue(viewModel.candidates.allSatisfy(\.isSelected))
        XCTAssertEqual(viewModel.selectedFiles.count, 2)
    }

    // MARK: - Size and risk

    func testSelectedSizeCountsOnlyTickedRowsInThatGroup() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", size: 1000, isSelected: true),
            makeCandidate(name: "b", group: "Gradle", size: 500),
            makeCandidate(name: "c", group: "Android SDK", size: 9000, isSelected: true)
        ])

        XCTAssertEqual(viewModel.selectedSize(inGroup: "Gradle"), 1000)
        XCTAssertEqual(viewModel.selectedSize(inGroup: "Android SDK"), 9000)
    }

    /// A heading reading green while hiding one row that removes an emulator would be the
    /// single misleading light in the UI, so the worst item wins.
    func testGroupRiskTakesTheRiskiestItem() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Android SDK", safety: .alwaysSafe),
            makeCandidate(name: "b", group: "Android SDK", safety: .regenerates),
            makeCandidate(name: "c", group: "Android SDK", safety: .needsConfirmation)
        ])

        XCTAssertEqual(viewModel.riskLevel(inGroup: "Android SDK"), .risky)
    }

    func testAnAllSafeGroupReportsSafe() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "Gradle", safety: .alwaysSafe),
            makeCandidate(name: "b", group: "Gradle", safety: .alwaysSafe)
        ])

        XCTAssertEqual(viewModel.riskLevel(inGroup: "Gradle"), .safe)
    }

    // MARK: - Every grouped category

    /// A heading must only ever report and act on the rows under it. When a category is
    /// grouped in the list but not in the selection helpers, every heading shows the whole
    /// list's selection and one click ticks rows belonging to other apps entirely.
    func testAGroupInAnyGroupedCategoryOnlyCoversItsOwnRows() {
        for category in [CleanupCandidateData.CleanupCategoryType.caches, .leftovers] {
            let viewModel = makeViewModel([
                makeCandidate(name: "a", group: "Inkscape", size: 100, isSelected: true),
                makeCandidate(name: "b", group: "Sketch", size: 900, isSelected: true)
            ], category: category)

            XCTAssertEqual(
                viewModel.selectedSize(inGroup: "Inkscape"), 100,
                "\(category) reported another group's bytes under this heading"
            )
            XCTAssertEqual(viewModel.selectedSize(inGroup: "Sketch"), 900)

            viewModel.toggleGroupSelection("Inkscape")

            XCTAssertFalse(viewModel.candidates[0].isSelected)
            XCTAssertTrue(
                viewModel.candidates[1].isSelected,
                "\(category) cleared a row that was not under the heading that was clicked"
            )
        }
    }

    func testAnUngroupedCategoryStillTreatsTheWholeListAsOneGroup() {
        let viewModel = makeViewModel([
            makeCandidate(name: "a", group: "unused", size: 100, isSelected: true),
            makeCandidate(name: "b", group: "unused", size: 900, isSelected: true)
        ], category: .duplicates)

        XCTAssertEqual(viewModel.selectedSize(inGroup: ""), 1000)
    }
}
