import Foundation

/// Creates a draft episode for a show.
public struct CreateDraftTool: ToolDefinition, Sendable {
    public let name = "episode.create_draft"
    public let description = "Creates a new draft episode in the specified show."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID","title":"String"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(CreateDraftInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let show = try store.show(id: params.showID) else {
                throw PodedgeError.notFound(entity: "Show", id: params.showID.uuidString)
            }
            let episode = Episode(
                show: show,
                title: params.title,
                originalAssetID: UUID(),
                status: .draft
            )
            store.addEpisode(episode)
            try store.save()
            return episode.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Updates metadata fields on an episode.
public struct UpdateMetadataTool: ToolDefinition, Sendable {
    public let name = "episode.update_metadata"
    public let description = "Updates title, subtitle, or summary on an episode."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID","title":"String?","subtitle":"String?","summary":"String?"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(UpdateEpisodeMetadataInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let ep = try store.episode(id: params.episodeID) else {
                throw PodedgeError.notFound(entity: "Episode", id: params.episodeID.uuidString)
            }
            if let title = params.title { ep.title = title }
            if let subtitle = params.subtitle { ep.subtitle = subtitle }
            if let summary = params.summary { ep.summary = summary }
            ep.updatedAt = Date()
            try store.save()
            return ep.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Enqueues a transcription job for an episode.
public struct TranscribeTool: ToolDefinition, Sendable {
    public let name = "episode.transcribe"
    public let description = "Enqueues a transcription job for the given episode."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID"}"#

    private let store: LibraryStore
    private let scheduler: JobScheduler

    public init(store: LibraryStore, scheduler: JobScheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(TranscribeInput.self, from: input)
        let summary = try await MainActor.run {
            let job = Job(kind: .transcribe, targetID: params.episodeID)
            try scheduler.enqueue(job)
            return JobSummary(
                id: job.id, kind: job.kind.rawValue, targetID: job.targetID,
                state: job.state.rawValue, attempts: job.attempts, createdAt: job.createdAt
            )
        }
        return try JSONEncoder().encode(summary)
    }
}

/// Enqueues a publish job for an episode.
public struct PublishTool: ToolDefinition, Sendable {
    public let name = "episode.publish"
    public let description = "Enqueues a publish job for the given episode."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID"}"#

    private let store: LibraryStore
    private let scheduler: JobScheduler

    public init(store: LibraryStore, scheduler: JobScheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(PublishInput.self, from: input)
        let summary = try await MainActor.run {
            let job = Job(kind: .publish, targetID: params.episodeID)
            try scheduler.enqueue(job)
            return JobSummary(
                id: job.id, kind: job.kind.rawValue, targetID: job.targetID,
                state: job.state.rawValue, attempts: job.attempts, createdAt: job.createdAt
            )
        }
        return try JSONEncoder().encode(summary)
    }
}

/// Unpublishes an episode by reverting its status to ready.
public struct UnpublishTool: ToolDefinition, Sendable {
    public let name = "episode.unpublish"
    public let description = "Reverts a published episode to ready state."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(UnpublishInput.self, from: input)
        let snapshot = try await MainActor.run {
            guard let ep = try store.episode(id: params.episodeID) else {
                throw PodedgeError.notFound(entity: "Episode", id: params.episodeID.uuidString)
            }
            ep.status = .ready
            ep.pubDate = nil
            ep.updatedAt = Date()
            try store.save()
            return ep.snapshot
        }
        return try JSONEncoder().encode(snapshot)
    }
}

/// Deletes an episode from the library.
public struct DeleteEpisodeTool: ToolDefinition, Sendable {
    public let name = "episode.delete"
    public let description = "Permanently deletes an episode."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(DeleteEpisodeInput.self, from: input)
        try await MainActor.run {
            guard let ep = try store.episode(id: params.episodeID) else {
                throw PodedgeError.notFound(entity: "Episode", id: params.episodeID.uuidString)
            }
            store.deleteEpisode(ep)
            try store.save()
        }
        return try JSONEncoder().encode(EmptyOutput())
    }
}
