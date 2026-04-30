import Foundation

// MARK: - Supporting Types

/// The rendered promotional content for a social media platform.
public struct PromotionOutput: Sendable {
    /// The promotional text body.
    public var text: String
    /// Suggested hashtags (without the `#` prefix).
    public var hashtags: [String]
    /// Total character count of the rendered output.
    public var characterCount: Int

    public init(text: String, hashtags: [String], characterCount: Int) {
        self.text = text
        self.hashtags = hashtags
        self.characterCount = characterCount
    }
}

// MARK: - Protocol

/// Generates promotional social media copy for an episode.
public protocol PromotionRenderer: Sendable {
    /// The target platform identifier (e.g. `"x"`, `"bluesky"`, `"mastodon"`).
    var platform: String { get }

    /// Maximum character count for the platform, or `nil` if unlimited.
    var maxLength: Int? { get }

    /// Renders promotional content for the given episode.
    ///
    /// - Parameters:
    ///   - episode: A sendable snapshot of the episode to promote.
    ///   - show: A sendable snapshot of the show the episode belongs to.
    ///   - transcript: An optional transcript to inform the copy.
    /// - Returns: The rendered promotional output.
    func render(
        episode: EpisodeSnapshot,
        show: ShowSnapshot,
        transcript: String?
    ) async throws -> PromotionOutput
}
