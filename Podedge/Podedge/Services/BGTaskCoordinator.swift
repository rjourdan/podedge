import Foundation
import PodedgeCore
import SwiftData

/// Coordinates scheduled episode publishing via a timer-based task system.
///
/// On macOS, `BGTaskScheduler` is unavailable. This coordinator uses
/// ``ScheduledTaskScheduling`` (backed by `TimerTaskScheduler`) to fire
/// publish jobs at the scheduled time.
@MainActor
public final class BGTaskCoordinator {

    /// The registered task identifier for scheduled publishing.
    static let scheduledPublishTaskID = "dev.podedge.scheduled-publish"

    private let jobScheduler: JobScheduler
    private let libraryStore: LibraryStore
    private let scheduler: ScheduledTaskScheduling

    /// Creates a coordinator that schedules publish tasks.
    ///
    /// - Parameters:
    ///   - jobScheduler: The job scheduler used to enqueue publish jobs.
    ///   - libraryStore: The store used to fetch due episodes.
    ///   - scheduler: The task scheduler implementation. Defaults to the shared timer scheduler.
    init(
        jobScheduler: JobScheduler,
        libraryStore: LibraryStore,
        scheduler: ScheduledTaskScheduling = TimerTaskScheduler.shared
    ) {
        self.jobScheduler = jobScheduler
        self.libraryStore = libraryStore
        self.scheduler = scheduler
    }

    /// Registers the scheduled-publish task handler.
    func registerTasks() {
        scheduler.register(forTaskWithIdentifier: Self.scheduledPublishTaskID) { [weak self] in
            await self?.handleScheduledPublish()
        }
    }

    /// Schedules a publish task to fire at the episode's `scheduledFor` date.
    ///
    /// - Parameter episode: The episode whose `scheduledFor` date determines when to fire.
    func schedulePublish(for episode: Episode) {
        guard let scheduledDate = episode.scheduledFor else { return }
        scheduler.schedule(identifier: Self.scheduledPublishTaskID, earliestBeginDate: scheduledDate)
    }

    // MARK: - Private

    private func handleScheduledPublish() async {
        let now = Date()
        do {
            let descriptor = FetchDescriptor<Episode>()
            let episodes = try libraryStore.modelContext.fetch(descriptor)
            let dueEpisodes = episodes.filter { episode in
                episode.status == .scheduled
                    && episode.scheduledFor != nil
                    && episode.scheduledFor! <= now
            }
            for episode in dueEpisodes {
                let job = Job(kind: .publish, targetID: episode.id)
                try jobScheduler.enqueue(job)
                episode.status = .processing
            }
            try libraryStore.modelContext.save()
        } catch {
            // Silently handle — jobs will be picked up on next pass.
        }
    }
}
