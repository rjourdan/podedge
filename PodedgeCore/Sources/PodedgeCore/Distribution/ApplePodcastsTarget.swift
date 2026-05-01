import Foundation

/// Guided distribution target for Apple Podcasts.
///
/// Apple Podcasts does not offer a public submission API. The ``submit(feedURL:show:)``
/// method returns a placeholder submission with the guided URL in the `note` field
/// for the UI layer to open.
public struct ApplePodcastsTarget: DistributionTarget, Sendable {

    public let targetID = "apple"
    public let displayName = "Apple Podcasts"
    public let mode: DistributionMode = .guided

    /// The URL the user should visit to submit their podcast to Apple Podcasts.
    public let guidedURL = URL(string: "https://podcasters.apple.com")!

    public init() {}

    // MARK: - DistributionTarget

    public func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        DistributionSubmission(
            externalShowID: "apple-\(show.podcastGUID.uuidString.lowercased())",
            status: .pending,
            note: "Open \(guidedURL.absoluteString) to submit your feed: \(feedURL.absoluteString)"
        )
    }

    public func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        // No API to check — user must confirm manually.
        .pending
    }
}
