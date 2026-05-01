import Foundation
import UserNotifications

/// Manages local notifications for publish success/failure and long-running jobs.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private init() {}

    /// Requests notification authorization from the user.
    func requestAuthorization() async {
        do {
            try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    /// Posts a notification for a successful publish.
    func notifyPublishSuccess(episodeTitle: String) {
        let content = UNMutableNotificationContent()
        content.title = "Episode Published"
        content.body = "\"\(episodeTitle)\" is now live in your RSS feed."
        content.sound = .default
        post(content, identifier: "publish-success-\(UUID().uuidString)")
    }

    /// Posts a notification for a failed publish.
    func notifyPublishFailure(episodeTitle: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "Publish Failed"
        content.body = "\"\(episodeTitle)\" failed: \(reason)"
        content.sound = .default
        post(content, identifier: "publish-failure-\(UUID().uuidString)")
    }

    /// Posts a notification when a long-running job completes.
    func notifyJobComplete(jobKind: String, success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Job Complete" : "Job Failed"
        content.body = "\(jobKind.capitalized) \(success ? "finished successfully" : "encountered an error")."
        content.sound = .default
        post(content, identifier: "job-\(UUID().uuidString)")
    }

    private func post(_ content: UNNotificationContent, identifier: String) {
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
