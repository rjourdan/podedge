import Foundation
import Testing

@testable import PodedgeCore

/// A configurable analytics provider for testing.
private struct StubAnalyticsProvider: AnalyticsProvider, Sendable {
    let providerName = "stub"
    let registerResult: Result<String, Error>
    let fetchResult: Result<AnalyticsFetchResult, Error>

    init(
        registerResult: Result<String, Error> = .success("stub-show-id"),
        fetchResult: Result<AnalyticsFetchResult, Error> = .success(
            AnalyticsFetchResult(downloads: 100, uniqueListeners: 50)
        )
    ) {
        self.registerResult = registerResult
        self.fetchResult = fetchResult
    }

    func register(feedURL: URL, podcastGUID: UUID) async throws -> String {
        try registerResult.get()
    }

    func prefixURL(for enclosureURL: URL) -> URL {
        enclosureURL
    }

    func fetchSnapshot(externalShowID: String, window: DateInterval) async throws -> AnalyticsFetchResult {
        try fetchResult.get()
    }
}

/// Thread-safe string collector for @Sendable closures.
private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [String] = []
    var values: [String] { lock.withLock { _values } }
    func append(_ value: String) { lock.withLock { _values.append(value) } }
}

@Suite("AnalyticsService")
struct AnalyticsServiceTests {

    @Test("registerShow adds show, duplicates ignored")
    func registerShow() async {
        let persisted = LockedStringArray()
        let service = AnalyticsService(
            provider: StubAnalyticsProvider(),
            pollingInterval: .seconds(3600),
            persistSnapshot: { showID, _ in persisted.append(showID) }
        )
        await service.registerShow(externalShowID: "show-1")
        await service.registerShow(externalShowID: "show-1") // Duplicate
        await service.registerShow(externalShowID: "show-2")

        await service.startPolling()
        try? await Task.sleep(for: .milliseconds(200))
        await service.stopPolling()

        // Should have polled 2 unique shows, not 3.
        #expect(persisted.values.count == 2)
        #expect(persisted.values.sorted() == ["show-1", "show-2"])
    }

    @Test("unregisterShow removes show from polling list")
    func unregisterShow() async {
        let persisted = LockedStringArray()
        let service = AnalyticsService(
            provider: StubAnalyticsProvider(),
            pollingInterval: .seconds(3600),
            persistSnapshot: { showID, _ in persisted.append(showID) }
        )
        await service.registerShow(externalShowID: "show-1")
        await service.unregisterShow(externalShowID: "show-1")

        await service.startPolling()
        try? await Task.sleep(for: .milliseconds(200))
        await service.stopPolling()

        #expect(persisted.values.isEmpty)
    }

    @Test("fetchNow delegates to provider")
    func fetchNowDelegatesToProvider() async throws {
        let expected = AnalyticsFetchResult(downloads: 42, uniqueListeners: 21)
        let service = AnalyticsService(
            provider: StubAnalyticsProvider(fetchResult: .success(expected)),
            persistSnapshot: { _, _ in }
        )
        let window = DateInterval(start: Date().addingTimeInterval(-3600), end: Date())
        let result = try await service.fetchNow(externalShowID: "any-id", window: window)
        #expect(result.downloads == 42)
        #expect(result.uniqueListeners == 21)
    }

    @Test("pollAll calls persistSnapshot for each registered show")
    func pollAllPersists() async throws {
        let persisted = LockedStringArray()
        let service = AnalyticsService(
            provider: StubAnalyticsProvider(),
            pollingInterval: .seconds(3600),
            persistSnapshot: { showID, _ in persisted.append(showID) }
        )
        await service.registerShow(externalShowID: "show-a")
        await service.registerShow(externalShowID: "show-b")

        await service.startPolling()
        try await Task.sleep(for: .milliseconds(200))
        await service.stopPolling()

        #expect(persisted.values.count == 2)
        #expect(persisted.values.sorted() == ["show-a", "show-b"])
    }

    @Test("pollAll continues on provider error")
    func pollAllContinuesOnError() async throws {
        let persisted = LockedStringArray()
        let failingProvider = StubAnalyticsProvider(
            fetchResult: .failure(PodedgeError.analyticsUnavailable(reason: "test"))
        )
        let service = AnalyticsService(
            provider: failingProvider,
            pollingInterval: .seconds(3600),
            persistSnapshot: { showID, _ in persisted.append(showID) }
        )
        await service.registerShow(externalShowID: "show-1")
        await service.registerShow(externalShowID: "show-2")

        await service.startPolling()
        try await Task.sleep(for: .milliseconds(200))
        await service.stopPolling()

        // Neither show should have been persisted since provider failed.
        #expect(persisted.values.isEmpty)
    }
}
