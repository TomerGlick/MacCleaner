import Foundation
import AppKit
import ServiceManagement

/// Installs and talks to the root helper that runs `purge`.
///
/// Registration asks for administrator rights once. macOS then shows the helper
/// under System Settings → General → Login Items, where the user can disable it.
@MainActor
class PrivilegedHelperService: ObservableObject {
    enum HelperError: LocalizedError, Equatable {
        case needsApproval
        case registrationFailed(String)
        case connectionFailed(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .needsApproval:
                return "Allow “Mac Storage Cleanup” in System Settings → General → Login Items, then try again."
            case .registrationFailed(let message):
                return "Could not install the helper: \(message)"
            case .connectionFailed(let message):
                return "Could not reach the helper: \(message)"
            case .commandFailed(let message):
                return message
            }
        }
    }

    static let shared = PrivilegedHelperService()

    @Published private(set) var status: SMAppService.Status = .notRegistered

    private let loggingService = LoggingService.shared
    private var connection: NSXPCConnection?

    private var service: SMAppService {
        SMAppService.daemon(plistName: PrivilegedHelperConstants.daemonPlistName)
    }

    private init() {
        status = service.status
    }

    var isInstalled: Bool {
        status == .enabled
    }

    func refreshStatus() {
        status = service.status
    }

    /// Registers the daemon if needed. Throws `.needsApproval` when the user
    /// still has to flip the switch in System Settings.
    func install() throws {
        let service = self.service

        switch service.status {
        case .enabled:
            status = .enabled
            return
        case .requiresApproval:
            status = .requiresApproval
            throw HelperError.needsApproval
        default:
            break
        }

        do {
            try service.register()
            loggingService.info("Registered privileged helper")
        } catch {
            status = service.status
            loggingService.error("Registering privileged helper failed", error: error)
            throw HelperError.registrationFailed(error.localizedDescription)
        }

        status = service.status
        if status == .requiresApproval {
            throw HelperError.needsApproval
        }
    }

    /// Removes the daemon. The next `install()` asks for authorization again.
    func uninstall() throws {
        invalidateConnection()
        do {
            try service.unregister()
            loggingService.info("Unregistered privileged helper")
        } catch {
            loggingService.error("Unregistering privileged helper failed", error: error)
            throw HelperError.registrationFailed(error.localizedDescription)
        }
        status = service.status
    }

    /// Offers the helper once, on first launch after the feature ships. "Not now" is a
    /// real answer: it is remembered, and Preferences › General keeps the offer around.
    func presentFirstRunOfferIfNeeded() {
        let preferences = PreferencesService.shared
        guard !preferences.hasPromptedForMemoryHelper else { return }

        refreshStatus()
        guard status != .enabled else {
            preferences.hasPromptedForMemoryHelper = true
            return
        }

        preferences.hasPromptedForMemoryHelper = true

        let alert = NSAlert()
        alert.messageText = "Free up memory without a password?"
        alert.informativeText = """
        Mac Storage Cleanup can install a small helper that flushes inactive and cached \
        memory for the Free RAM button. The helper runs one system command and nothing else.

        Installing asks for your administrator password once. You can remove it any time \
        in Preferences › General, or switch it off in System Settings › General › Login Items.
        """
        alert.addButton(withTitle: "Install…")
        alert.addButton(withTitle: "Not now")
        alert.alertStyle = .informational

        // The app usually lives in the menu bar, so the alert needs to be brought forward.
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try install()
            showInformation("Helper installed", "Free RAM now runs without asking for your password.")
        } catch HelperError.needsApproval {
            openLoginItemsSettings()
            showInformation("One more step",
                            HelperError.needsApproval.errorDescription ?? "Approval is needed in System Settings.")
        } catch {
            showInformation("Could not install the helper",
                            "\(error.localizedDescription)\n\nFree RAM still works — it will ask for your password each time.")
        }
    }

    private func showInformation(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Installs the helper if needed, then has it run `purge`.
    func purgeMemory() async throws {
        try install()

        let connection = currentConnection()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // XPC can answer twice — a reply and a connection error — so every
            // path goes through a guard that resumes the continuation once.
            let resumer = SingleResume(continuation: continuation)

            let remote = connection.remoteObjectProxyWithErrorHandler { error in
                resumer.finish(.failure(HelperError.connectionFailed(error.localizedDescription)))
            }

            guard let proxy = remote as? PrivilegedHelperProtocol else {
                resumer.finish(.failure(HelperError.connectionFailed("Unexpected helper interface.")))
                return
            }

            proxy.purgeMemory { success, message in
                if success {
                    resumer.finish(.success(()))
                } else {
                    resumer.finish(.failure(HelperError.commandFailed(message ?? "Could not free memory.")))
                }
            }
        }
    }

    // MARK: - XPC plumbing

    private func currentConnection() -> NSXPCConnection {
        if let connection = connection {
            return connection
        }

        let connection = NSXPCConnection(machServiceName: PrivilegedHelperConstants.machServiceName,
                                         options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.setCodeSigningRequirement(PrivilegedHelperConstants.helperCodeSigningRequirement)

        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }
        connection.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.connection = nil }
        }

        connection.resume()
        self.connection = connection
        return connection
    }

    private func invalidateConnection() {
        connection?.invalidate()
        connection = nil
    }
}

/// XPC can call back twice — once with a reply, once with a connection error.
/// A continuation may only be resumed once.
private final class SingleResume: @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Error>
    private let lock = NSLock()
    private var isFinished = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !isFinished else { return }
        isFinished = true
        continuation.resume(with: result)
    }
}
