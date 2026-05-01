import Foundation

// MARK: - Supporting Types

/// A snapshot of analytics data fetched from an external provider.
public struct AnalyticsFetchResult: Sendable {
    /// Total download count in the requested window.
    public var downloads: Int
    /// Unique listener count in the requested window.
    public var uniqueListeners: Int
    /// Breakdown of downloads by podcast app name.
    public var appBreakdown: [String: Int]
    /// Breakdown of downloads by geographic region.
    public var geoBreakdown: [String: Int]

    public init(
        downloads: Int,
        uniqueListeners: Int,
        appBreakdown: [String: Int] = [:],
        geoBreakdown: [String: Int] = [:]
    ) {
        self.downloads = downloads
        self.uniqueListeners = uniqueListeners
        self.appBreakdown = appBreakdown
        self.geoBreakdown = geoBreakdown
    }
}

// MARK: - Protocol

/// Abstraction over podcast analytics providers (e.g. OP3).
public protocol AnalyticsProvider: Sendable {
    /// Human-readable provider name (e.g. `"op3"`).
    var providerName: String { get }

    /// Registers a feed URL with the analytics provider.
    ///
    /// - Parameters:
    ///   - feedURL: The public URL of the show's RSS feed.
    ///   - podcastGUID: The Podcasting 2.0 GUID for the show.
    /// - Returns: The external show identifier assigned by the provider.
    func register(feedURL: URL, podcastGUID: UUID) async throws -> String

    /// Wraps an enclosure URL with the provider's analytics prefix.
    ///
    /// - Parameter enclosureURL: The original media file URL.
    /// - Returns: A URL that routes through the analytics provider before redirecting.
    func prefixURL(for enclosureURL: URL) -> URL

    /// Fetches an analytics snapshot for the given show and time window.
    ///
    /// - Parameters:
    ///   - externalShowID: The provider-assigned show identifier.
    ///   - window: The date interval to query.
    /// - Returns: Aggregated analytics data for the window.
    func fetchSnapshot(
        externalShowID: String,
        window: DateInterval
    ) async throws -> AnalyticsFetchResult
}
