import XCTest
@testable import MacStorageCleanupApp

final class SystemHealthTests: XCTestCase {
    private func health(
        cpu: Double = 10,
        memory: Double = 40,
        disk: Double = 40,
        battery: Int? = 100,
        uptimeDays: Double = 1
    ) -> SystemHealth {
        SystemHealth.calculate(
            cpuUsage: cpu,
            memoryPressure: memory,
            diskUsedPercent: disk,
            batteryMaxCapacity: battery,
            uptime: uptimeDays * 86_400
        )
    }

    func testAnIdleMachineScoresFull() {
        let result = health()

        XCTAssertEqual(result.score, 100)
        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.band, .excellent)
    }

    func testValuesBelowTheirThresholdCostNothing() {
        XCTAssertEqual(health(cpu: 50).score, 100)
        XCTAssertEqual(health(memory: 70).score, 100)
        XCTAssertEqual(health(disk: 80).score, 100)
    }

    /// The bug this guards against inverts the whole feature: a penalty that ramps to its
    /// own threshold shrinks once the threshold is passed, so the score *rises* as the
    /// machine gets worse.
    func testScoreNeverRisesAsAMetricWorsens() {
        var previous = 101
        for usage in stride(from: 0.0, through: 100.0, by: 1.0) {
            let score = health(cpu: usage).score
            XCTAssertLessThanOrEqual(score, previous, "CPU \(usage)% scored higher than the step before it")
            previous = score
        }

        previous = 101
        for pressure in stride(from: 0.0, through: 100.0, by: 1.0) {
            let score = health(memory: pressure).score
            XCTAssertLessThanOrEqual(score, previous, "Memory \(pressure)% scored higher than the step before it")
            previous = score
        }

        previous = 101
        for used in stride(from: 0.0, through: 100.0, by: 1.0) {
            let score = health(disk: used).score
            XCTAssertLessThanOrEqual(score, previous, "Disk \(used)% scored higher than the step before it")
            previous = score
        }
    }

    func testPenaltyIsContinuousAcrossTheHighThreshold() {
        // A jump at the boundary would make one extra percent of load cost several points.
        let justBelow = health(cpu: 84.9).score
        let justAbove = health(cpu: 85.1).score

        XCTAssertLessThanOrEqual(abs(justBelow - justAbove), 1)
    }

    func testFullyLoadedMachineSpendsTheWholeWeight() {
        let result = health(cpu: 100, memory: 40, disk: 40)

        XCTAssertEqual(result.score, 70, "CPU is worth 30 points")
    }

    func testIssuesAreNamedWorstFirst() {
        let result = health(cpu: 100, memory: 95, disk: 99, battery: 50, uptimeDays: 20)

        XCTAssertEqual(result.issues.count, 5)
        XCTAssertTrue(result.issues[0].hasPrefix("CPU"), "CPU carries the largest weight")
        XCTAssertEqual(result.issues.last, "Up for 20 days")
        XCTAssertEqual(result.band, .poor)
    }

    func testDesktopWithoutABatteryIsNotPenalised() {
        XCTAssertEqual(health(battery: nil).score, 100)
        XCTAssertEqual(health(battery: 0).score, 100, "A zero reading is a missing battery, not a dead one")
    }

    func testWornBatteryCostsMoreThanAnAgeingOne() {
        let ageing = health(battery: 75)
        let worn = health(battery: 50)

        XCTAssertLessThan(worn.score, ageing.score)
        XCTAssertLessThan(ageing.score, 100)
    }

    func testUptimeIsNamedOnceItIsWorthRestartingFor() {
        XCTAssertTrue(health(uptimeDays: 6).issues.isEmpty)
        XCTAssertEqual(health(uptimeDays: 8).issues, ["Up for 8 days"])
        XCTAssertLessThan(health(uptimeDays: 20).score, health(uptimeDays: 8).score)
    }

    func testScoreStaysInRange() {
        let worst = health(cpu: 100, memory: 100, disk: 100, battery: 1, uptimeDays: 90)

        XCTAssertGreaterThanOrEqual(worst.score, 0)
        XCTAssertLessThanOrEqual(worst.score, 100)
    }

    func testBandsFollowTheScore() {
        XCTAssertEqual(SystemHealth(score: 90, issues: []).band, .excellent)
        XCTAssertEqual(SystemHealth(score: 70, issues: []).band, .good)
        XCTAssertEqual(SystemHealth(score: 50, issues: []).band, .fair)
        XCTAssertEqual(SystemHealth(score: 20, issues: []).band, .poor)
    }
}
