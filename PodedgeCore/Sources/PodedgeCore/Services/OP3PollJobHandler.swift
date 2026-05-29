import Foundation
import SwiftData

/// Bridges the job scheduler to ``AnalyticsService``, executing `.op3Poll` jobs
/// and self-scheduling the next poll.
public struct OP3PollJobHandler: JobHandler, Sendable {

    public let handledKind: JobKind = .op3Poll

    private let analyticsService: AnalyticsService

    /// Creates a handler that delegates analytics polling to the given service.
    ///
    /// - Parameter analyticsService: The service used to fetch analytics snapshots.
    public init(analyticsService: AnalyticsService) {
        self.analyticsService = analyticsService
    }

    public func execute(jobID: UUID, container: ModelContainer) async throws {
        let context = ModelContext(container)

        // Fetch job.
        var jobDescriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        jobDescriptor.fetchLimit = 1
        guard let job = try context.fetch(jobDescriptor).first else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }

        // Fetch show.
        let targetID = job.targetID
        var showDescriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == targetID })
        showDescriptor.fetchLimit = 1
        guard let show = try context.fetch(showDescriptor).first else {
            throw PodedgeError.notFound(entity: "Show", id: targetID.uuidString)
        }

        // Fetch analytics binding.
        guard let analyticsBindingID = show.analyticsBindingID else {
            throw PodedgeError.analyticsUnavailable(reason: "Show has no analytics binding")
        }
        var bindingDescriptor = FetchDescriptor<AnalyticsBinding>(predicate: #Predicate { $0.id == analyticsBindingID })
        bindingDescriptor.fetchLimit = 1
        guard let binding = try context.fetch(bindingDescriptor).first else {
            throw PodedgeError.notFound(entity: "AnalyticsBinding", id: analyticsBindingID.uuidString)
        }

        guard let externalShowID = binding.externalShowID else {
            throw PodedgeError.analyticsUnavailable(reason: "AnalyticsBinding has no externalShowID")
        }

        // Fetch snapshot.
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now)
        _ = try await analyticsService.fetchNow(externalShowID: externalShowID, window: window)

        // Enqueue next poll job.
        let nextJob = Job(
            kind: .op3Poll,
            targetID: show.id,
            payloadJSON: "{\"delaySeconds\":21600}"
        )
        context.insert(nextJob)
        try context.save()
    }
}
