import Foundation

/// Enqueues a metadata generation job for an episode.
public struct GenerateMetadataTool: ToolDefinition, Sendable {
    public let name = "llm.generate_metadata"
    public let description = "Enqueues an LLM metadata generation job for the given episode."
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
        let params = try JSONDecoder().decode(GenerateMetadataInput.self, from: input)
        let summary = try await MainActor.run {
            let job = Job(kind: .generateMetadata, targetID: params.episodeID)
            try scheduler.enqueue(job)
            return JobSummary(
                id: job.id, kind: job.kind.rawValue, targetID: job.targetID,
                state: job.state.rawValue, attempts: job.attempts, createdAt: job.createdAt
            )
        }
        return try JSONEncoder().encode(summary)
    }
}

/// Generates a social media blurb for an episode on a given platform.
public struct GenerateBlurbTool: ToolDefinition, Sendable {
    public let name = "llm.generate_blurb"
    public let description = "Generates a social media blurb for an episode using the LLM."
    public let scope: ToolScope = .mutating
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID","platform":"String"}"#

    private let store: LibraryStore
    private let renderer: SocialBlurbRenderer

    public init(store: LibraryStore, renderer: SocialBlurbRenderer) {
        self.store = store
        self.renderer = renderer
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(GenerateBlurbInput.self, from: input)
        let (epSnap, showSnap) = try await MainActor.run {
            guard let ep = try store.episode(id: params.episodeID) else {
                throw PodedgeError.notFound(entity: "Episode", id: params.episodeID.uuidString)
            }
            guard let show = ep.show else {
                throw PodedgeError.notFound(entity: "Show", id: "parent of \(params.episodeID.uuidString)")
            }
            return (ep.snapshot, show.snapshot)
        }
        let output = try await renderer.render(episode: epSnap, show: showSnap, transcript: nil)
        return try JSONEncoder().encode(GenerateBlurbOutput(blurb: output.text))
    }
}
