import SwiftUI
import Foundation

// Window manager to handle window state
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    @Published var shouldShowWindow = true
    
    func openWindow() {
        shouldShowWindow = true
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A lightweight Full Disk Access probe shared by app launch and permission re-check UI.
enum FullDiskAccessStatus {
    case granted
    case denied
    case undetermined
}

enum FullDiskAccessDetector {
    private static var protectedDirectoryCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Safari"),
            home.appendingPathComponent("Library/Mail"),
            home.appendingPathComponent("Library/Messages")
        ]
    }

    static func currentStatus(fileManager: FileManager = .default) -> FullDiskAccessStatus {
        var foundProtectedDirectory = false

        for directory in protectedDirectoryCandidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            foundProtectedDirectory = true

            do {
                _ = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                return .granted
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                    return .denied
                }
            } catch {
                continue
            }
        }

        return foundProtectedDirectory ? .denied : .undetermined
    }

    static func hasAccess(fileManager: FileManager = .default) -> Bool {
        switch currentStatus(fileManager: fileManager) {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            // Some systems may not have all probe directories populated; avoid blocking startup on inconclusive checks.
            LoggingService.shared.warning("Full Disk Access check was inconclusive; allowing app startup and deferring permission failures to runtime operations.")
            return true
        }
    }
}

@main
struct MacStorageCleanupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager.shared
    @State private var hasFullDiskAccess = false
    
    init() {
        // Check for full disk access
        _hasFullDiskAccess = State(initialValue: FullDiskAccessDetector.hasAccess())

        // Request notification permissions on app launch
        Task {
            try? await NotificationService.shared.requestAuthorization()
            NotificationService.shared.registerNotificationCategories()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if hasFullDiskAccess {
                MainWindowView()
                    .frame(minWidth: 900, minHeight: 600)
            } else {
                PermissionRequestView(hasPermission: $hasFullDiskAccess)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mac Storage Cleanup") {
                    NSApp.orderFrontStandardAboutPanel()
                }
            }
            
            // The default WindowGroup "New Window" item is left in place: it is the
            // only reliable way to get a window back once SwiftUI has released one,
            // and the app delegate drives it when reopening from the menu bar.
        }
        
        Settings {
            PreferencesView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set only by the menu bar popover's Quit action. Every other quit path
    /// (Cmd+Q, the Quit menu item, closing the last window) keeps the menu bar
    /// session running instead of tearing the process down.
    static var isPerformingFullQuit = false

    /// Windows hidden by `enterMenuBarOnlyMode`, kept so the exact same windows
    /// come back instead of guessing at one from `NSApp.windows`.
    private static var windowsHiddenForMenuBarMode: [NSWindow] = []

    /// Drops the Dock icon and app menu so the app lives on as a menu bar session.
    /// Windows are ordered out rather than closed: SwiftUI releases a closed
    /// WindowGroup window, and there is no reliable way to ask it for a new one
    /// from AppKit, so hiding is what makes reopening work.
    static func enterMenuBarOnlyMode() {
        let windows = NSApp.windows.filter { window in
            window.isVisible && window.canBecomeMain && !window.isKind(of: NSPanel.self)
        }

        for window in windows {
            window.orderOut(nil)
        }

        windowsHiddenForMenuBarMode = windows
        NSApp.setActivationPolicy(.accessory)
    }

    /// Brings the Dock icon and app menu back before a window is shown again.
    static func leaveMenuBarOnlyMode() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
    }

    /// Brings back the windows hidden on the way into menu bar mode.
    /// Returns false when there was nothing to restore.
    @discardableResult
    static func restoreWindowsHiddenForMenuBarMode() -> Bool {
        let windows = windowsHiddenForMenuBarMode
        windowsHiddenForMenuBarMode = []

        guard !windows.isEmpty else { return false }

        for window in windows {
            window.makeKeyAndOrderFront(nil)
        }
        windows.first?.orderFrontRegardless()

        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let showMenuBar = PreferencesService.shared.loadPreferences().showMenuBarIcon
        
        if showMenuBar {
            // Setup menu bar
            MenuBarManager.shared.setupMenuBar()
        }
        
        // Start system monitoring
        SystemStatsService.shared.startMonitoring()
        
        // Sparkle schedules its own checks from launch, including menu bar sessions that
        // never open a window. Touching the service here is what starts it.
        _ = AppUpdaterService.shared
        
        // Offer the memory helper once, after the first launch has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            PrivilegedHelperService.shared.presentFirstRunOfferIfNeeded()
        }
        
        // Listen for show main window notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainWindow),
            name: NSNotification.Name("ShowMainWindow"),
            object: nil
        )
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when last window closes - keep running in menu bar
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Quitting from the popover means the user wants the menu bar gone too.
        if AppDelegate.isPerformingFullQuit {
            return .terminateNow
        }

        // No status item means there is nothing to fall back on, so quit for real.
        guard MenuBarManager.shared.isActive else {
            return .terminateNow
        }

        AppDelegate.enterMenuBarOnlyMode()
        return .terminateCancel
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        
        // Restore the window ourselves and return false so AppKit does not add a
        // second one on top of it.
        showMainWindow()
        return false
    }
    
    @objc func showMainWindow() {
        AppDelegate.leaveMenuBarOnlyMode()
        NSApp.activate(ignoringOtherApps: true)
        
        // Windows parked by a Cmd+Q come back exactly as they were
        if AppDelegate.restoreWindowsHiddenForMenuBarMode() {
            return
        }
        
        // An existing window only counts when it is still on screen; SwiftUI keeps
        // released window objects around, and ordering one of those front does nothing.
        let existingWindow = NSApp.windows.first { window in
            window.canBecomeMain
                && !window.isKind(of: NSPanel.self)
                && (window.isVisible || window.isMiniaturized)
        }
        
        if let existingWindow {
            existingWindow.deminiaturize(nil)
            existingWindow.makeKeyAndOrderFront(nil)
            existingWindow.orderFrontRegardless()
            return
        }
        
        // Nothing left to show, so ask SwiftUI for a fresh window through the
        // WindowGroup's own File > New Window command.
        guard let newWindowItem = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New Window"),
              let action = newWindowItem.action else {
            LoggingService.shared.warning("Could not find the New Window menu item; the main window cannot be reopened.")
            return
        }
        
        NSApp.sendAction(action, to: newWindowItem.target, from: newWindowItem)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        SystemStatsService.shared.stopMonitoring()
    }
}
