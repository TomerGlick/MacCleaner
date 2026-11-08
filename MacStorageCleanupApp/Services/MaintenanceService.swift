import Foundation
import MacStorageCleanupCore

/// The maintenance jobs this app knows how to do.
///
/// Every task here is user-scope: it touches files under the user's own Library and never
/// needs administrator rights. That is the line this catalog draws on purpose — the
/// privileged helper exposes exactly one action, and reclaiming a few megabytes of stale
/// state is not a good enough reason to widen it.
enum MaintenanceTaskID: String, CaseIterable, Identifiable {
    case savedApplicationState
    case brokenLaunchAgents
    case quarantineHistory
    case notificationHistory
    case finderMetadata
    case legacyLoginItems

    var id: String { rawValue }
}

/// One thing a task found, and what removing it is worth.
struct MaintenanceFinding: Identifiable, Equatable {
    let id = UUID()
    /// The file this refers to, when the finding is a file at all. Database rows have none.
    let url: URL?
    let label: String
    let bytes: Int64

    static func == (lhs: MaintenanceFinding, rhs: MaintenanceFinding) -> Bool {
        lhs.id == rhs.id
    }
}

/// What a task saw when it looked, before anything was changed.
///
/// `itemCount` is stated separately from `findings` because the two database tasks count
/// rows they will delete but hold a single file to act on. `reclaimableBytes` is zero when
/// the figure is genuinely unknown — compacting a database frees an amount nobody can
/// predict from outside it — and the UI says "unknown" rather than inventing a number.
struct MaintenanceReport: Equatable {
    let taskID: MaintenanceTaskID
    /// The files this task would remove. Empty for a task that edits a database in place.
    let findings: [MaintenanceFinding]
    /// What to tell the user they have: files, rows, or broken entries.
    let itemCount: Int
    /// Zero means "cannot be known before running", not "nothing to reclaim".
    let reclaimableBytes: Int64
    /// The database a database task will compact.
    let databaseURL: URL?
    /// Explains an empty result, or a result the count alone would misrepresent.
    let note: String?

    init(
        taskID: MaintenanceTaskID,
        findings: [MaintenanceFinding] = [],
        itemCount: Int? = nil,
        reclaimableBytes: Int64? = nil,
        databaseURL: URL? = nil,
        note: String? = nil
    ) {
        self.taskID = taskID
        self.findings = findings
        self.itemCount = itemCount ?? findings.count
        self.reclaimableBytes = reclaimableBytes ?? findings.reduce(0) { $0 + $1.bytes }
        self.databaseURL = databaseURL
        self.note = note
    }

    var isEmpty: Bool { itemCount == 0 }

    static func empty(_ taskID: MaintenanceTaskID, note: String? = nil) -> MaintenanceReport {
        MaintenanceReport(taskID: taskID, note: note)
    }
}

/// What actually happened when a task ran.
struct MaintenanceResult: Equatable {
    let taskID: MaintenanceTaskID
    let itemsHandled: Int
    let bytesFreed: Int64
    let failures: [String]
    /// True when nothing was really deleted because the app is in debug mode.
    let wasDryRun: Bool
}

/// A maintenance job's identity as the user reads it.
struct MaintenanceTask: Identifiable {
    let id: MaintenanceTaskID
    let title: String
    /// One line: what running this does.
    let summary: String
    /// What the user gives up. Never omitted, even when the answer is "nothing".
    let cost: String
    let risk: CleanupCandidateData.RiskLevel
    /// Some jobs can only be reported on — acting on them belongs to System Settings.
    let isAuditOnly: Bool
    /// Looking costs real time, so it waits to be asked.
    ///
    /// Sweeping a home directory measured over a minute on a machine with cloud-synced
    /// folders in it. Running that the moment the tab opens would make the whole view feel
    /// broken, so an expensive job shows a Check button and stays quiet until pressed.
    var isExpensive: Bool = false
}

/// Runs the maintenance catalog.
///
/// Each task is split into `inspect` and `apply`, and the UI never calls the second
/// without showing the first. That is the same contract the cleanup list keeps: nothing is
/// removed that the user has not already seen listed.
@MainActor
final class MaintenanceService: ObservableObject {
    static let shared = MaintenanceService()

    /// How long something must sit unused before a task offers to remove it.
    static let staleAge: TimeInterval = 30 * 24 * 60 * 60

    /// Ceiling on a single sweep, so a pathological home directory cannot hang the scan.
    private static let maximumFindings = 20_000

