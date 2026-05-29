import Foundation
import SwiftData

/// A single episode within a show.
@Model public final class Episode {
    @Attribute(.unique) public var id: UUID

    /// The show this episode belongs to. Always non-nil after insertion;
    /// optional to satisfy SwiftData inverse relationship requirements.
    public var show: Show?

    public var title: String
    public var subtitle: String?
    public var summary: String
    public var descriptionHTML: String?
    public var season: Int?
    public var number: Int?
    public var type: EpisodeType
    public var explicit: Bool?

    /// Locked at creation — used as the RSS `<guid>`. Never changes once set.
    public var guid: String

    public var originalAssetID: UUID
    public var publishedAssetID: UUID?
    public var coverArtAssetID: UUID?

    /// Lifecycle state of this episode from import through publication.
    public var status: EpisodeStatus

    public var pubDate: Date?
    public var scheduledFor: Date?

    /// Podcasting 2.0 chapters in JSON Chapters format.
    public var chaptersJSON: String?

    public var transcriptAssetID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .nullify, inverse: \AnalyticsSnapshot.episode)
    public var analyticsSnapshots: [AnalyticsSnapshot] = []

    public init(
        id: UUID = UUID(),
        show: Show? = nil,
        title: String,
        subtitle: String? = nil,
        summary: String = "",
        descriptionHTML: String? = nil,
        season: Int? = nil,
        number: Int? = nil,
        type: EpisodeType = .full,
        explicit: Bool? = nil,
        guid: String? = nil,
        originalAssetID: UUID,
        publishedAssetID: UUID? = nil,
        coverArtAssetID: UUID? = nil,
        status: EpisodeStatus = .draft,
        pubDate: Date? = nil,
        scheduledFor: Date? = nil,
        chaptersJSON: String? = nil,
        transcriptAssetID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.show = show
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.descriptionHTML = descriptionHTML
        self.season = season
        self.number = number
        self.type = type
        self.explicit = explicit
        self.guid = guid ?? id.uuidString
        self.originalAssetID = originalAssetID
        self.publishedAssetID = publishedAssetID
        self.coverArtAssetID = coverArtAssetID
        self.status = status
        self.pubDate = pubDate
        self.scheduledFor = scheduledFor
        self.chaptersJSON = chaptersJSON
        self.transcriptAssetID = transcriptAssetID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Validation

    /// Validates that a scheduled publish date is in the future.
    ///
    /// - Parameter date: The proposed `scheduledFor` date.
    /// - Throws: ``PodedgeError/preconditionViolated(reason:)`` if `date` is not in the future.
    public static func validateScheduledFor(_ date: Date) throws {
        guard date > Date() else {
            throw PodedgeError.preconditionViolated(reason: "scheduledFor must be in the future")
        }
    }
}
