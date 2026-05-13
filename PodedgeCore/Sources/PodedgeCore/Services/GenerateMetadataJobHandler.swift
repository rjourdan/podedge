import Foundation
import SwiftData

/// Bridges the job scheduler to the metadata generation service, executing
/// `.generateMetadata` jobs by reading an episode's transcript and producing
/// AI-generated metadata suggestions.
public struct GenerateMetadataJobHandler: JobHandler, Sendable {

    /// The kind of job this handler processes.
    public let handledKind: JobKind = .generateMetadata

    private let metadataService: MetadataGenerationService

    /// Creates a handler that delegates metadata generation to the given service.
    ///
    /// - Parameter metadataService: The service used to generate episode metadata from a transcript.
    public init(metadataService: MetadataGenerationService) {
        self.metadataService = metadataService
    }

    /// Executes the metadata generation job.
    ///
    /// Reads the episode's plain-text transcript from disk, calls the metadata
    /// generation service, removes any previous suggestions, and persists the
    /// new ``EpisodeSuggestions`` record.
    ///
    /// - Parameters:
    ///   - jobID: The persistent identifier of the job to execute.
    ///   - container: The model container for creating a context.
    public func execute(jobID: UUID, container: ModelContainer) async throws {
        let context = ModelContext(container)

        // Fetch job.
        var jobDescriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        jobDescriptor.fetchLimit = 1
        guard let job = try context.fetch(jobDescriptor).first else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }

        // Fetch episode.
        let targetID = job.targetID
        var episodeDescriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == targetID })
        episodeDescriptor.fetchLimit = 1
        guard let episode = try context.fetch(episodeDescriptor).first else {
            throw PodedgeError.notFound(entity: "Episode", id: targetID.uuidString)
        }

        // Fetch transcript asset.
        guard let transcriptAssetID = episode.transcriptAssetID else {
            throw PodedgeError.notFound(entity: "TranscriptAsset")
        }

        var assetDescriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == transcriptAssetID })
        assetDescriptor.fetchLimit = 1
        guard let asset = try context.fetch(assetDescriptor).first else {
            throw PodedgeError.notFound(entity: "TranscriptAsset")
        }

        // Derive plain-text file URL from the VTT path.
        let txtURL = asset.localURL.deletingPathExtension().appendingPathExtension("txt")

        guard FileManager.default.fileExists(atPath: txtURL.path) else {
            throw PodedgeError.notFound(entity: "TranscriptAsset")
        }

        let transcript = try String(contentsOf: txtURL, encoding: .utf8)

        // Resolve show title.
        let showTitle = episode.show?.title ?? "Untitled Show"

        // Generate metadata.
        let episodeNumber = String(episode.number ?? 0)
        let result = try await metadataService.generate(
            transcript: transcript,
            showTitle: showTitle,
            episodeNumber: episodeNumber
        )

        // Delete existing suggestions for this episode.
        let episodeID = episode.id
        let suggestionsDescriptor = FetchDescriptor<EpisodeSuggestions>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        let existingSuggestions = try context.fetch(suggestionsDescriptor)
        for suggestion in existingSuggestions {
            context.delete(suggestion)
        }

        // Insert new suggestions.
        let suggestions = EpisodeSuggestions(episodeID: episode.id, metadata: result)
        context.insert(suggestions)

        try context.save()
    }
}
