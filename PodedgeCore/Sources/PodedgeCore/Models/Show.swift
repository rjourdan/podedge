import Foundation
import SwiftData

/// A podcast show — the top-level entity in the library.
@Model public final class Show {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var author: String
    public var summary: String

    /// Language tag per RFC 5646, e.g. `"en-US"`.
    public var language: String

    /// Top-level Apple Podcasts / iTunes category, e.g. `"Technology"`.
    public var category: String

    public var subcategory: String?
    public var explicit: Bool
    public var copyright: String?
    public var ownerEmail: String
    public var ownerName: String
    public var coverArtAssetID: UUID?

    /// Podcasting 2.0 `<podcast:guid>`. Locked at creation — never changes.
    public var podcastGUID: UUID

    /// Podcasting 2.0 `<podcast:locked>`. When `true`, prevents transfer to another host.
    public var podcastLocked: Bool

    public var hostBindingID: UUID

    /// Relative path to the RSS feed on the hosting backend, e.g. `"shows/my-show/feed.xml"`.
    public var feedRemotePath: String

    public var analyticsBindingID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    public var episodes: [Episode] = []

    @Relationship(deleteRule: .cascade, inverse: \DistributionRecord.show)
    public var distributions: [DistributionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \AnalyticsSnapshot.show)
    public var analyticsSnapshots: [AnalyticsSnapshot] = []

    public init(
        id: UUID = UUID(),
        title: String,
        author: String,
        summary: String,
        language: String = "en-US",
        category: String,
        subcategory: String? = nil,
        explicit: Bool = false,
        copyright: String? = nil,
        ownerEmail: String,
        ownerName: String,
        coverArtAssetID: UUID? = nil,
        podcastGUID: UUID = UUID(),
        podcastLocked: Bool = true,
        hostBindingID: UUID,
        feedRemotePath: String,
        analyticsBindingID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.language = language
        self.category = category
        self.subcategory = subcategory
        self.explicit = explicit
        self.copyright = copyright
        self.ownerEmail = ownerEmail
        self.ownerName = ownerName
        self.coverArtAssetID = coverArtAssetID
        self.podcastGUID = podcastGUID
        self.podcastLocked = podcastLocked
        self.hostBindingID = hostBindingID
        self.feedRemotePath = feedRemotePath
        self.analyticsBindingID = analyticsBindingID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
