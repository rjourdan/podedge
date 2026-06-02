import Foundation

/// Builds an RSS feed preview XML string for a show.
public struct BuildPreviewTool: ToolDefinition, Sendable {
    public let name = "feed.build_preview"
    public let description = "Builds an RSS feed preview for the given show and returns XML."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore
    private let feedBuilder: FeedBuilder
    private let serializer: FeedXMLSerializer

    public init(store: LibraryStore, feedBuilder: FeedBuilder, serializer: FeedXMLSerializer) {
        self.store = store
        self.feedBuilder = feedBuilder
        self.serializer = serializer
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(BuildPreviewInput.self, from: input)
        let (showSnap, episodeSnaps) = try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            let eps = try store.episodes(for: params.showID)
                .filter { $0.status == .published }
                .map(\.snapshot)
            return (show.snapshot, eps)
        }
        let feedURL = URL(string: "https://example.com/\(showSnap.feedRemotePath)")!
        let feed = feedBuilder.build(show: showSnap, episodes: episodeSnaps, feedURL: feedURL)
        let xmlData = serializer.serialize(feed)
        let xml = String(data: xmlData, encoding: .utf8) ?? ""
        return try JSONEncoder().encode(BuildPreviewOutput(xml: xml))
    }
}

/// Validates the feed for a show and returns issues.
public struct ValidateFeedTool: ToolDefinition, Sendable {
    public let name = "feed.validate"
    public let description = "Validates the RSS feed for a show and returns any issues."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore
    private let feedBuilder: FeedBuilder
    private let validator: FeedValidator

    public init(store: LibraryStore, feedBuilder: FeedBuilder, validator: FeedValidator) {
        self.store = store
        self.feedBuilder = feedBuilder
        self.validator = validator
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(ValidateFeedInput.self, from: input)
        let (showSnap, episodeSnaps) = try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            let eps = try store.episodes(for: params.showID)
                .filter { $0.status == .published }
                .map(\.snapshot)
            return (show.snapshot, eps)
        }
        let feedURL = URL(string: "https://example.com/\(showSnap.feedRemotePath)")!
        let feed = feedBuilder.build(show: showSnap, episodes: episodeSnaps, feedURL: feedURL)
        let issues = validator.validate(feed)
        return try JSONEncoder().encode(ValidateFeedOutput(issues: issues))
    }
}
