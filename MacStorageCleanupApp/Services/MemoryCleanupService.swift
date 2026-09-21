import Foundation

/// Frees inactive and cached memory by running the system `purge` tool.
///
/// macOS reclaims memory on its own, so this mostly helps after a large job
/// leaves the file cache full. It needs administrator rights because `purge`
/// is root-only.
@MainActor
class MemoryCleanupService: ObservableObject {
    enum CleanupError: LocalizedError {
        case toolMissing
        case cancelled
        case needsApproval
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .toolMissing:
                return "The system purge tool is not available on this Mac."
            case .cancelled:
                return "Freeing memory was cancelled."
            case .needsApproval:
                return "Allow “Mac Storage Cleanup” in System Settings → General → Login Items, then try again."
            case .failed(let message):
                return message.isEmpty ? "Could not free memory." : message
            }
        }
    }

    static let shared = MemoryCleanupService()

    @Published private(set) var isFreeingMemory = false
    @Published private(set) var statusMessage: String?

    private let purgeToolPath = "/usr/sbin/purge"
    private let loggingService = LoggingService.shared

    private init() {
    }

    /// Runs `purge` and reports how much memory became available.
    @discardableResult
    func freeUpMemory() async -> Result<UInt64, CleanupError> {
        guard !isFreeingMemory else {
            return .failure(.failed("Already freeing memory."))
        }

        isFreeingMemory = true
        statusMessage = "Freeing memory…"
        defer { isFreeingMemory = false }

        let availableBefore = Self.availableMemoryBytes()
        let outcome = await runPurge()

        switch outcome {
        case .failure(let error):
            statusMessage = error == .cancelled ? nil : error.errorDescription
            if error != .cancelled {
                loggingService.error("Freeing memory failed: \(error.errorDescription ?? "unknown error")")
            }
            return .failure(error)

        case .success:
            let availableAfter = Self.availableMemoryBytes()
            let freed = availableAfter > availableBefore ? availableAfter - availableBefore : 0
            statusMessage = freed > 0 ? "Freed \(Self.formatBytes(freed)) of memory" : "Memory is already compact"
            loggingService.info("Freed \(freed) bytes of memory")
            return .success(freed)
        }
    }

    /// Prefers the installed root helper, which runs without a password. Falls
    /// back to a one-off authorization prompt when the helper is unavailable.
    private func runPurge() async -> Result<Void, CleanupError> {
        do {
            try await PrivilegedHelperService.shared.purgeMemory()
            return .success(())
        } catch PrivilegedHelperService.HelperError.needsApproval {
            PrivilegedHelperService.shared.openLoginItemsSettings()
            return .failure(.needsApproval)
        } catch {
            loggingService.warning("Helper purge unavailable, asking for authorization instead: \(error.localizedDescription)")
        }

        let toolPath = purgeToolPath
        return await Task.detached(priority: .userInitiated) {
            MemoryCleanupService.runPurgeWithAuthorization(at: toolPath)
        }.value
    }

    func clearStatusMessage() {
        statusMessage = nil
    }

    // MARK: - Helpers

    private nonisolated static func runPurgeWithAuthorization(at toolPath: String) -> Result<Void, CleanupError> {
        guard FileManager.default.isExecutableFile(atPath: toolPath) else {
            return .failure(.toolMissing)
        }

        // `purge` needs root, so ask the system for an authorization prompt.
        let script = "do shell script \"\(toolPath)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus != 0 else {
            return .success(())
        }

        let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if message.contains("-128") || message.localizedCaseInsensitiveContains("User canceled") {
            return .failure(.cancelled)
        }
        return .failure(.failed(message))
    }

    /// Free, inactive, purgeable and speculative pages: what `purge` can hand back.
    private static func availableMemoryBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(vm_page_size)
        let pages = UInt64(stats.free_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.purgeable_count)
            + UInt64(stats.speculative_count)
        return pages * pageSize
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }
}

extension MemoryCleanupService.CleanupError: Equatable {
    static func == (lhs: MemoryCleanupService.CleanupError, rhs: MemoryCleanupService.CleanupError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