    /// Wall-clock budget for one inspection. A sweep that runs out reports what it has.
    static let inspectionBudget: TimeInterval = 20

    @Published private(set) var reports: [MaintenanceTaskID: MaintenanceReport] = [:]
    @Published private(set) var results: [MaintenanceTaskID: MaintenanceResult] = [:]
    @Published private(set) var runningTask: MaintenanceTaskID?
    @Published private(set) var isInspecting = false

    private let fileManager = FileManager.default
    private let loggingService = LoggingService.shared
    private let preferences = PreferencesService.shared
    private let sizer = DirectorySizer()
    private let homeURL = URL(fileURLWithPath: NSHomeDirectory())

    private init() {}

    // MARK: - Catalog

    static let catalog: [MaintenanceTask] = [
        MaintenanceTask(
            id: .savedApplicationState,
            title: "Saved Window State",
            summary: "Remove window layouts kept for apps you have not opened in a month.",
            cost: "Those apps reopen with default windows instead of where you left them.",
            risk: .safe,
            isAuditOnly: false
        ),
        MaintenanceTask(
            id: .brokenLaunchAgents,
            title: "Broken Launch Agents",
            summary: "Remove background-job definitions whose program is no longer on disk.",
            cost: "Nothing runs today that stops running. Each one is already failing to launch.",
            risk: .moderate,
            isAuditOnly: false
        ),
        MaintenanceTask(
            id: .quarantineHistory,
            title: "Download History",
            summary: "Clear Gatekeeper's record of where downloaded files came from.",
            cost: "Finder stops being able to say which app or site a downloaded file came from.",
            risk: .moderate,
            isAuditOnly: false
        ),
        MaintenanceTask(
            id: .notificationHistory,
            title: "Notification History",
            summary: "Delete delivered notifications older than a month from Notification Centre.",
            cost: "Old notifications disappear from Notification Centre. Nothing else changes.",
            risk: .moderate,
            isAuditOnly: false
        ),
        MaintenanceTask(
            id: .finderMetadata,
            title: "Finder Metadata (.DS_Store)",
            summary: "Remove the .DS_Store files Finder scatters through your folders.",
            cost: "Folders lose their icon positions and view settings. Finder writes them again.",
            risk: .safe,
            isAuditOnly: false,
            isExpensive: true
        ),
        MaintenanceTask(
            id: .legacyLoginItems,
            title: "Login Items",
            summary: "Report login items that point at software no longer installed.",
            cost: "Nothing — this only looks.",
            risk: .safe,
            isAuditOnly: true
        )
    ]

    static func task(_ id: MaintenanceTaskID) -> MaintenanceTask {
        // Every identifier in the enum has a catalog entry; the force is a compile-time
        // omission check that fails loudly in development rather than silently in the UI.
        guard let task = catalog.first(where: { $0.id == id }) else {
            fatalError("Maintenance task \(id.rawValue) has no catalog entry")
        }
        return task
    }

    /// True when the app is in debug mode, where nothing is actually deleted.
    var isDryRun: Bool { preferences.loadPreferences().debugMode }

    // MARK: - Inspection

    func inspectAll() async {
        isInspecting = true
        defer { isInspecting = false }

        for task in Self.catalog where !task.isExpensive {
            reports[task.id] = await inspect(task.id)
        }
    }

    func inspect(_ id: MaintenanceTaskID) async -> MaintenanceReport {
        let home = homeURL
        let sizer = self.sizer
        let cutoff = Date().addingTimeInterval(-Self.staleAge)

        let report = await Task.detached(priority: .userInitiated) {
            let inspector = MaintenanceInspector(
                home: home,
                sizer: sizer,
                cutoff: cutoff,
                limit: Self.maximumFindings,
                deadline: Date().addingTimeInterval(Self.inspectionBudget)
            )
            switch id {
            case .savedApplicationState: return inspector.savedApplicationState()
            case .brokenLaunchAgents: return inspector.brokenLaunchAgents()
            case .quarantineHistory: return inspector.quarantineHistory()
            case .notificationHistory: return inspector.notificationHistory()
            case .finderMetadata: return inspector.finderMetadata()
            case .legacyLoginItems: return inspector.legacyLoginItems()
            }
        }.value

        reports[id] = report
        return report
    }

    // MARK: - Running

