import Foundation
import MacStorageCleanupCore

/// Looks at the system without changing it.
///
/// Split out of `MaintenanceService` so that every "what is there" decision is a plain
/// value-returning function over an injected home directory and clock, testable without a
/// real Library and without the risk of a test deleting anything.
struct MaintenanceInspector {
    let home: URL
    let sizer: DirectorySizer
    /// Anything untouched since this moment counts as stale.
    let cutoff: Date
    let limit: Int
    /// When a sweep must stop and report what it has. A home directory with cloud-synced
    /// folders in it can take minutes to walk, and a partial answer beats a hung view.
    let deadline: Date
    let fileManager: FileManager

    init(
        home: URL,
        sizer: DirectorySizer,
        cutoff: Date,
        limit: Int,
        deadline: Date = .distantFuture,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.sizer = sizer
        self.cutoff = cutoff
        self.limit = limit
        self.deadline = deadline
        self.fileManager = fileManager
    }

    // MARK: - Saved window state

    func savedApplicationState() -> MaintenanceReport {
        let root = home.appendingPathComponent("Library/Saved Application State")
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty(.savedApplicationState, note: "No saved window state on this Mac.")
        }

        var findings: [MaintenanceFinding] = []
        for entry in entries where entry.pathExtension == "savedState" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified < cutoff else { continue }

