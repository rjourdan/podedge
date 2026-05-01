import Foundation

/// Value type representing the `<channel>` element of a podcast RSS feed.
public struct RSSChannel: Sendable {
    /// Show title. Maps to `<title>`.
    public var title: String
    /// URL of the show's website or feed landing page. Maps to `<link>`.
    public var link: URL
    /// Show description / summary (plain text only — no HTML). Maps to `<description>`.
    /// HTML content belongs in `<content:encoded>` at the item level.
    public var description: String
    /// Language tag per RFC 5646, e.g. `"en-US"`. Maps to `<language>`.
    public var language: String
    /// Copyright notice. Maps to `<copyright>`.
    public var copyright: String?
    /// Author name. Maps to `<itunes:author>`.
    public var author: String
    /// Owner name. Maps to `<itunes:owner><itunes:name>`.
    public var ownerName: String
    /// Owner email. Maps to `<itunes:owner><itunes:email>`.
    public var ownerEmail: String
    /// Whether the show contains explicit content. Maps to `<itunes:explicit>`.
    public var explicit: Bool
    /// Top-level iTunes category, e.g. `"Technology"`. Maps to `<itunes:category>`.
    public var category: String
    /// Optional subcategory within the top-level category. Maps to nested `<itunes:category>`.
    public var subcategory: String?
    /// URL to the show's cover art image. Maps to `<itunes:image>`.
    public var imageURL: URL?
    /// Podcasting 2.0 show GUID. Maps to `<podcast:guid>`.
    public var podcastGUID: UUID
    /// Podcasting 2.0 lock flag. Maps to `<podcast:locked>`.
    public var podcastLocked: Bool
    /// The feed's self-referencing URL. Maps to `<atom:link rel="self">`.
    public var feedURL: URL?

    public init(
        title: String,
        link: URL,
        description: String,
        language: String,
        copyright: String? = nil,
        author: String,
        ownerName: String,
        ownerEmail: String,
        explicit: Bool,
        category: String,
        subcategory: String? = nil,
        imageURL: URL? = nil,
        podcastGUID: UUID,
        podcastLocked: Bool,
        feedURL: URL? = nil
    ) {
        self.title = title
        self.link = link
        self.description = description
        self.language = language
        self.copyright = copyright
        self.author = author
        self.ownerName = ownerName
        self.ownerEmail = ownerEmail
        self.explicit = explicit
        self.category = category
        self.subcategory = subcategory
        self.imageURL = imageURL
        self.podcastGUID = podcastGUID
        self.podcastLocked = podcastLocked
        self.feedURL = feedURL
    }
}
