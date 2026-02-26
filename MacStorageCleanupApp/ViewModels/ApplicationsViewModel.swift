import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class ApplicationsViewModel: ObservableObject {
    @Published var applications: [Application] = []
    @Published var isLoading = false
    @Published var sortOrder: SortOrder = .size
    @Published var selectedApplication: Application?
    @Published var showUninstallView = false
    @Published var errorMessage: String?
    
    private let applicationManager: ApplicationManager
    
    enum SortOrder {
        case name
        case size
        case lastUsed
    }
    
    init(applicationManager: ApplicationManager = DefaultApplicationManager()) {
        self.applicationManager = applicationManager
    }
    
    var sortedApplications: [Application] {
        switch sortOrder {
        case .name:
            return applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            return applications.sorted { $0.size > $1.size }
        case .lastUsed:
            return applications.sorted { (app1, app2) in
                guard let date1 = app1.lastUsedDate else { return false }
                guard let date2 = app2.lastUsedDate else { return true }
                return date1 > date2
            }
        }
    }
    
    func loadApplications() async {
        isLoading = true
        errorMessage = nil
        
        do {
            applications = await applicationManager.discoverApplications()
        } catch {
            errorMessage = "Failed to load applications: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func selectApplication(_ application: Application) {
        selectedApplication = application
        showUninstallView = true
    }
    
    func dismissUninstallView() {
        showUninstallView = false
        selectedApplication = nil
    }
    
    func refreshAfterUninstall() {
        Task {
            await loadApplications()
        }
    }
    
    // Preview helper
    static var preview: ApplicationsViewModel {
        let vm = ApplicationsViewModel()
        vm.applications = [
            Application(
                bundleURL: URL(fileURLWithPath: "/Applications/Xcode.app"),
                name: "Xcode",
                version: "15.0",
                bundleIdentifier: "com.apple.dt.Xcode",
                size: 15_000_000_000,
                lastUsedDate: Date().addingTimeInterval(-86400 * 2),
                isRunning: false
            ),
            Application(
                bundleURL: URL(fileURLWithPath: "/Applications/Safari.app"),
                name: "Safari",
                version: "17.0",
                bundleIdentifier: "com.apple.Safari",
                size: 250_000_000,
                lastUsedDate: Date(),
                isRunning: true
            ),
            Application(
                bundleURL: URL(fileURLWithPath: "/Applications/Final Cut Pro.app"),
                name: "Final Cut Pro",
                version: "10.7",
                bundleIdentifier: "com.apple.FinalCut",
                size: 8_000_000_000,
                lastUsedDate: Date().addingTimeInterval(-86400 * 30),
                isRunning: false
            ),
            Application(
                bundleURL: URL(fileURLWithPath: "/Applications/Logic Pro.app"),
                name: "Logic Pro",
                version: "10.8",
                bundleIdentifier: "com.apple.logic10",
                size: 5_000_000_000,
                lastUsedDate: Date().addingTimeInterval(-86400 * 7),
                isRunning: false
            )
        ]
        return vm
    }
}
