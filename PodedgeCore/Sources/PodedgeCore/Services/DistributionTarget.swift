import Foundation

// MARK: - Supporting Types

/// How a distribution target accepts show submissions.
public enum DistributionMode: String, Codable, Sendable {
    /// Submission is handled programmatically via an API.
    case api
    /// Submission requires manual steps guided by the app.
    case guided
}

/// The result of submitting a show to a distribution directory.
public struct DistributionSubmission: Sendable {
    /// The external identifier assigned by the directory.
    public var externalShowID: String
    /// The current status of the submission.
    public var status: DistributionStatus
    /// An optional human-readable note from the directory.
    public var note: String?

    public init(
        externalShowID: String,
        status: DistributionStatus,
        note: String? = nil
    ) {
        self.externalShowID = externalShowID
        self.status = status
        self.note = note
    }
}

// MARK: - Protocol

/// Abstraction over podcast distribution directories (e.g. Apple Podcasts,
/// Spotify, Podcast Index).
public protocol DistributionTarget: Sendable {
    /// Unique machine-readable identifier (e.g. `"apple"`, `"spotify"`).
    var targetID: String { get }

    /// Human-readable display name for the directory.
    var displayName: String { get }

    /// Whether submission is API-driven or requires guided manual steps.
    var mode: DistributionMode { get }

    /// Submits a show's feed to the distribution directory.
    ///
    /// - Parameters:
    ///   - feedURL: The public URL of the show's RSS feed.
    ///   - show: A sendable snapshot of the show being submitted.
    /// - Returns: The submission result with an external ID and status.
    func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission

    /// Refreshes the submission status for a previously submitted show.
    ///
    /// - Parameter externalShowID: The ID returned by a prior ``submit(feedURL:show:)`` call.
    /// - Returns: The current distribution status.
    func refreshStatus(externalShowID: String) async throws -> DistributionStatus
}
