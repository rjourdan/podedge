import Foundation

/// A `Sendable` value-type snapshot of a ``Show`` for use across isolation boundaries.
public struct ShowSnapshot: Sendable {
    public var id: UUID
    public var title: String
    public var author: String
    public var summary: String
    public var language: String
    public var category: String
    public var subcategory: String?
    public var explicit: Bool
    public var copyright: String?
    public var ownerEmail: String
    public var ownerName: String
    public var podcastGUID: UUID
    public var podcastLocked: Bool
    public var feedRemotePath: String
    public var hostBindingID: UUID
    public var analyticsBindingID: UUID?
    public var coverArtAssetID: UUID?

    public init(
        id: UUID,
        title: String,
        author: String,
        summary: String,
        language: String,
        category: String,
        subcategory: String? = nil,
        explicit: Bool,
        copyright: String? = nil,
        ownerEmail: String,
        ownerName: String,
        podcastGUID: UUID,
        podcastLocked: Bool,
        feedRemotePath: String,
        hostBindingID: UUID,
        analyticsBindingID: UUID? = nil,
        coverArtAssetID: UUID? = nil
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
        self.podcastGUID = podcastGUID
        self.podcastLocked = podcastLocked
        self.feedRemotePath = feedRemotePath
        self.hostBindingID = hostBindingID
        self.analyticsBindingID = analyticsBindingID
        self.coverArtAssetID = coverArtAssetID
    }
}

// MARK: - Show Convenience

extension Show {
    /// Creates a `Sendable` snapshot of this show's current state.
    public var snapshot: ShowSnapshot {
        ShowSnapshot(
            id: id,
            title: title,
            author: author,
            summary: summary,
            language: language,
            category: category,
            subcategory: subcategory,
            explicit: explicit,
            copyright: copyright,
            ownerEmail: ownerEmail,
            ownerName: ownerName,
            podcastGUID: podcastGUID,
            podcastLocked: podcastLocked,
            feedRemotePath: feedRemotePath,
            hostBindingID: hostBindingID,
            analyticsBindingID: analyticsBindingID,
            coverArtAssetID: coverArtAssetID
        )
    }
}

/// A `Sendable` value-type snapshot of an ``Episode`` for use across isolation boundaries.
public struct EpisodeSnapshot: Sendable {
    public var id: UUID
    public var title: String
    public var subtitle: String?
    public var summary: String
    public var descriptionHTML: String?
    public var season: Int?
    public var number: Int?
    public var type: EpisodeType
    public var explicit: Bool?
    public var guid: String
    public var status: EpisodeStatus
    public var pubDate: Date?
    public var chaptersJSON: String?
    public var originalAssetID: UUID
    public var publishedAssetID: UUID?
    public var coverArtAssetID: UUID?

    public init(
        id: UUID,
        title: String,
        subtitle: String? = nil,
        summary: String,
        descriptionHTML: String? = nil,
        season: Int? = nil,
        number: Int? = nil,
        type: EpisodeType,
        explicit: Bool? = nil,
        guid: String,
        status: EpisodeStatus,
        pubDate: Date? = nil,
        chaptersJSON: String? = nil,
        originalAssetID: UUID,
        publishedAssetID: UUID? = nil,
        coverArtAssetID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.descriptionHTML = descriptionHTML
        self.season = season
        self.number = number
        self.type = type
        self.explicit = explicit
        self.guid = guid
        self.status = status
        self.pubDate = pubDate
        self.chaptersJSON = chaptersJSON
        self.originalAssetID = originalAssetID
        self.publishedAssetID = publishedAssetID
        self.coverArtAssetID = coverArtAssetID
    }
}

// MARK: - Episode Convenience

extension Episode {
    /// Creates a `Sendable` snapshot of this episode's current state.
    public var snapshot: EpisodeSnapshot {
        EpisodeSnapshot(
            id: id,
            title: title,
            subtitle: subtitle,
            summary: summary,
            descriptionHTML: descriptionHTML,
            season: season,
            number: number,
            type: type,
            explicit: explicit,
            guid: guid,
            status: status,
            pubDate: pubDate,
            chaptersJSON: chaptersJSON,
            originalAssetID: originalAssetID,
            publishedAssetID: publishedAssetID,
            coverArtAssetID: coverArtAssetID
        )
    }
}
