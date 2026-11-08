import SwiftUI

/// The maintenance catalog: look first, then act, one job at a time.
///
/// There is deliberately no "run everything" button. Each job costs the user something
/// different, and a single click that does all six hides which of those costs was paid.
struct MaintenanceView: View {
    @StateObject private var service = MaintenanceService.shared
    @State private var expandedTasks: Set<MaintenanceTaskID> = []
    @State private var confirmingTask: MaintenanceTaskID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(MaintenanceService.catalog) { task in
                        MaintenanceTaskCard(
                            task: task,
                            report: service.reports[task.id],
                            result: service.results[task.id],
                            isRunning: service.runningTask == task.id,
                            isExpanded: expandedTasks.contains(task.id),
                            onInspect: { Task { await service.inspect(task.id) } },
                            onToggleDetail: { toggleDetail(task.id) },
                            onRun: { confirmingTask = task.id }
                        )
                    }
                }
                .padding(16)
            }
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingTask != nil },
                set: { if !$0 { confirmingTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let id = confirmingTask {
                Button("Run", role: .destructive) {
                    confirmingTask = nil
                    Task { await service.run(id) }
                }
            }
            Button("Cancel", role: .cancel) { confirmingTask = nil }
        } message: {
            if let id = confirmingTask {
                Text(MaintenanceService.task(id).cost)
            }
        }
        .task {
            // Inspection only reads, so it can run on arrival without asking.
            if service.reports.isEmpty {
                await service.inspectAll()
            }
        }
    }

    private var confirmationTitle: String {
        guard let id = confirmingTask else { return "" }
        let task = MaintenanceService.task(id)
        let report = service.reports[id]
        let count = report?.itemCount ?? 0
        return "\(task.title): \(count) item\(count == 1 ? "" : "s")"
    }

    private func toggleDetail(_ id: MaintenanceTaskID) {
        if expandedTasks.contains(id) {
            expandedTasks.remove(id)
        } else {
            expandedTasks.insert(id)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maintenance")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Stale system state that no cleanup of caches will reach.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if service.isInspecting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.trailing, 4)
                }

                Button {
                    Task { await service.inspectAll() }
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .disabled(service.isInspecting || service.runningTask != nil)
            }

            if service.isDryRun {
                Label(
                    "Debug mode is on — these jobs report what they would do and change nothing.",
                    systemImage: "ladybug"
                )
                .font(.caption)
                .foregroundColor(.orange)
            }

            Label(
                "Every job here works inside your own Library and never asks for administrator rights.",
                systemImage: "person.crop.circle"
            )
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// One job, with whatever is currently known about it.
private struct MaintenanceTaskCard: View {
    let task: MaintenanceTask
    let report: MaintenanceReport?
    let result: MaintenanceResult?
    let isRunning: Bool
    let isExpanded: Bool
    let onInspect: () -> Void
    let onToggleDetail: () -> Void
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RiskDot(level: task.risk, diameter: 10)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                actionArea
            }

            statusLine

            if let report, !report.findings.isEmpty {
                Button(action: onToggleDetail) {
                    Label(
                        isExpanded ? "Hide the list" : "Show what was found",
                        systemImage: isExpanded ? "chevron.down" : "chevron.right"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)

                if isExpanded {
                    detailList(report)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var actionArea: some View {
        if isRunning {
            ProgressView()
                .controlSize(.small)
        } else if task.isAuditOnly {
            Text("Report only")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if let report, !report.isEmpty {
            Button("Run", action: onRun)
                .buttonStyle(.borderedProminent)
        } else {
            Button("Check", action: onInspect)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let result {
            HStack(spacing: 6) {
                Image(systemName: result.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(result.failures.isEmpty ? .green : .orange)
                Text(resultSummary(result))
                    .font(.caption)
            }
            if !result.failures.isEmpty {
                ForEach(result.failures, id: \.self) { failure in
                    Text(failure)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } else if let report {
            Text(reportSummary(report))
                .font(.caption)
                .foregroundColor(report.isEmpty ? .secondary : .primary)
        } else {
            Text(task.isExpensive
                 ? "Not checked yet — this one walks your folders, so it waits to be asked."
                 : "Not checked yet.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func detailList(_ report: MaintenanceReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // A card is not a file browser: the first twenty answer "is this what I think
            // it is", and the count carries the rest.
            ForEach(report.findings.prefix(20)) { finding in
                HStack {
                    Text(finding.label)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if finding.bytes > 0 {
                        Text(ByteCountFormatter.string(fromByteCount: finding.bytes, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if report.findings.count > 20 {
                Text("and \(report.findings.count - 20) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, 20)
    }

    private func reportSummary(_ report: MaintenanceReport) -> String {
        if report.isEmpty {
            return report.note ?? "Nothing to do."
        }
        var line = "\(report.itemCount) item\(report.itemCount == 1 ? "" : "s")"
        if report.reclaimableBytes > 0 {
            line += " · \(ByteCountFormatter.string(fromByteCount: report.reclaimableBytes, countStyle: .file))"
        }
        if let note = report.note {
            line += " · \(note)"
        }
        return line
    }

    private func resultSummary(_ result: MaintenanceResult) -> String {
        if result.wasDryRun {
            return "Debug mode: would have handled \(result.itemsHandled) item\(result.itemsHandled == 1 ? "" : "s")."
        }
        let freed = ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file)
        let base = "Handled \(result.itemsHandled) item\(result.itemsHandled == 1 ? "" : "s"), freed \(freed)."
        return result.failures.isEmpty ? base : base + " Some items could not be removed:"
    }
}

#Preview {
    MaintenanceView()
        .frame(width: 720, height: 600)
}
