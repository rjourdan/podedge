import Foundation
import SwiftData

/// Single source of truth for all persistent models. Provides typed CRUD
/// wrappers around a ``ModelContext``.
///
/// `LibraryStore` is intentionally not an actor — it's bound to the
/// `ModelContext` it's given, which is itself `@MainActor`-isolated when
/// created from a `ModelContainer` on the main thread. Callers are
/// responsible for using it on the correct isolation domain.
@MainActor
public final class LibraryStore {

    public let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Shows

    /// Returns every show in the library, sorted alphabetically by title.
    public func allShows() throws -> [Show] {
        try modelContext.fetch(FetchDescriptor<Show>(sortBy: [SortDescriptor(\.title)]))
    }

    /// Returns the show with the given identifier, or `nil` if not found.
    public func show(id: UUID) throws -> Show? {
        var descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts a new show into the model context.
    public func addShow(_ show: Show) {
        modelContext.insert(show)
    }

    /// Deletes a show and cascades to its episodes, distributions, and analytics snapshots.
    public func deleteShow(_ show: Show) {
        modelContext.delete(show)
    }

    // MARK: - Episodes

    /// Returns all episodes belonging to the given show, sorted newest-first by creation date.
    public func episodes(for showID: UUID) throws -> [Episode] {
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.show?.id == showID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Returns the episode with the given identifier, or `nil` if not found.
    public func episode(id: UUID) throws -> Episode? {
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts a new episode into the model context.
    public func addEpisode(_ episode: Episode) {
        modelContext.insert(episode)
    }

    /// Deletes an episode from the model context.
    public func deleteEpisode(_ episode: Episode) {
        modelContext.delete(episode)
    }

    // MARK: - Assets

    /// Returns the asset with the given identifier, or `nil` if not found.
    public func asset(id: UUID) throws -> Asset? {
        var descriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts a new asset into the model context.
    public func addAsset(_ asset: Asset) {
        modelContext.insert(asset)
    }

    /// Deletes an asset from the model context.
    public func deleteAsset(_ asset: Asset) {
        modelContext.delete(asset)
    }

    // MARK: - Host Bindings

    /// Returns all host bindings, sorted alphabetically by display name.
    public func allHostBindings() throws -> [HostBinding] {
        try modelContext.fetch(FetchDescriptor<HostBinding>(sortBy: [SortDescriptor(\.displayName)]))
    }

    /// Returns the host binding with the given identifier, or `nil` if not found.
    public func hostBinding(id: UUID) throws -> HostBinding? {
        var descriptor = FetchDescriptor<HostBinding>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts a new host binding into the model context.
    public func addHostBinding(_ binding: HostBinding) {
        modelContext.insert(binding)
    }

    /// Deletes a host binding from the model context.
    public func deleteHostBinding(_ binding: HostBinding) {
        modelContext.delete(binding)
    }

    // MARK: - Analytics Bindings

    /// Returns the analytics binding with the given identifier, or `nil` if not found.
    public func analyticsBinding(id: UUID) throws -> AnalyticsBinding? {
        var descriptor = FetchDescriptor<AnalyticsBinding>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Inserts a new analytics binding into the model context.
    public func addAnalyticsBinding(_ binding: AnalyticsBinding) {
        modelContext.insert(binding)
    }

    /// Deletes an analytics binding from the model context.
    public func deleteAnalyticsBinding(_ binding: AnalyticsBinding) {
        modelContext.delete(binding)
    }

    // MARK: - Jobs

    /// Returns all jobs in the pending state, sorted oldest-first by creation date.
    public func pendingJobs() throws -> [Job] {
        // Fetch all jobs sorted by creation date, then filter in memory.
        // SwiftData's #Predicate does not reliably support captured enum
        // constants across all runners (SPM vs Xcode).
        let all = try modelContext.fetch(
            FetchDescriptor<Job>(sortBy: [SortDescriptor(\.createdAt)])
        )
        return all.filter { $0.state == .pending }
    }

    /// Returns all jobs targeting the given entity, sorted newest-first by creation date.
    public func jobs(for targetID: UUID) throws -> [Job] {
        try modelContext.fetch(
            FetchDescriptor<Job>(
                predicate: #Predicate { $0.targetID == targetID },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
    }

    /// Inserts a new job into the model context.
    public func addJob(_ job: Job) {
        modelContext.insert(job)
    }

    // MARK: - Analytics Snapshots

    /// Returns snapshots for the given show captured on or after `since`, sorted oldest-first.
    public func snapshots(for showID: UUID, since: Date) throws -> [AnalyticsSnapshot] {
        try modelContext.fetch(
            FetchDescriptor<AnalyticsSnapshot>(
                predicate: #Predicate { $0.show?.id == showID && $0.capturedAt >= since },
                sortBy: [SortDescriptor(\.capturedAt)]
            )
        )
    }

    /// Inserts a new analytics snapshot into the model context.
    public func addSnapshot(_ snapshot: AnalyticsSnapshot) {
        modelContext.insert(snapshot)
    }

    // MARK: - Distribution Records

    /// Returns all distribution records for the given show.
    public func distributions(for showID: UUID) throws -> [DistributionRecord] {
        try modelContext.fetch(
            FetchDescriptor<DistributionRecord>(
                predicate: #Predicate { $0.show?.id == showID }
            )
        )
    }

    /// Inserts a new distribution record into the model context.
    public func addDistribution(_ record: DistributionRecord) {
        modelContext.insert(record)
    }

    /// Deletes a distribution record from the model context.
    public func deleteDistribution(_ record: DistributionRecord) {
        modelContext.delete(record)
    }

    // MARK: - Persistence

    /// Persists all pending changes in the model context. Throws on failure.
    public func save() throws {
        try modelContext.save()
    }
}
