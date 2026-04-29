import Foundation
import SwiftData

/// A point-in-time snapshot of analytics data from OP3.
@Model public final class AnalyticsSnapshot {
    @Attribute(.unique) public var id: UUID

    /// The show this snapshot belongs to. Always non-nil after insertion;
    /// optional to satisfy SwiftData inverse relationship requirements.
    public var show: Show?

    /// The episode this snapshot relates to, if episode-level.
    /// Nil for show-level aggregate snapshots; optional to satisfy SwiftData
    /// inverse relationship requirements.
    public var episode: Episode?

    public var capturedAt: Date
    public var windowStart: Date
    public var windowEnd: Date
    public var downloads: Int
    public var uniqueListeners: Int
    public var appsJSON: String
    public var geosJSON: String

    public init(
        id: UUID = UUID(),
        show: Show? = nil,
        episode: Episode? = nil,
        capturedAt: Date = Date(),
        windowStart: Date,
        windowEnd: Date,
        downloads: Int = 0,
        uniqueListeners: Int = 0,
        appsJSON: String = "{}",
        geosJSON: String = "{}"
    ) {
        self.id = id
        self.show = show
        self.episode = episode
        self.capturedAt = capturedAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.downloads = downloads
        self.uniqueListeners = uniqueListeners
        self.appsJSON = appsJSON
        self.geosJSON = geosJSON
    }
}
