import Foundation
import SwiftData

@testable import PodedgeCore

/// Shared test container that is created once and reused across all SwiftData tests.
///
/// SwiftData's `ModelContainer` crashes (signal trap) when multiple containers
/// are created in the same process, even with unique names or in-memory stores.
/// Using a single shared container avoids this entirely.
enum TestDatabase {
    /// The shared container, created lazily on first access.
    @MainActor
    static let shared: ModelContainer = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeCoreTests", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shared-\(ProcessInfo.processInfo.processIdentifier).store")
        // Remove any leftover file from a previous run of this process.
        try? FileManager.default.removeItem(at: url)
        return try! PodedgeSchema.makeContainer(url: url)
    }()

    /// Deletes all model objects from the shared container's main context.
    ///
    /// Call at the start of each test to ensure a clean slate. Deletes objects
    /// individually (not batch) to respect cascade rules and inverse relationships.
    @MainActor
    static func reset() throws {
        let context = shared.mainContext

        // Delete leaf entities first, then parents.
        // AnalyticsSnapshot → Episode, Show
        for obj in try context.fetch(FetchDescriptor<AnalyticsSnapshot>()) { context.delete(obj) }
        // DistributionRecord → Show
        for obj in try context.fetch(FetchDescriptor<DistributionRecord>()) { context.delete(obj) }
        // Episode → Show
        for obj in try context.fetch(FetchDescriptor<Episode>()) { context.delete(obj) }
        // Independent entities
        for obj in try context.fetch(FetchDescriptor<Job>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<Asset>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<AgentAuditEntry>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<HostBinding>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<AnalyticsBinding>()) { context.delete(obj) }
        // Parent entity last
        for obj in try context.fetch(FetchDescriptor<Show>()) { context.delete(obj) }

        try context.save()
    }
}
