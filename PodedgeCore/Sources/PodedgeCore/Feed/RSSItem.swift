import Foundation

/// Value type representing an `<item>` element in a podcast RSS feed.
public struct RSSItem: Sendable {
    /// Episode title. Maps to `<title>`.
    public var title: String
    /// Globally unique identifier for the episode. Maps to `<guid>`.
    public var guid: String
    /// Episode description / summary (plain text only — no HTML). Maps to `<description>`.
    public var description: String
    /// Optional HTML description. Maps to `<content:encoded>`.
    public var contentEncoded: String?
    /// Publication date. Maps to `<pubDate>`.
    public var pubDate: Date
    /// URL to the audio enclosure. Maps to `<enclosure url="...">`.
    public var enclosureURL: URL
    /// Byte length of the enclosure file. Maps to `<enclosure length="...">`.
    public var enclosureLength: Int64
    /// MIME type of the enclosure, e.g. `"audio/mpeg"`. Maps to `<enclosure type="...">`.
    public var enclosureType: String
    /// Duration in seconds. Maps to `<itunes:duration>`.
    public var duration: Double?
    /// iTunes episode type. Maps to `<itunes:episodeType>`.
    public var episodeType: EpisodeType
    /// Season number, if applicable. Maps to `<itunes:season>`.
    public var season: Int?
    /// Episode number, if applicable. Maps to `<itunes:episode>`.
    public var episode: Int?
    /// Whether the episode contains explicit content. Maps to `<itunes:explicit>`.
    public var explicit: Bool?
    /// Episode subtitle. Maps to `<itunes:subtitle>`.
    public var subtitle: String?
    /// URL to episode-specific cover art. Maps to `<itunes:image>`.
    public var imageURL: URL?
    /// URL to a Podcasting 2.0 JSON Chapters file. Maps to `<podcast:chapters>`.
    public var chaptersURL: URL?
    /// URL to a VTT transcript file. Maps to `<podcast:transcript>`.
    public var transcriptURL: URL?

    public init(
        title: String,
        guid: String,
        description: String,
        contentEncoded: String? = nil,
        pubDate: Date,
        enclosureURL: URL,
        enclosureLength: Int64,
        enclosureType: String = "audio/mpeg",
        duration: Double? = nil,
        episodeType: EpisodeType = .full,
        season: Int? = nil,
        episode: Int? = nil,
        explicit: Bool? = nil,
        subtitle: String? = nil,
        imageURL: URL? = nil,
        chaptersURL: URL? = nil,
        transcriptURL: URL? = nil
    ) {
        self.title = title
        self.guid = guid
        self.description = description
        self.contentEncoded = contentEncoded
        self.pubDate = pubDate
        self.enclosureURL = enclosureURL
        self.enclosureLength = enclosureLength
        self.enclosureType = enclosureType
        self.duration = duration
        self.episodeType = episodeType
        self.season = season
        self.episode = episode
        self.explicit = explicit
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.chaptersURL = chaptersURL
        self.transcriptURL = transcriptURL
    }
}
