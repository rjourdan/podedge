import Foundation

/// Queries cached analytics snapshots for a show.
public struct QueryCachedAnalyticsTool: ToolDefinition, Sendable {
    public let name = "analytics.query_cached"
    public let description = "Returns cached analytics snapshots for a show, optionally filtered by date."
    public let scope: ToolScope = .readOnly
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"showID":"UUID","since":"Date?"}"#

    private let store: LibraryStore

    public init(store: LibraryStore) { self.store = store }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(AnalyticsQueryInput.self, from: input)
        let since = params.since ?? .distantPast
        let summaries = try await MainActor.run {
            try store.snapshots(for: params.showID, since: since).map { snap in
                AnalyticsSnapshotSummary(
                    id: snap.id,
                    capturedAt: snap.capturedAt,
                    windowStart: snap.windowStart,
                    windowEnd: snap.windowEnd,
                    downloads: snap.downloads,
                    uniqueListeners: snap.uniqueListeners
                )
            }
        }
        return try JSONEncoder().encode(AnalyticsQueryOutput(snapshots: summaries))
    }
}
