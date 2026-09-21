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
            
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    WindowManager.shared.openWindow()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        
        Settings {
            PreferencesView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let showMenuBar = PreferencesService.shared.loadPreferences().showMenuBarIcon
        
        if showMenuBar {
            // Setup menu bar
            MenuBarManager.shared.setupMenuBar()
        }
        
        // Start system monitoring
        SystemStatsService.shared.startMonitoring()
        
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
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // If no windows are visible, show the main window
            showMainWindow()
        }
        return true
    }
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // Find and show existing windows
        let windows = NSApp.windows.filter { window in
            // Filter out utility windows (like popovers)
            return window.canBecomeMain && !window.isKind(of: NSPanel.self)
        }
        
        if let mainWindow = windows.first {
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
        } else {
            // No main window exists - need to create one
            // Use the new window action
            if let newWindowAction = NSApp.mainMenu?.item(withTitle: "File")?.submenu?.item(withTitle: "New Window") {
                NSApp.sendAction(newWindowAction.action!, to: newWindowAction.target, from: nil)
            } else {
                // Fallback: Try to trigger window creation via WindowGroup
                // This is a workaround for SwiftUI apps
                DispatchQueue.main.async {
                    WindowManager.shared.openWindow()
                }
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        SystemStatsService.shared.stopMonitoring()
    }
}
