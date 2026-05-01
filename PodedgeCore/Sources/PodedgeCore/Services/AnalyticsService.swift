import Foundation
import os

/// Coordinates analytics polling across shows, persisting snapshots via a callback.
///
/// Polls the configured ``AnalyticsProvider`` every 6 hours for each registered show.
public actor AnalyticsService {

    /// Callback to persist an analytics fetch result. Receives the external show ID and the result.
    public typealias PersistSnapshot = @Sendable (String, AnalyticsFetchResult) async throws -> Void

    private let provider: any AnalyticsProvider
    private let persistSnapshot: PersistSnapshot
    private let pollingInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var registeredShows: [String] = []
    private let logger = PodedgeLogger.analytics

    /// Creates an analytics service.
    ///
    /// - Parameters:
    ///   - provider: The analytics provider to poll.
    ///   - pollingInterval: How often to poll. Defaults to 6 hours.
    ///   - persistSnapshot: Callback invoked with each fetched snapshot for persistence.
    public init(
        provider: any AnalyticsProvider,
        pollingInterval: Duration = .seconds(6 * 3600),
        persistSnapshot: @escaping PersistSnapshot
    ) {
        self.provider = provider
        self.pollingInterval = pollingInterval
        self.persistSnapshot = persistSnapshot
    }

    /// Registers a show for periodic analytics polling.
    ///
    /// - Parameter externalShowID: The provider-assigned show identifier.
    public func registerShow(externalShowID: String) {
        guard !registeredShows.contains(externalShowID) else { return }
        registeredShows.append(externalShowID)
    }

    /// Removes a show from periodic polling.
    ///
    /// - Parameter externalShowID: The provider-assigned show identifier.
    public func unregisterShow(externalShowID: String) {
        registeredShows.removeAll { $0 == externalShowID }
    }

    /// Starts the periodic polling loop.
    public func startPolling() {
        guard pollingTask == nil else { return }
        let interval = pollingInterval
        pollingTask = Task {
            while !Task.isCancelled {
                await self.pollAll()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Stops the periodic polling loop.
    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Fetches a snapshot for a single show on demand.
    ///
    /// - Parameters:
    ///   - externalShowID: The provider-assigned show identifier.
    ///   - window: The date interval to query.
    /// - Returns: The fetched analytics result.
    public func fetchNow(
        externalShowID: String,
        window: DateInterval
    ) async throws -> AnalyticsFetchResult {
        try await provider.fetchSnapshot(externalShowID: externalShowID, window: window)
    }

    // MARK: - Private

    private func pollAll() async {
        let now = Date()
        let window = DateInterval(start: now.addingTimeInterval(-6 * 3600), end: now)

        for showID in registeredShows {
            do {
                let result = try await provider.fetchSnapshot(externalShowID: showID, window: window)
                try await persistSnapshot(showID, result)
                logger.info("Polled analytics for show \(showID, privacy: .public): \(result.downloads) downloads")
            } catch {
                logger.error("Analytics poll failed for \(showID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
