import Foundation
import SwiftUI

/// A single number for "how is this Mac doing right now", plus the reasons behind it.
///
/// The score exists to be glanceable, so it is deliberately made of things this app can
/// actually measure. CPU temperature is not among them: `SystemStatsService` derives its
/// temperature figure from CPU load, so scoring it would count the same load twice and
/// dress a guess up as a sensor reading. Disk I/O is absent for the same reason — nothing
/// here measures it.
///
/// Every penalty ramps to the end of its range rather than to its own threshold. A penalty
/// that divides by the threshold instead starts shrinking once the threshold is passed,
/// which makes the score climb as the machine gets worse.
struct SystemHealth: Equatable {
    /// 0–100. Higher is better.
    let score: Int
    /// Short phrases naming what cost the most points, worst first. Empty when nothing did.
    let issues: [String]

    enum Band {
        case excellent, good, fair, poor

        var label: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Needs attention"
            }
        }

        var color: Color {
            switch self {
            case .excellent, .good: return .green
            case .fair: return .yellow
            case .poor: return .red
            }
        }
    }

    var band: Band {
        switch score {
        case 85...: return .excellent
        case 65..<85: return .good
        case 45..<65: return .fair
        default: return .poor
        }
    }

    // MARK: - Weights and thresholds

    private enum Weight {
        static let cpu = 30.0
        static let memory = 30.0
        static let disk = 25.0
        static let battery = 15.0
    }

    private enum Threshold {
        static let cpuNormal = 50.0
        static let cpuHigh = 85.0
        static let memoryNormal = 70.0
        static let memoryHigh = 88.0
        static let diskWarn = 80.0
        static let diskCritical = 93.0
        static let batteryWarnCapacity = 80
        static let batteryPoorCapacity = 60
        static let uptimeWarnDays = 7.0
        static let uptimeLongDays = 14.0
    }

    static let unknown = SystemHealth(score: 100, issues: [])

    /// - Parameters:
    ///   - cpuUsage: percent, 0–100.
    ///   - memoryPressure: percent of physical memory in use, 0–100.
    ///   - diskUsedPercent: percent of the boot volume in use, 0–100.
    ///   - batteryMaxCapacity: percent of design capacity, or nil on a desktop.
    ///   - uptime: seconds since boot.
    static func calculate(
        cpuUsage: Double,
        memoryPressure: Double,
        diskUsedPercent: Double,
        batteryMaxCapacity: Int?,
        uptime: TimeInterval
    ) -> SystemHealth {
        var score = 100.0
        var penalties: [(penalty: Double, issue: String)] = []

        let cpu = rampedPenalty(
            value: cpuUsage,
            normal: Threshold.cpuNormal,
            high: Threshold.cpuHigh,
            weight: Weight.cpu
        )
        if cpuUsage > Threshold.cpuHigh {
            penalties.append((cpu, "CPU at \(Int(cpuUsage))%"))
        }
        score -= cpu

        let memory = rampedPenalty(
            value: memoryPressure,
            normal: Threshold.memoryNormal,
            high: Threshold.memoryHigh,
            weight: Weight.memory
        )
        if memoryPressure > Threshold.memoryHigh {
            penalties.append((memory, "Memory pressure at \(Int(memoryPressure))%"))
        }
        score -= memory

        let disk = rampedPenalty(
            value: diskUsedPercent,
            normal: Threshold.diskWarn,
            high: Threshold.diskCritical,
            weight: Weight.disk
        )
        if diskUsedPercent > Threshold.diskWarn {
            penalties.append((disk, "Disk \(Int(diskUsedPercent))% full"))
        }
        score -= disk

        // A desktop has no battery, and a missing battery is not a fault.
        if let capacity = batteryMaxCapacity, capacity > 0 {
            if capacity < Threshold.batteryPoorCapacity {
                score -= Weight.battery
                penalties.append((Weight.battery, "Battery at \(capacity)% of its original capacity"))
            } else if capacity < Threshold.batteryWarnCapacity {
                score -= Weight.battery / 3
                penalties.append((Weight.battery / 3, "Battery at \(capacity)% of its original capacity"))
            }
        }

        // Uptime is not a fault in itself — it is the one thing on this list the user can
        // fix in a minute, so it is worth naming and cheap to penalise.
        let days = uptime / 86_400
        if days >= Threshold.uptimeLongDays {
            score -= 8
            penalties.append((8, "Up for \(Int(days)) days"))
        } else if days >= Threshold.uptimeWarnDays {
            score -= 3
            penalties.append((3, "Up for \(Int(days)) days"))
        }

        let issues = penalties
            .sorted { $0.penalty > $1.penalty }
            .map(\.issue)

        return SystemHealth(score: Int(max(0, min(100, score.rounded()))), issues: issues)
    }

    /// Half the weight is spent getting from `normal` to `high`, the other half getting
    /// from `high` to 100. The two halves meet at `high`, so the penalty rises smoothly and
    /// never falls as the value climbs.
    private static func rampedPenalty(value: Double, normal: Double, high: Double, weight: Double) -> Double {
        guard value > normal else { return 0 }
        let half = weight / 2
        if value <= high {
            return half * (value - normal) / (high - normal)
        }
        return half + half * min(1, (value - high) / (100 - high))
    }
}
