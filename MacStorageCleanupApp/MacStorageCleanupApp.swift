import SwiftUI

@main
struct MacStorageCleanupApp: App {
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
