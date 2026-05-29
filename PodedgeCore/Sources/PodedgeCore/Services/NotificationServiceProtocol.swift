import Foundation

/// Abstraction for delivering publish-related notifications, enabling
/// testability without depending on system notification APIs.
public protocol NotificationServiceProtocol: Sendable {
    /// Notifies the user of a successful episode publication.
    func sendPublishSuccess(episodeTitle: String) async

    /// Notifies the user of a failed episode publication.
    func sendPublishFailure(episodeTitle: String, reason: String) async
}
