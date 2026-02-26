import SwiftUI

@main
struct MacStorageCleanupApp: App {
    init() {
        // Request notification permissions on app launch
        Task {
            try? await NotificationService.shared.requestAuthorization()
            NotificationService.shared.registerNotificationCategories()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainWindowView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
