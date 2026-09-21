import Foundation
import Sparkle

/// Over-the-air updates, backed by Sparkle.
///
/// Sparkle reads the appcast named by `SUFeedURL` and refuses any update whose EdDSA
/// signature does not match `SUPublicEDKey` in Info.plist. That key is separate from the
/// Developer ID certificate, so publishing a release is not by itself enough to push code
/// to anyone.
@MainActor
final class AppUpdaterService: NSObject, ObservableObject {
    static let shared = AppUpdaterService()

    /// The update Sparkle has found, if any. Drives the badge in the main window.
    @Published private(set) var availableUpdate: SUAppcastItem?
    @Published private(set) var canCheckForUpdates = false

    private var updaterController: SPUStandardUpdaterController!
    private let preferences = PreferencesService.shared

    private override init() {
        super.init()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = preferences.checkForUpdatesAutomatically
        // Fetch in the background so the user's click installs rather than waits.
        updater.automaticallyDownloadsUpdates = true

        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    /// Shows Sparkle's update window: progress, release notes, install and relaunch.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Mirrors the Preferences toggle into Sparkle's own scheduling.
    func setAutomaticChecks(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
    }

    var automaticallyChecksForUpdates: Bool {
        updaterController.updater.automaticallyChecksForUpdates
    }
}

extension AppUpdaterService: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.availableUpdate = item }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableUpdate = nil }
    }
}
