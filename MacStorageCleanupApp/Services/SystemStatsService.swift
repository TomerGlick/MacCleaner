import Foundation
import IOKit
import IOKit.ps

class SystemStatsService: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var cpuTemperature: Double = 0
    @Published var memoryPressure: Double = 0
    @Published var memoryUsed: String = "0 GB"
    @Published var memoryTotal: String = "0 GB"
    @Published var availableStorage: String = "0 GB"
    @Published var batteryLevel: Int = 0
    @Published var batteryState: String = "Unknown"
    @Published var batteryHealth: String = "Normal"
    /// Percent of the battery's *design* capacity it can still hold.
    ///
    /// Not `kIOPSMaxCapacityKey`: that reports 100 on every modern Mac, because it is a
    /// percentage of the current full charge rather than of the original one. Reading it as
    /// health means the figure is always perfect and never says anything.
    @Published var batteryMaxCapacity: Int = 100
    @Published var batteryCycleCount: Int = 0
    @Published var networkUpload: String = "0 KB/s"
    @Published var networkDownload: String = "0 KB/s"
    @Published var uptime: String = "0h"
    @Published var uptimeSeconds: TimeInterval = 0
    /// Percent of the boot volume in use. Distinct from `availableStorage`, which is for
    /// reading, not for arithmetic.
    @Published var diskUsedPercent: Double = 0
    /// One glanceable number, recomputed on every tick alongside the figures behind it.
    @Published var health: SystemHealth = .unknown
    /// Nil on a Mac with no battery, which is not a fault and must not be scored as one.
    @Published var batteryIsPresent: Bool = false
    
    private var timer: Timer?
    private var previousNetworkStats: (sent: UInt64, received: UInt64)?
    private let loggingService = LoggingService.shared
    
    static let shared = SystemStatsService()
    
    private init() {
    }
    
    func startMonitoring() {
        guard timer == nil else { return }

        updateStats()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateStats() {
        Task { @MainActor in
            self.cpuUsage = getCPUUsage()
            self.cpuTemperature = getCPUTemperature()
            let memory = getMemoryInfo()
            self.memoryPressure = memory.pressure
            self.memoryUsed = memory.used
            self.memoryTotal = memory.total
            self.availableStorage = getAvailableStorage()
            let battery = getBatteryInfo()
            self.batteryLevel = battery.level
            self.batteryState = battery.state

            let condition = getBatteryCondition()
            self.batteryMaxCapacity = condition.capacityPercent ?? 100
            self.batteryCycleCount = condition.cycleCount ?? 0
            self.batteryHealth = condition.label
            let network = getNetworkStats()
            self.networkUpload = network.upload
            self.networkDownload = network.download
            self.uptime = getUptime()
            self.uptimeSeconds = getUptimeSeconds()
            self.diskUsedPercent = getDiskUsedPercent()
            self.batteryIsPresent = battery.state != "Unknown"

            self.health = SystemHealth.calculate(
                cpuUsage: self.cpuUsage,
                memoryPressure: self.memoryPressure,
                diskUsedPercent: self.diskUsedPercent,
                batteryMaxCapacity: self.batteryIsPresent ? self.batteryMaxCapacity : nil,
                uptime: self.uptimeSeconds
            )
        }
    }
    
    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = task_threads(mach_task_self_, &threadsList, &threadsCount)
        
        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }
                
                guard infoResult == KERN_SUCCESS else { continue }
                
                let threadBasicInfo = threadInfo
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += (Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE)) * 100.0
                }
            }
            
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }
        
        return min(totalUsageOfCPU, 100.0)
    }
    
    private func getCPUTemperature() -> Double {
        // Note: Getting actual CPU temperature requires IOKit and is complex
        // This is a placeholder that estimates based on CPU usage
        return 40.0 + (cpuUsage * 0.3)
    }
    
    private func getMemoryInfo() -> (pressure: Double, used: String, total: String) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return (0, "0 GB", "0 GB")
        }
        
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        
        // Calculate memory pressure more accurately
        // Active + Wired + Compressed gives us the actual memory pressure
        let activeMemory = UInt64(stats.active_count) * UInt64(vm_page_size)
        let wiredMemory = UInt64(stats.wire_count) * UInt64(vm_page_size)
        let compressedMemory = UInt64(stats.compressor_page_count) * UInt64(vm_page_size)
        
        // Memory pressure is based on how much memory is actively being used
        // vs how much is available (free + inactive + purgeable)
        let freeMemory = UInt64(stats.free_count) * UInt64(vm_page_size)
        let inactiveMemory = UInt64(stats.inactive_count) * UInt64(vm_page_size)
        let purgeableMemory = UInt64(stats.purgeable_count) * UInt64(vm_page_size)
        
        let availableMemory = freeMemory + inactiveMemory + purgeableMemory
        let usedMemory = totalMemory - availableMemory
        
        // Pressure calculation: lower when there's more available memory
        let pressure = (Double(usedMemory) / Double(totalMemory)) * 100.0
        
        // For display, include compressed pages alongside active + wired memory.
        let displayUsedMemory = activeMemory + wiredMemory + compressedMemory
        let usedGB = Double(displayUsedMemory) / 1_073_741_824 // 1024^3
        let totalGB = Double(totalMemory) / 1_073_741_824
        
        return (
            pressure,
            String(format: "%.1f GB", usedGB),
            String(format: "%.1f GB", totalGB)
        )
    }
    
    private func getMemoryPressure() -> Double {
        return getMemoryInfo().pressure
    }
    
    private func getAvailableStorage() -> String {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return "0 GB"
        }
        
        do {
            let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let capacity = values.volumeAvailableCapacity {
                // Use decimal (base 10) like Finder and most apps
                let gb = Double(capacity) / 1_000_000_000
                return String(format: "%.2f GB", gb)
            }
        } catch {
            loggingService.error("Error getting storage statistics", error: error)
        }
        
        return "0 GB"
    }
    
    /// Share of the boot volume in use, as a percentage.
    ///
    /// Uses the same "available for important usage" figure Finder reports, so the number
    /// agrees with what the user sees rather than with raw free blocks.
    private func getDiskUsedPercent() -> Double {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
            guard let total = values.volumeTotalCapacity, total > 0 else { return 0 }
            let available = values.volumeAvailableCapacityForImportantUsage ?? 0
            let used = Double(total) - Double(available)
            return max(0, min(100, used / Double(total) * 100))
        } catch {
            loggingService.error("Error reading volume capacity", error: error)
            return 0
        }
    }

    private func getUptimeSeconds() -> TimeInterval {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride

        guard sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0) == 0 else {
            return ProcessInfo.processInfo.systemUptime
        }

        let bootTimeInterval = TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000
        return max(0, Date().timeIntervalSince1970 - bootTimeInterval)
    }

    /// Real battery wear, read from the battery itself.
    ///
    /// `AppleSmartBattery` publishes the charge the pack can still take
    /// (`NominalChargeCapacity`) next to the charge it shipped with (`DesignCapacity`), and
    /// their ratio is the number System Information calls Maximum Capacity. Everything else
    /// available through the power-source API is a percentage of the present full charge,
    /// which cannot fall below 100 no matter how worn the battery is.
    private func getBatteryCondition() -> (capacityPercent: Int?, cycleCount: Int?, label: String) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return (nil, nil, "No battery")
        }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return (nil, nil, "Unknown")
        }

        let design = properties["DesignCapacity"] as? Int
        // NominalChargeCapacity is the modern key; AppleRawMaxCapacity is its predecessor.
        let current = (properties["NominalChargeCapacity"] as? Int) ?? (properties["AppleRawMaxCapacity"] as? Int)
        let cycles = properties["CycleCount"] as? Int
        let hasPermanentFailure = (properties["PermanentFailureStatus"] as? Int ?? 0) != 0

        guard let design, design > 0, let current else {
            return (nil, cycles, "Unknown")
        }

        let percent = Int((Double(current) / Double(design) * 100).rounded())

        let label: String
        if hasPermanentFailure {
            label = "Service Recommended"
        } else if percent >= 80 {
            label = "Normal"
        } else if percent >= 60 {
            label = "Fair"
        } else {
            label = "Service Recommended"
        }

        return (min(100, percent), cycles, label)
    }

    /// Charge level and charging state. Wear is read separately by `getBatteryCondition()`.
    private func getBatteryInfo() -> (level: Int, state: String, health: String, maxCapacity: Int) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any] {
                if let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                   let isCharging = description[kIOPSIsChargingKey] as? Bool {
                    
                    let state = isCharging ? "Charging" : "Fully charged"
                    
                    // Get battery health information
                    var health = "Normal"
                    var maxCapacity = 100
                    
                    // Check for max capacity (battery health)
                    if let maxCap = description[kIOPSMaxCapacityKey] as? Int {
                        maxCapacity = maxCap
                        
                        // Determine health status based on max capacity
                        if maxCap >= 80 {
                            health = "Normal"
                        } else if maxCap >= 60 {
                            health = "Fair"
                        } else {
                            health = "Poor"
                        }
                    }
                    
                    // Check if battery needs service
                    if let batteryHealth = description["BatteryHealth"] as? String {
                        if batteryHealth == "Good" {
                            health = "Normal"
                        } else if batteryHealth == "Fair" {
                            health = "Fair"
                        } else if batteryHealth == "Poor" || batteryHealth == "Check Battery" {
                            health = "Service Recommended"
                        }
                    }
                    
                    return (currentCapacity, state, health, maxCapacity)
                }
            }
        }
        
        return (100, "Unknown", "Normal", 100)
    }
    
    private func getNetworkStats() -> (upload: String, download: String) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        var upload: UInt64 = 0
        var download: UInt64 = 0
        
        guard getifaddrs(&ifaddr) == 0 else {
            return ("0 KB/s", "0 KB/s")
        }
        
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee else { continue }
            let name = String(cString: interface.ifa_name)
            
            // Check for active network interfaces (en0 is typically WiFi, en1 might be Ethernet)
            if name.hasPrefix("en") {
                if let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                    if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                        upload += UInt64(data.ifi_obytes)
                        download += UInt64(data.ifi_ibytes)
                    }
                }
            }
        }
        
        // Calculate rate if we have previous stats
        if let previous = previousNetworkStats {
            // Calculate the difference
            let uploadDiff = upload > previous.sent ? upload - previous.sent : 0
            let downloadDiff = download > previous.received ? download - previous.received : 0
            
            // Store current values for next calculation
            previousNetworkStats = (upload, download)
            
            // Divide by 2 since we update every 2 seconds to get per-second rate
            let uploadRate = uploadDiff / 2
            let downloadRate = downloadDiff / 2
            
            return (formatBytes(uploadRate), formatBytes(downloadRate))
        }
        
        // First run - store values and return 0
        previousNetworkStats = (upload, download)
        return ("0 KB/s", "0 KB/s")
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes == 0 {
            return "0 KB/s"
        } else if bytes < 1024 {
            return "\(bytes) B/s"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB/s", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB/s", Double(bytes) / 1024.0 / 1024.0)
        }
    }
    
    private func getUptime() -> String {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        
        let result = sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0)
        
        guard result == 0 else {
            // Fallback to process uptime if sysctl fails
            let uptime = ProcessInfo.processInfo.systemUptime
            let hours = Int(uptime / 3600)
            let minutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
        
        let bootTimeInterval = TimeInterval(bootTime.tv_sec) + TimeInterval(bootTime.tv_usec) / 1_000_000
        let uptime = Date().timeIntervalSince1970 - bootTimeInterval
        
        let hours = Int(uptime / 3600)
        let minutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
