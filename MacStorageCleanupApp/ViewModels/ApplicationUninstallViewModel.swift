import SwiftUI
import Foundation
import MacStorageCleanupCore

@MainActor
class ApplicationUninstallViewModel: ObservableObject {
    @Published var application: Application
    @Published var associatedFiles: [FileMetadata] = []
    @Published var isLoadingAssociatedFiles = true
    @Published var removeAssociatedFiles = true
    @Published var isUninstalling = false
    @Published var showConfirmation = false
    @Published var uninstallResult: UninstallResult?
    @Published var errorMessage: String?
    
    private let applicationManager: ApplicationManager
    
    var totalSpaceToFree: Int64 {
        var total = application.size
        if removeAssociatedFiles {
            total += associatedFiles.reduce(0) { $0 + $1.size }
        }
        return total
    }
    
    var formattedTotalSpace: String {
        ByteCountFormatter.string(fromByteCount: totalSpaceToFree, countStyle: .file)
    }
    
    var canUninstall: Bool {
        !application.isRunning && !isUninstalling
    }
    
    init(application: Application, applicationManager: ApplicationManager = DefaultApplicationManager()) {
        self.application = application
        self.applicationManager = applicationManager
    }
    
    func loadAssociatedFiles() async {
        isLoadingAssociatedFiles = true
        associatedFiles = await applicationManager.findAssociatedFiles(for: application)
        isLoadingAssociatedFiles = false
    }
    
    func requestUninstall() {
        if application.isRunning {
            errorMessage = "Please quit \(application.name) before uninstalling."
            return
        }
        showConfirmation = true
    }
    
    func performUninstall() async {
        isUninstalling = true
        errorMessage = nil
        showConfirmation = false
        
        do {
            let result = try await applicationManager.uninstall(
                application: application,
                removeAssociatedFiles: removeAssociatedFiles
            )
            uninstallResult = result
        } catch let error as UninstallError {
            switch error {
            case .applicationRunning(let name):
                errorMessage = "Cannot uninstall \(name) while it is running. Please quit the application first."
            case .applicationNotFound(let path):
                errorMessage = "Application not found at \(path)"
            case .permissionDenied:
                errorMessage = "Permission denied. You may need administrator privileges to uninstall this application."
            case .partialUninstall(let removed, let failed):
                errorMessage = "Partial uninstall: \(removed) files removed, \(failed) files failed."
            case .unknown(let message):
                errorMessage = "Uninstall failed: \(message)"
            }
        } catch {
            errorMessage = "Unexpected error: \(error.localizedDescription)"
        }
        
        isUninstalling = false
    }
    
    func cancelConfirmation() {
        showConfirmation = false
    }
}