            let name = entry.deletingPathExtension().lastPathComponent
            findings.append(MaintenanceFinding(
                url: entry,
                label: name,
                bytes: sizer.allocatedSize(of: entry).bytes
            ))
            if findings.count >= limit { break }
        }

        return MaintenanceReport(taskID: .savedApplicationState, findings: findings.sorted { $0.bytes > $1.bytes })
    }

    // MARK: - Launch agents

    /// Finds per-user launch agents whose executable is gone.
    ///
    /// Only an **absolute** program path is judged. An agent that names a bare command is
    /// resolved against launchd's own search path at load time, which this cannot
    /// reproduce, so those are left alone rather than guessed at.
    func brokenLaunchAgents() -> MaintenanceReport {
        let root = home.appendingPathComponent("Library/LaunchAgents")
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return .empty(.brokenLaunchAgents, note: "You have no per-user launch agents.")
        }

        var findings: [MaintenanceFinding] = []
        var skipped = 0

        for entry in entries where entry.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: entry),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                continue
            }

            // A bundle-relative program is resolved by launchd against a bundle we would
            // have to locate ourselves. Not our call to make.
            if plist["BundleProgram"] != nil { continue }

            guard let program = Self.programPath(from: plist) else {
                skipped += 1
                continue
            }
            guard program.hasPrefix("/") else {
                skipped += 1
                continue
            }
            guard !fileManager.fileExists(atPath: program) else { continue }

            findings.append(MaintenanceFinding(
                url: entry,
                label: "\(entry.deletingPathExtension().lastPathComponent) → \(program)",
                bytes: sizer.allocatedSize(ofFile: entry)
            ))
        }

        let note = skipped > 0
            ? "\(skipped) agent\(skipped == 1 ? "" : "s") name a command rather than a path, so they were left alone."
            : nil
        return MaintenanceReport(taskID: .brokenLaunchAgents, findings: findings, note: note)
    }

    static func programPath(from plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String, !program.isEmpty {
            return program
        }
        if let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first, !first.isEmpty {
            return first
        }
        return nil
    }

    // MARK: - Databases

    func quarantineHistory() -> MaintenanceReport {
        let database = home.appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
        return databaseReport(
            taskID: .quarantineHistory,
            database: database,
            table: "LSQuarantineEvent",
            column: "LSQuarantineTimeStamp",
            emptyNote: "Gatekeeper has no download history on this Mac.",
            unit: "download record"
        )
    }

    func notificationHistory() -> MaintenanceReport {
        guard let database = Self.notificationDatabase(home: home, fileManager: fileManager) else {
            return .empty(.notificationHistory, note: "Notification Centre keeps no history on this Mac.")
        }
        return databaseReport(
            taskID: .notificationHistory,
            database: database,
            table: "record",
            column: "delivered_date",
            emptyNote: "Notification Centre keeps no history here.",
            unit: "delivered notification"
        )
    }

    /// Notification Centre moved house in macOS 15. Both addresses are checked, so a newer
    /// system is not reported as having no history at all.
    static func notificationDatabase(home: URL, fileManager: FileManager) -> URL? {
        let groupDatabase = home.appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        if fileManager.fileExists(atPath: groupDatabase.path) { return groupDatabase }

        guard let darwinDirectory = ProcessInfo.processInfo.environment["TMPDIR"].map({ ($0 as NSString).deletingLastPathComponent }) else {
            return nil
        }
        let legacy = URL(fileURLWithPath: darwinDirectory)
            .appendingPathComponent("com.apple.notificationcenter/db2/db")
        return fileManager.fileExists(atPath: legacy.path) ? legacy : nil
    }

    private func databaseReport(
        taskID: MaintenanceTaskID,
        database: URL,
        table: String,
        column: String,
        emptyNote: String,
        unit: String
    ) -> MaintenanceReport {
        guard fileManager.fileExists(atPath: database.path) else {
            return .empty(taskID, note: emptyNote)
        }
        guard fileManager.isExecutableFile(atPath: Self.sqlitePath) else {
            return .empty(taskID, note: "The sqlite3 tool is missing, so this cannot be read.")
        }
        guard let threshold = Self.storedCutoff(database: database, table: table, column: column, cutoff: cutoff) else {
            return .empty(taskID, note: Self.unreadableNote(for: database))
        }

        let countQuery = "SELECT count(*) FROM \(table) WHERE \(column) IS NOT NULL AND \(column) < \(threshold);"
        guard let output = Self.querySQLite(database: database, statement: countQuery),
              let rows = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .empty(taskID, note: Self.unreadableNote(for: database))
        }
        guard rows > 0 else {
            return .empty(taskID, note: "Nothing older than a month.")
        }

        return MaintenanceReport(
            taskID: taskID,
            itemCount: rows,
            // Compacting a database frees an amount that depends on its internal free
            // pages. Guessing here would be a number the user could check and catch.
            reclaimableBytes: 0,
            databaseURL: database,
            note: "\(rows) \(unit)\(rows == 1 ? "" : "s") older than a month. The database is compacted afterwards; the space freed is measured then."
        )
    }

    // MARK: - Finder metadata

    /// Sweeps the user's own folders for `.DS_Store`.
    ///
    /// Library is skipped because Finder metadata there belongs to app-managed folders, and
    /// version-control and dependency directories are skipped because touching them churns
    /// a diff or a checksum for no gain.
    func finderMetadata() -> MaintenanceReport {
        let skipped: Set<String> = [
            "Library", ".Trash", "node_modules", ".git", "Pods",
            "DerivedData", ".build", "Applications"
        ]

        var findings: [MaintenanceFinding] = []
        var ranOutOfTime = false
        var checked = 0

        let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey],
            options: [.skipsPackageDescendants]
        )

        while let entry = enumerator?.nextObject() as? URL {
            // Checking the clock on every entry would cost more than the walk; every few
            // thousand entries is often enough to stop within a second of the budget. The
            // first entry is checked too, so an already-expired budget stops at once.
            checked += 1
            if checked % 2048 == 1, Date() >= deadline {
                ranOutOfTime = true
                break
            }

            let name = entry.lastPathComponent

            if skipped.contains(name) {
                enumerator?.skipDescendants()
                continue
            }
            // Deep trees below a few levels are somebody's project, not a place a user
            // browses in Finder, and walking all of them turns a click into a minute.
            if enumerator?.level ?? 0 > 6 {
                enumerator?.skipDescendants()
                continue
            }
            guard name == ".DS_Store" else { continue }

            findings.append(MaintenanceFinding(
                url: entry,
                label: (entry.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                bytes: sizer.allocatedSize(ofFile: entry)
            ))
            if findings.count >= limit { break }
        }

        let note = ranOutOfTime
            ? "Stopped after \(Int(MaintenanceService.inspectionBudget)) seconds — this is what was found so far."
            : nil
        return MaintenanceReport(taskID: .finderMetadata, findings: findings, note: note)
    }

    // MARK: - Login items

    /// Reports legacy login items whose target is missing.
    ///
    /// Only the old `com.apple.loginitems` list can be read without root. Items registered
    /// the modern way live in a database only `sfltool` can open as root, so this says so
    /// rather than pretending the list is complete.
    func legacyLoginItems() -> MaintenanceReport {
        let plistURL = home.appendingPathComponent("Library/Preferences/com.apple.loginitems.plist")
        let coverageNote = "Only the legacy login-item list can be read without administrator rights. Items added by modern apps are managed in System Settings → General → Login Items."

        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let session = plist["SessionItems"] as? [String: Any],
              let items = session["CustomListItems"] as? [[String: Any]] else {
            return .empty(.legacyLoginItems, note: coverageNote)
        }

        var findings: [MaintenanceFinding] = []
        for item in items {
            let name = item["Name"] as? String ?? "Unnamed item"
            guard let bookmark = item["Bookmark"] as? Data else { continue }

            var isStale = false
            let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if let resolved, fileManager.fileExists(atPath: resolved.path) { continue }

            findings.append(MaintenanceFinding(
                url: nil,
                label: resolved.map { "\(name) → \($0.path)" } ?? name,
                bytes: 0
            ))
        }

        let note = findings.isEmpty
            ? "No broken legacy login items. " + coverageNote
            : "Remove these in System Settings → General → Login Items. " + coverageNote
        return MaintenanceReport(taskID: .legacyLoginItems, findings: findings, reclaimableBytes: 0, note: note)
    }

    /// Why a database could not be read.
    ///
    /// Another app's group container is not covered by Full Disk Access — macOS 15 moved
    /// Notification Centre's database into one and no permission a user can grant opens it
    /// again. Telling them to go and switch on a permission they may already have, for a
    /// door it does not unlock, is worse than saying nothing.
    static func unreadableNote(for database: URL) -> String {
        if database.path.contains("/Group Containers/") {
            return "macOS does not let other apps read this database, and no permission changes that."
        }
        return "Could not read the database. Grant Full Disk Access, or close the app that has it open."
    }

    // MARK: - SQLite

    static let sqlitePath = "/usr/bin/sqlite3"

    /// The same instant expressed the way the table already expresses time.
    ///
    /// These are Apple's private databases and the epoch is not documented or stable:
    /// quarantine records use Apple's 2001 reference date, and Notification Centre has been
    /// seen storing Unix time. Assuming the wrong one does not fail loudly — it silently
    /// makes the cutoff match every row in the table and deletes the lot. So the epoch is
    /// read off the data instead of assumed: no timestamp in Apple's epoch can be as large
    /// as a present-day Unix timestamp.
    static func storedCutoff(database: URL, table: String, column: String, cutoff: Date) -> Int? {
        guard let output = querySQLite(database: database, statement: "SELECT max(\(column)) FROM \(table);") else {
            return nil
        }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let newest = Double(trimmed) ?? 0
        let usesUnixEpoch = newest > unixEpochDiscriminator

        return usesUnixEpoch ? Int(cutoff.timeIntervalSince1970) : Int(cutoff.timeIntervalSinceReferenceDate)
    }

    /// Comfortably above any Apple-epoch timestamp (2001-based time will not reach this
    /// until the year 2039) and below every Unix timestamp since 2001.
    static let unixEpochDiscriminator: Double = 1_200_000_000

    /// Runs a read-only query and returns its output, or nil when it failed.
    static func querySQLite(database: URL, statement: String) -> String? {
        run(arguments: ["-readonly", database.path, statement])?.output
    }

    /// Runs a modifying statement. Returns an error message, or nil on success.
    static func runSQLite(database: URL, statement: String) -> String? {
        guard let outcome = run(arguments: [database.path, statement]) else {
            return "Could not run sqlite3."
        }
        guard outcome.status == 0 else {
            return outcome.error.isEmpty ? "sqlite3 exited with status \(outcome.status)." : outcome.error
        }
        return nil
    }

    private static func run(arguments: [String]) -> (output: String, error: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlitePath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outData, encoding: .utf8) ?? ""
        let error = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 && arguments.contains("-readonly") {
            return nil
        }
        return (output, error, process.terminationStatus)
    }
}
