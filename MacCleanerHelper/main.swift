import Foundation

/// Root daemon behind `SMAppService`. It exposes exactly one action — running
/// `/usr/sbin/purge` — and accepts connections only from the signed app.
final class HelperDelegate: NSObject, NSXPCListenerDelegate, PrivilegedHelperProtocol {
    static let version = "1.0"

    private let purgeToolPath = "/usr/sbin/purge"

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // A root service must not talk to anyone but our own app.
        connection.setCodeSigningRequirement(PrivilegedHelperConstants.clientCodeSigningRequirement)
        connection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - PrivilegedHelperProtocol

    func purgeMemory(reply: @escaping (Bool, String?) -> Void) {
        // Fixed path, no arguments: nothing the caller sends reaches the shell.
        guard FileManager.default.isExecutableFile(atPath: purgeToolPath) else {
            reply(false, "The system purge tool is not available on this Mac.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: purgeToolPath)
        process.arguments = []

        let errorPipe = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            reply(false, error.localizedDescription)
            return
        }

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            reply(true, nil)
        } else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            reply(false, message.isEmpty ? "purge exited with status \(process.terminationStatus)." : message)
        }
    }

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(HelperDelegate.version)
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: PrivilegedHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
