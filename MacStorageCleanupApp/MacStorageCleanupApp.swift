import SwiftUI

// Window manager to handle window state
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    @Published var shouldShowWindow = true
    
    func openWindow() {
        shouldShowWindow = true
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MacStorageCleanupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var windowManager = WindowManager.shared
    @State private var hasFullDiskAccess = false
    
    init() {
        // Check for full disk access
        _hasFullDiskAccess = State(initialValue: checkFullDiskAccess())
        
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
    
    private func checkFullDiskAccess() -> Bool {
        // Try to access a protected directory
        let testPath = NSHomeDirectory() + "/Library/Safari"
        let fileManager = FileManager.default
        
        // Try to list contents of Safari directory
        do {
            _ = try fileManager.contentsOfDirectory(atPath: testPath)
            return true
        } catch {
            return false
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check user preference for menu bar icon (default to true)
        let showMenuBar = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        
        if showMenuBar {
            // Setup menu bar
            MenuBarManager.shared.setupMenuBar()
        }
        
        // Start system monitoring
        SystemStatsService.shared.startMonitoring()
        
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
