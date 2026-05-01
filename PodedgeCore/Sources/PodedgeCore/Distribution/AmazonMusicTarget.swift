import Foundation

/// Guided distribution target for Amazon Music / Audible.
///
/// Amazon Music does not offer a public feed submission API. The ``submit(feedURL:show:)``
/// method returns a placeholder submission with the guided URL in the `note` field
/// for the UI layer to open.
public struct AmazonMusicTarget: DistributionTarget, Sendable {

    public let targetID = "amazon"
    public let displayName = "Amazon Music"
    public let mode: DistributionMode = .guided

    /// The URL the user should visit to submit their podcast to Amazon Music.
    public let guidedURL = URL(string: "https://podcasters.amazon.com")!

    public init() {}

    // MARK: - DistributionTarget

    public func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        DistributionSubmission(
            externalShowID: "amazon-\(show.podcastGUID.uuidString.lowercased())",
            status: .pending,
            note: "Open \(guidedURL.absoluteString) to submit your feed: \(feedURL.absoluteString)"
        )
    }

    public func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        .pending
    }
}
