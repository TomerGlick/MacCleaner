import Foundation

/// Names shared by the app and the privileged helper.
enum PrivilegedHelperConstants {
    /// launchd label, Mach service name and the helper's bundle identifier.
    static let machServiceName = "com.tomerglick.MacStorageCleanup.helper"

    /// The launchd property list embedded in the app bundle.
    static let daemonPlistName = "com.tomerglick.MacStorageCleanup.helper.plist"

    /// Only a copy of this app, signed by this team, may talk to the helper.
    static let clientCodeSigningRequirement = """
    anchor apple generic \
    and identifier "com.tomerglick.MacStorageCleanup" \
    and certificate leaf[subject.OU] = "D27PA9832J"
    """

    /// The app refuses to talk to any helper that is not the one we shipped.
    static let helperCodeSigningRequirement = """
    anchor apple generic \
    and identifier "com.tomerglick.MacStorageCleanup.helper" \
    and certificate leaf[subject.OU] = "D27PA9832J"
    """
}

/// The complete surface the root helper exposes. Keep it this small.
@objc protocol PrivilegedHelperProtocol {
    /// Runs the system `purge` tool, which needs root.
    func purgeMemory(reply: @escaping (Bool, String?) -> Void)

    /// Version of the installed helper, so the app can spot a stale one.
    func helperVersion(reply: @escaping (String) -> Void)
}
