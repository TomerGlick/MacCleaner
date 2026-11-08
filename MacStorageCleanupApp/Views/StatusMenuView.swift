import SwiftUI

/// The menu bar popover.
///
/// Everything here has to be visible without scrolling: this is a panel that appears under
/// a click and disappears on the next one, and a stat you have to scroll to find is a stat
/// you will not look at. So the layout is fixed — a header, one storage row and a 3×2 grid
/// of equal tiles — and any new stat has to earn its place by replacing one of them.
struct StatusMenuView: View {
    @StateObject private var statsService = SystemStatsService.shared
    @StateObject private var memoryService = MemoryCleanupService.shared
    @State private var machineName = Host.current().localizedName ?? "MacBook"

    /// Three across, two down. The tile size follows from the popover width.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 10) {
                StorageRow(
                    available: statsService.availableStorage,
                    usedPercent: statsService.diskUsedPercent,
                    action: openAppAndScan
                )

                LazyVGrid(columns: columns, spacing: 10) {
                    StatTile(
                        icon: "clock",
                        title: "Uptime",
                        value: statsService.uptime,
                        subtitle: "Since boot"
                    )

                    StatTile(
                        icon: "memorychip",
                        title: "Memory",
                        value: statsService.memoryUsed,
                        subtitle: "Pressure \(Int(statsService.memoryPressure))%",
                        actionText: memoryService.isFreeingMemory ? "Freeing…" : "Free RAM",
                        action: freeUpMemory,
                        isActionDisabled: memoryService.isFreeingMemory
                    )

                    StatTile(
                        icon: "cpu",
                        title: "CPU",
                        value: "\(Int(statsService.cpuUsage))%",
                        subtitle: "\(Int(statsService.cpuTemperature))°C est."
                    )

                    StatTile(
                        icon: "wifi",
                        title: "Network",
                        value: "↓ \(statsService.networkDownload)",
                        subtitle: "↑ \(statsService.networkUpload)"
                    )

                    StatTile(
                        icon: "heart.fill",
                        title: "Battery Health",
                        value: "\(statsService.batteryMaxCapacity)%",
                        subtitle: statsService.batteryCycleCount > 0
                            ? "\(statsService.batteryCycleCount) cycles"
                            : statsService.batteryHealth
                    )

                    StatTile(
                        icon: "battery.100",
                        title: "Battery",
                        value: "\(statsService.batteryLevel)%",
                        subtitle: statsService.batteryState
                    )
                }
            }
            .padding(14)

            // Reserved rather than conditional: a line appearing and vanishing would
            // resize the popover under the pointer mid-click.
            Text(memoryService.statusMessage ?? " ")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)

            Spacer(minLength: 0)

            footer
        }
        .frame(width: 400, height: StatusMenuView.popoverHeight)
        .background(Color(NSColor.windowBackgroundColor))
    }

    /// Kept next to the layout it describes, so the popover cannot be sized from a guess.
    static let popoverHeight: CGFloat = 520

    private var header: some View {
        HStack(spacing: 14) {
            HealthRing(health: statsService.health)

            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Storage Cleanup")
                    .font(.headline)
                    .foregroundColor(.white)

                Text(machineName)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))

                Text(statsService.health.issues.first ?? "Nothing needs attention")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .help(statsService.health.issues.isEmpty
                          ? "Nothing needs attention"
                          : statsService.health.issues.joined(separator: "\n"))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.cyan.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: openMainApp) {
                Text("Open Mac Storage Cleanup")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button(action: quitApp) {
                Label("Quit", systemImage: "power")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Quit Mac Storage Cleanup")
        }
        .padding(14)
    }

    private func openAppAndScan() {
        // Post notification to trigger scan
        NotificationCenter.default.post(name: NSNotification.Name("StartStorageScan"), object: nil)

        // Open main app
        openMainApp()
    }

    private func freeUpMemory() {
        Task {
            await memoryService.freeUpMemory()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            memoryService.clearStatusMessage()
        }
    }

    private func quitApp() {
        MenuBarManager.shared.togglePopover()
        // The only path that really tears the process down; Cmd+Q just hides
        // the windows and leaves the menu bar session running.
        AppDelegate.allowsTermination = true
        NSApp.terminate(nil)
    }

    private func openMainApp() {
        // Close the popover first
        MenuBarManager.shared.togglePopover()

        // The app delegate owns window restoration: it leaves menu bar only mode,
        // brings back windows parked by a Cmd+Q, and creates one if none exist.
        NotificationCenter.default.post(name: NSNotification.Name("ShowMainWindow"), object: nil)
    }
}

/// Disk space, given a full row because it is the one number this app exists for.
private struct StorageRow: View {
    let available: String
    let usedPercent: Double
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "internaldrive")
                .font(.title3)
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text("Macintosh HD")
                    .font(.subheadline.weight(.semibold))
                Text("\(available) free · \(Int(usedPercent))% used")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: action) {
                Text("Free Up")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

/// One stat. Every tile is the same height whether or not it carries a button, so the grid
/// stays a grid instead of two rows of different depths.
private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    var actionText: String? = nil
    var action: (() -> Void)? = nil
    var isActionDisabled: Bool = false

    private static let height: CGFloat = 96

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .lineLimit(1)

            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let actionText, let action {
                Button(action: action) {
                    Text(actionText)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(isActionDisabled ? .secondary : .blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(isActionDisabled ? 0.05 : 0.12))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(isActionDisabled)
                .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .padding(.horizontal, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

/// The health score as a ring that fills with the score and takes its colour from the band.
private struct HealthRing: View {
    let health: SystemHealth

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 5)

            Circle()
                .trim(from: 0, to: CGFloat(health.score) / 100)
                .stroke(health.band.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: health.score)

            VStack(spacing: 0) {
                Text("\(health.score)")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text(health.band.label)
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)
        }
        .frame(width: 62, height: 62)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System health \(health.score) out of 100, \(health.band.label)")
    }
}

#Preview {
    StatusMenuView()
}
