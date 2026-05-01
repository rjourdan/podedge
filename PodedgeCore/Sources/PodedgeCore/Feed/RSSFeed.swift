import Foundation

/// A complete podcast RSS feed, ready for XML serialization.
public struct RSSFeed: Sendable {
    /// The channel (show-level) metadata.
    public var channel: RSSChannel
    /// The items (episodes) in reverse-chronological order.
    public var items: [RSSItem]

    public init(channel: RSSChannel, items: [RSSItem]) {
        self.channel = channel
        self.items = items
    }
}
