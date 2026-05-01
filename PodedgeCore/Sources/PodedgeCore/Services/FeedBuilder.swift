import Foundation

/// Builds an ``RSSFeed`` from snapshot value types.
///
/// The builder resolves asset URLs through a provided closure and optionally
/// rewrites enclosure URLs through an analytics prefix.
public struct FeedBuilder: Sendable {

    /// Closure that resolves an asset ID to its public URL.
    public typealias AssetResolver = @Sendable (UUID) -> URL?

    /// Optional analytics prefix rewriter. Receives the original enclosure URL
    /// and returns the prefixed URL.
    public typealias AnalyticsRewriter = @Sendable (URL) -> URL

    private let resolveAsset: AssetResolver
    private let rewriteEnclosure: AnalyticsRewriter?

    /// Creates a feed builder.
    ///
    /// - Parameters:
    ///   - resolveAsset: Resolves an asset UUID to its public URL.
    ///   - rewriteEnclosure: Optional analytics prefix rewriter for enclosure URLs.
    public init(
        resolveAsset: @escaping AssetResolver,
        rewriteEnclosure: AnalyticsRewriter? = nil
    ) {
        self.resolveAsset = resolveAsset
        self.rewriteEnclosure = rewriteEnclosure
    }

    /// Builds an RSS feed from a show snapshot and its published episodes.
    ///
    /// - Parameters:
    ///   - show: The show snapshot.
    ///   - episodes: Published episode snapshots, sorted by `pubDate` descending.
    ///   - feedURL: The public URL of the feed itself (for `<atom:link rel="self">`).
    /// - Returns: A fully populated ``RSSFeed``.
    public func build(
        show: ShowSnapshot,
        episodes: [EpisodeSnapshot],
        feedURL: URL
    ) -> RSSFeed {
        let imageURL = show.coverArtAssetID.flatMap(resolveAsset)

        let channel = RSSChannel(
            title: show.title,
            link: feedURL,
            description: Self.stripHTML(show.summary),
            language: show.language,
            copyright: show.copyright,
            author: show.author,
            ownerName: show.ownerName,
            ownerEmail: show.ownerEmail,
            explicit: show.explicit,
            category: show.category,
            subcategory: show.subcategory,
            imageURL: imageURL,
            podcastGUID: show.podcastGUID,
            podcastLocked: show.podcastLocked,
            feedURL: feedURL
        )

        let items = episodes.compactMap { ep -> RSSItem? in
            guard let assetID = ep.publishedAssetID,
                  let rawURL = resolveAsset(assetID) else { return nil }

            let enclosureURL = rewriteEnclosure?(rawURL) ?? rawURL
            let epImageURL = ep.coverArtAssetID.flatMap(resolveAsset)

            return RSSItem(
                title: ep.title,
                guid: ep.guid,
                description: Self.stripHTML(ep.summary),
                contentEncoded: ep.descriptionHTML,
                pubDate: ep.pubDate ?? Date(),
                enclosureURL: enclosureURL,
                enclosureLength: ep.enclosureByteSize,
                enclosureType: "audio/mpeg",
                duration: nil,
                episodeType: ep.type,
                season: ep.season,
                episode: ep.number,
                explicit: ep.explicit,
                subtitle: ep.subtitle,
                imageURL: epImageURL,
                chaptersURL: ep.chaptersJSON != nil ? chaptersURL(for: ep, feedURL: feedURL) : nil,
                transcriptURL: ep.transcriptURL
            )
        }

        return RSSFeed(channel: channel, items: items)
    }

    /// Derives a chapters URL from the episode GUID relative to the feed URL.
    private func chaptersURL(for episode: EpisodeSnapshot, feedURL: URL) -> URL? {
        feedURL.deletingLastPathComponent()
            .appendingPathComponent("chapters")
            .appendingPathComponent("\(episode.guid).json")
    }

    /// Strips HTML tags from a string, returning plain text.
    ///
    /// Fix #15: `<description>` must be plain text; `<content:encoded>` carries HTML.
    static func stripHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
