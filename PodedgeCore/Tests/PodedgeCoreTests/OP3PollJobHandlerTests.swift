import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Mock Analytics Provider

private struct MockAnalyticsProvider: AnalyticsProvider {
    var providerName: String { "mock" }
    var fetchedShowIDs: SharedArray<String> = SharedArray()

    func register(feedURL: URL, podcastGUID: UUID) async throws -> String { "mock-id" }
    func prefixURL(for enclosureURL: URL) -> URL { enclosureURL }

    func fetchSnapshot(externalShowID: String, window: DateInterval) async throws -> AnalyticsFetchResult {
        await fetchedShowIDs.append(externalShowID)
        return AnalyticsFetchResult(downloads: 42, uniqueListeners: 10)
    }
}

/// Thread-safe array for test assertions.
private actor SharedArray<T> {
    var values: [T] = []
    func append(_ value: T) { values.append(value) }
}

// MARK: - Tests

@Suite("OP3PollJobHandler", .serialized, .tags(.swiftData))
@MainActor
struct OP3PollJobHandlerTests {

    private static let db = "op3PollJobHandler"

    private func makeContainer() throws -> ModelContainer {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        return container
    }

    private func makeEnv(container: ModelContainer) throws -> (
        handler: OP3PollJobHandler,
        provider: MockAnalyticsProvider,
        show: Show,
        job: Job
    ) {
        let context = container.mainContext

        let analyticsBinding = AnalyticsBinding(
            provider: "op3",
            externalShowID: "ext-show-123",
            prefixBaseURL: URL(string: "https://op3.dev/e")!
        )
        context.insert(analyticsBinding)

        let binding = HostBinding(
            displayName: "Test", bucket: "b", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: "k"
        )
        context.insert(binding)

        let show = Show(
            title: "Poll Show", author: "A", summary: "S",
            category: "Tech", ownerEmail: "t@t.com", ownerName: "A",
            hostBindingID: binding.id,
            feedRemotePath: "shows/poll/feed.xml",
            analyticsBindingID: analyticsBinding.id
        )
        context.insert(show)

        let job = Job(kind: .op3Poll, targetID: show.id)
        context.insert(job)
        try context.save()

        let provider = MockAnalyticsProvider()
        let service = AnalyticsService(provider: provider, persistSnapshot: { _, _ in })
        let handler = OP3PollJobHandler(analyticsService: service)

        return (handler, provider, show, job)
    }

    @Test("Handler enqueues next poll job after execution")
    func testEnqueuesNextPollJob() async throws {
        let container = try makeContainer()
        let (handler, _, show, job) = try makeEnv(container: container)

        try await handler.execute(jobID: job.id, container: container)

        // Check that a new op3Poll job was created.
        let context = ModelContext(container)
        let showID = show.id
        let jobs = try context.fetch(FetchDescriptor<Job>())
        let nextPollJobs = jobs.filter { $0.kind == .op3Poll && $0.id != job.id && $0.targetID == showID }
        #expect(nextPollJobs.count == 1)
    }

    @Test("Next poll job has correct delay in payload")
    func testNextPollHasCorrectDelay() async throws {
        let container = try makeContainer()
        let (handler, _, _, job) = try makeEnv(container: container)

        try await handler.execute(jobID: job.id, container: container)

        let context = ModelContext(container)
        let jobs = try context.fetch(FetchDescriptor<Job>())
        let nextJob = try #require(jobs.first { $0.kind == .op3Poll && $0.id != job.id })
        #expect(nextJob.payloadJSON?.contains("21600") == true)
    }

    @Test("Handler fetches analytics for correct show")
    func testFetchesAnalyticsForCorrectShow() async throws {
        let container = try makeContainer()
        let (handler, provider, _, job) = try makeEnv(container: container)

        try await handler.execute(jobID: job.id, container: container)

        let fetched = await provider.fetchedShowIDs.values
        #expect(fetched == ["ext-show-123"])
    }
}
