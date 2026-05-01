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
    /// Byte size of the published enclosure file. Used for `<enclosure length="...">`.
    public var enclosureByteSize: Int64
    /// URL to a VTT transcript file, if available.
    public var transcriptURL: URL?

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
        coverArtAssetID: UUID? = nil,
        enclosureByteSize: Int64 = 0,
        transcriptURL: URL? = nil
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
        self.enclosureByteSize = enclosureByteSize
        self.transcriptURL = transcriptURL
    }
}

// MARK: - Episode Convenience

extension Episode {
    /// Creates a `Sendable` snapshot of this episode's current state.
    ///
    /// `enclosureByteSize` defaults to `0` because `Episode` stores only a
    /// `publishedAssetID` (no relationship to `Asset`). Use
    /// ``snapshot(resolvingAsset:)`` when you need the byte size populated
    /// (e.g. for RSS feed generation).
    public var snapshot: EpisodeSnapshot {
        snapshot(resolvingAsset: { _ in nil })
    }

    /// Creates a snapshot, resolving the published asset to populate `enclosureByteSize`.
    ///
    /// - Parameter resolvingAsset: Closure that looks up an ``Asset`` by its ID.
    ///   Typically backed by a `ModelContext` fetch. Pass `{ _ in nil }` when the
    ///   byte size is not needed.
    /// - Returns: A fully populated ``EpisodeSnapshot``.
    public func snapshot(resolvingAsset: (UUID) -> Asset?) -> EpisodeSnapshot {
        // Option B: Episode has no Asset relationship, so the caller provides
        // a resolver. FeedBuilder already uses a similar AssetResolver pattern.
        let byteSize: Int64 = publishedAssetID
            .flatMap(resolvingAsset)
            .map(\.byteSize) ?? 0

        return EpisodeSnapshot(
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
            coverArtAssetID: coverArtAssetID,
            enclosureByteSize: byteSize
        )
    }
}

/// A `Sendable` value-type snapshot of a ``HostBinding`` for use across isolation boundaries.
public struct HostBindingSnapshot: Sendable {
    public var id: UUID
    public var kind: HostKind
    public var displayName: String
    public var bucket: String
    public var region: String
    public var prefix: String
    public var publicBaseURL: URL
    public var keychainRef: String

    public init(
        id: UUID,
        kind: HostKind,
        displayName: String,
        bucket: String,
        region: String,
        prefix: String,
        publicBaseURL: URL,
        keychainRef: String
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.bucket = bucket
        self.region = region
        self.prefix = prefix
        self.publicBaseURL = publicBaseURL
        self.keychainRef = keychainRef
    }
}

// MARK: - HostBinding Convenience

extension HostBinding {
    /// Creates a `Sendable` snapshot of this host binding's current state.
    public var snapshot: HostBindingSnapshot {
        HostBindingSnapshot(
            id: id,
            kind: kind,
            displayName: displayName,
            bucket: bucket,
            region: region,
            prefix: prefix,
            publicBaseURL: publicBaseURL,
            keychainRef: keychainRef
        )
    }
}
