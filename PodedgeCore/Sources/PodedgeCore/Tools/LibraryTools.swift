import Foundation

/// Lists all shows in the library.
public struct ListShowsTool: ToolDefinition, Sendable {
    public let name = "library.list_shows"
    public let description = "Returns all shows in the library."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = "{}"

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let shows = try await MainActor.run { try store.allShows().map(\.snapshot) }
        return try JSONEncoder().encode(shows)
    }
}

/// Returns a single show by ID.
public struct GetShowTool: ToolDefinition, Sendable {
    public let name = "library.get_show"
    public let description = "Returns a show by its identifier."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(GetShowInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            return show.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Lists episodes for a show.
public struct ListEpisodesTool: ToolDefinition, Sendable {
    public let name = "library.list_episodes"
    public let description = "Returns all episodes for a given show."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(ListEpisodesInput.self, from: input)
        let snapshots = try await MainActor.run {
            try store.episodes(for: params.showID).map(\.snapshot)
        }
        return try JSONEncoder().encode(snapshots)
    }
}

/// Returns a single episode by ID.
public struct GetEpisodeTool: ToolDefinition, Sendable {
    public let name = "library.get_episode"
    public let description = "Returns an episode by its identifier."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(GetEpisodeInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let ep = try store.episode(id: params.episodeID) else {
                throw PodedgeError.notFound(entity: "Episode", id: params.episodeID.uuidString)
            }
            return ep.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}
