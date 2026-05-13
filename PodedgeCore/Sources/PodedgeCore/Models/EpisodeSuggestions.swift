import Foundation
import SwiftData

/// Persisted snapshot of AI-generated metadata suggestions for an episode.
///
/// Stores the output of ``MetadataGenerationService`` so the user can review,
/// edit, and apply suggestions without re-running the LLM.
@Model public final class EpisodeSuggestions {
    /// Unique identifier for this suggestion set.
    @Attribute(.unique) public var id: UUID

    /// The episode these suggestions belong to.
    public var episodeID: UUID

    /// Timestamp when the suggestions were generated.
    public var generatedAt: Date

    /// AI-suggested episode title.
    public var suggestedTitle: String

    /// AI-suggested episode subtitle.
    public var suggestedSubtitle: String

    /// AI-suggested HTML description for podcast directories.
    public var suggestedDescriptionHTML: String

    /// JSON-encoded array of keyword strings.
    public var keywordsJSON: String

    /// JSON-encoded array of ``GeneratedChapter`` values.
    public var chaptersJSON: String

    /// Promotional blurb for Twitter/X (max 280 characters).
    public var blurbTwitter: String

    /// Promotional blurb for LinkedIn.
    public var blurbLinkedIn: String

    /// Promotional blurb for Mastodon (max 500 characters).
    public var blurbMastodon: String

    /// Promotional blurb for Bluesky.
    public var blurbBluesky: String

    /// Promotional blurb for Threads.
    public var blurbThreads: String

    /// Creates a new suggestions record from generated metadata.
    ///
    /// - Parameters:
    ///   - episodeID: The identifier of the episode these suggestions target.
    ///   - metadata: The generated metadata returned by ``MetadataGenerationService``.
    public init(episodeID: UUID, metadata: GeneratedMetadata) {
        self.id = UUID()
        self.episodeID = episodeID
        self.generatedAt = Date()
        self.suggestedTitle = metadata.title
        self.suggestedSubtitle = metadata.subtitle
        self.suggestedDescriptionHTML = metadata.descriptionHTML
        self.keywordsJSON = Self.encode(metadata.keywords)
        self.chaptersJSON = Self.encode(metadata.chapters)
        self.blurbTwitter = metadata.blurbs.twitter
        self.blurbLinkedIn = metadata.blurbs.linkedin
        self.blurbMastodon = metadata.blurbs.mastodon
        self.blurbBluesky = metadata.blurbs.mastodon   // v1: derived from mastodon
        self.blurbThreads = metadata.blurbs.mastodon   // v1: derived from mastodon
    }

    // MARK: - Computed Properties

    /// Decoded keyword strings from the stored JSON.
    public var keywords: [String] {
        guard let data = keywordsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Decoded chapter markers from the stored JSON.
    public var chapters: [GeneratedChapter] {
        guard let data = chaptersJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([GeneratedChapter].self, from: data)) ?? []
    }

    // MARK: - Private

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
