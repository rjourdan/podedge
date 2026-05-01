import Foundation

/// Guided distribution target for Spotify.
///
/// Spotify does not offer a public feed submission API. The ``submit(feedURL:show:)``
/// method returns a placeholder submission with the guided URL in the `note` field
/// for the UI layer to open.
public struct SpotifyTarget: DistributionTarget, Sendable {

    public let targetID = "spotify"
    public let displayName = "Spotify"
    public let mode: DistributionMode = .guided

    /// The URL the user should visit to submit their podcast to Spotify.
    public let guidedURL = URL(string: "https://podcasters.spotify.com")!

    public init() {}

    // MARK: - DistributionTarget

    public func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        DistributionSubmission(
            externalShowID: "spotify-\(show.podcastGUID.uuidString.lowercased())",
            status: .pending,
            note: "Open \(guidedURL.absoluteString) to submit your feed: \(feedURL.absoluteString)"
        )
    }

    public func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        .pending
    }
}