    /// Applies a task to exactly the findings the user was shown.
    @discardableResult
    func run(_ id: MaintenanceTaskID) async -> MaintenanceResult {
        guard !Self.task(id).isAuditOnly else {
            let result = MaintenanceResult(taskID: id, itemsHandled: 0, bytesFreed: 0, failures: [], wasDryRun: false)
            results[id] = result
            return result
        }

        let report: MaintenanceReport
        if let existing = reports[id] {
            report = existing
        } else {
            report = await inspect(id)
        }
        runningTask = id
        defer { runningTask = nil }

        let dryRun = isDryRun
        let useTrash = preferences.moveToTrashByDefault
        let result: MaintenanceResult

        switch id {
        case .quarantineHistory, .notificationHistory:
            result = await pruneDatabase(for: id, report: report, dryRun: dryRun)
        default:
            result = await removeFiles(for: id, report: report, dryRun: dryRun, useTrash: useTrash)
        }

        loggingService.info(
            "Maintenance \(id.rawValue): \(result.itemsHandled) item(s), "
            + "\(ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file))"
            + (result.wasDryRun ? " (debug mode, nothing removed)" : "")
        )

        results[id] = result
        // The findings just became stale, so the row goes back to "not yet inspected"
        // rather than showing a count that no longer exists.
        reports[id] = nil
        return result
    }

    private func removeFiles(
        for id: MaintenanceTaskID,
        report: MaintenanceReport,
        dryRun: Bool,
        useTrash: Bool
    ) async -> MaintenanceResult {
        let fileManager = self.fileManager
        let findings = report.findings

        return await Task.detached(priority: .userInitiated) {
            var handled = 0
            var freed: Int64 = 0
            var failures: [String] = []

            for finding in findings {
                guard let url = finding.url else { continue }

                if dryRun {
                    handled += 1
                    freed += finding.bytes
                    continue
                }

                do {
                    if useTrash {
                        var resulting: NSURL?
                        try fileManager.trashItem(at: url, resultingItemURL: &resulting)
                    } else {
                        try fileManager.removeItem(at: url)
                    }
                    handled += 1
                    freed += finding.bytes
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }

            return MaintenanceResult(
                taskID: id,
                itemsHandled: handled,
                bytesFreed: freed,
                // A wall of identical permission errors helps nobody; the count does.
                failures: Array(failures.prefix(5)),
                wasDryRun: dryRun
            )
        }.value
    }

    private func pruneDatabase(
        for id: MaintenanceTaskID,
        report: MaintenanceReport,
        dryRun: Bool
    ) async -> MaintenanceResult {
        guard let database = report.databaseURL else {
            return MaintenanceResult(taskID: id, itemsHandled: 0, bytesFreed: 0, failures: [], wasDryRun: dryRun)
        }

        let rowCount = report.itemCount
        if dryRun {
            return MaintenanceResult(taskID: id, itemsHandled: rowCount, bytesFreed: 0, failures: [], wasDryRun: true)
        }

        let table: String
        let column: String
        switch id {
        case .quarantineHistory:
            table = "LSQuarantineEvent"
            column = "LSQuarantineTimeStamp"
        case .notificationHistory:
            table = "record"
            column = "delivered_date"
        default:
            return MaintenanceResult(taskID: id, itemsHandled: 0, bytesFreed: 0, failures: [], wasDryRun: dryRun)
        }

        // Re-derived here rather than carried over from the inspection, so the delete uses
        // the epoch the table is using now and not the one it used a few minutes ago.
        guard let threshold = MaintenanceInspector.storedCutoff(
            database: database,
            table: table,
            column: column,
            cutoff: Date().addingTimeInterval(-Self.staleAge)
        ) else {
            return MaintenanceResult(
                taskID: id,
                itemsHandled: 0,
                bytesFreed: 0,
                failures: ["Could not read \(database.lastPathComponent)."],
                wasDryRun: false
            )
        }

        let statement = "DELETE FROM \(table) WHERE \(column) IS NOT NULL AND \(column) < \(threshold); VACUUM;"

        let sizer = self.sizer
        let before = sizer.allocatedSize(ofFile: database)

        return await Task.detached(priority: .userInitiated) {
            if let failure = MaintenanceInspector.runSQLite(database: database, statement: statement) {
                return MaintenanceResult(taskID: id, itemsHandled: 0, bytesFreed: 0, failures: [failure], wasDryRun: false)
            }

            // The only honest figure is the one measured either side of the compaction.
            let after = sizer.allocatedSize(ofFile: database)
            return MaintenanceResult(
                taskID: id,
                itemsHandled: rowCount,
                bytesFreed: max(0, before - after),
                failures: [],
                wasDryRun: false
            )
        }.value
    }
}
