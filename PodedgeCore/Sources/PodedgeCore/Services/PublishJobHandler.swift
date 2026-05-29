import Foundation
import SwiftData

/// Bridges the job scheduler to ``PublishService``, executing `.publish` jobs.
///
/// The scheduler invokes handlers from `@MainActor` context. This handler
/// accesses SwiftData models and calls the main-actor-isolated ``PublishService``.
public struct PublishJobHandler: JobHandler, Sendable {

    public let handledKind: JobKind = .publish

    private let publishService: PublishService
    private let notificationService: any NotificationServiceProtocol

    /// Creates a handler that delegates publishing to the given services.
    ///
    /// - Parameters:
    ///   - publishService: The service that orchestrates the full publish pipeline.
    ///   - notificationService: The service used to deliver user-facing notifications.
    public init(publishService: PublishService, notificationService: any NotificationServiceProtocol) {
        self.publishService = publishService
        self.notificationService = notificationService
    }

    @MainActor
    public func execute(jobID: UUID, container: ModelContainer) async throws {
        let context = container.mainContext

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

        // Idempotency guard.
        guard episode.status != .published else { return }

        // Fetch show.
        guard let show = episode.show else {
            throw PodedgeError.notFound(entity: "Show", id: "episode.show")
        }

        let episodeTitle = episode.title

        do {
            try await publishService.publish(show: show, episode: episode)
            await notificationService.sendPublishSuccess(episodeTitle: episodeTitle)
        } catch {
            episode.status = .failed
            episode.updatedAt = Date()
            try context.save()
            await notificationService.sendPublishFailure(episodeTitle: episodeTitle, reason: error.localizedDescription)
            throw error
        }
    }
}
