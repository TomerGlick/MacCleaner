import Foundation
import UserNotifications

/// Service for managing macOS notifications
class NotificationService {
    static let shared = NotificationService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    
    private init() {}
    
    /// Requests notification permissions from the user
    func requestAuthorization() async throws {
        try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    /// Sends a notification for scheduled cleanup completion
    /// - Parameters:
    ///   - filesRemoved: Number of files removed
    ///   - spaceFreed: Amount of space freed in bytes
    func notifyScheduledCleanupComplete(filesRemoved: Int, spaceFreed: Int64) {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled Cleanup Complete"
        content.body = "Removed \(filesRemoved) files and freed \(formatBytes(spaceFreed))"
        content.sound = .default
        content.categoryIdentifier = "CLEANUP_COMPLETE"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Sends a notification for scheduled cleanup errors
    /// - Parameters:
    ///   - errorCount: Number of errors encountered
    ///   - errorSummary: Brief summary of errors
    func notifyScheduledCleanupError(errorCount: Int, errorSummary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled Cleanup Error"
        content.body = "\(errorCount) error\(errorCount == 1 ? "" : "s") occurred: \(errorSummary)"
        content.sound = .default
        content.categoryIdentifier = "CLEANUP_ERROR"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Sends a notification for scheduled cleanup warnings
    /// - Parameters:
    ///   - warningCount: Number of warnings
    ///   - warningSummary: Brief summary of warnings
    func notifyScheduledCleanupWarning(warningCount: Int, warningSummary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Scheduled Cleanup Warning"
        content.body = "\(warningCount) warning\(warningCount == 1 ? "" : "s"): \(warningSummary)"
        content.sound = .default
        content.categoryIdentifier = "CLEANUP_WARNING"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Sends a generic notification
    /// - Parameters:
    ///   - title: Notification title
    ///   - body: Notification body
    ///   - category: Optional category identifier
    func sendNotification(title: String, body: String, category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        if let category = category {
            content.categoryIdentifier = category
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Removes all delivered notifications
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }
    
    /// Removes all pending notification requests
    func removeAllPendingNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }
    
    // MARK: - Helper Methods
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Notification Categories

extension NotificationService {
    /// Registers notification categories with actions
    func registerNotificationCategories() {
        let cleanupCompleteCategory = UNNotificationCategory(
            identifier: "CLEANUP_COMPLETE",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        let cleanupErrorCategory = UNNotificationCategory(
            identifier: "CLEANUP_ERROR",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_LOGS",
                    title: "View Logs",
                    options: .foreground
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let cleanupWarningCategory = UNNotificationCategory(
            identifier: "CLEANUP_WARNING",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_DETAILS",
                    title: "View Details",
                    options: .foreground
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            cleanupCompleteCategory,
            cleanupErrorCategory,
            cleanupWarningCategory
        ])
    }
}
