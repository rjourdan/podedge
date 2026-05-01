import Foundation
import Testing

@testable import PodedgeCore

// MARK: - Stub Distribution Target

/// A configurable distribution target for testing.
struct StubDistributionTarget: DistributionTarget, Sendable {
    let targetID: String
    let displayName: String
    let mode: DistributionMode
    let submitResult: Result<DistributionSubmission, Error>
    let refreshResult: DistributionStatus

    init(
        targetID: String = "stub",
        displayName: String = "Stub Target",
        mode: DistributionMode = .api,
        submitResult: Result<DistributionSubmission, Error> = .success(
            DistributionSubmission(externalShowID: "stub-123", status: .pending)
        ),
        refreshResult: DistributionStatus = .live
    ) {
        self.targetID = targetID
        self.displayName = displayName
        self.mode = mode
        self.submitResult = submitResult
        self.refreshResult = refreshResult
    }

    func submit(feedURL: URL, show: ShowSnapshot) async throws -> DistributionSubmission {
        try submitResult.get()
    }

    func refreshStatus(externalShowID: String) async throws -> DistributionStatus {
        refreshResult
    }
}

// MARK: - DistributionService Tests

@Suite("DistributionService")
struct DistributionServiceTests {

    private let feedURL = URL(string: "https://cdn.example.com/feed.xml")!

    @Test("Register and submit to a target")
    func registerAndSubmit() async throws {
        let service = DistributionService()
        let target = StubDistributionTarget()
        await service.register(target)

        let show = makeTestShowSnapshot()
        let result = try await service.submit(targetID: "stub", feedURL: feedURL, show: show)
        #expect(result.externalShowID == "stub-123")
        #expect(result.status == .pending)
    }

    @Test("Submit throws for unregistered target")
    func submitUnregistered() async {
        let service = DistributionService()
        let show = makeTestShowSnapshot()
        await #expect(throws: PodedgeError.self) {
            try await service.submit(targetID: "nonexistent", feedURL: feedURL, show: show)
        }
    }

    @Test("Refresh status returns target's status")
    func refreshStatus() async throws {
        let service = DistributionService()
        let target = StubDistributionTarget(refreshResult: .live)
        await service.register(target)

        let status = try await service.refreshStatus(targetID: "stub", externalShowID: "stub-123")
        #expect(status == .live)
    }

    @Test("submitToAll returns results for all targets")
    func submitToAll() async {
        let service = DistributionService()
        await service.register(StubDistributionTarget(targetID: "a", displayName: "A"))
        await service.register(StubDistributionTarget(targetID: "b", displayName: "B"))

        let show = makeTestShowSnapshot()
        let results = await service.submitToAll(feedURL: feedURL, show: show)
        #expect(results.count == 2)
        #expect(results["a"] != nil)
        #expect(results["b"] != nil)
    }

    @Test("submitToAll captures errors per target")
    func submitToAllWithError() async {
        let service = DistributionService()
        await service.register(StubDistributionTarget(targetID: "ok", displayName: "OK"))
        await service.register(StubDistributionTarget(
            targetID: "fail",
            displayName: "Fail",
            submitResult: .failure(PodedgeError.distributionFailed(target: "fail", reason: "test error"))
        ))

        let show = makeTestShowSnapshot()
        let results = await service.submitToAll(feedURL: feedURL, show: show)

        if case .success = results["ok"] {
            // expected
        } else {
            Issue.record("Expected success for 'ok' target")
        }

        if case .failure = results["fail"] {
            // expected
        } else {
            Issue.record("Expected failure for 'fail' target")
        }
    }

    @Test("registeredTargetIDs returns all registered IDs")
    func registeredTargetIDs() async {
        let service = DistributionService()
        await service.register(StubDistributionTarget(targetID: "x", displayName: "X"))
        await service.register(StubDistributionTarget(targetID: "y", displayName: "Y"))

        let ids = await service.registeredTargetIDs
        #expect(ids.sorted() == ["x", "y"])
    }
}

// MARK: - Guided Target Tests

@Suite("Guided Distribution Targets", .serialized)
struct GuidedTargetTests {

    private let feedURL = URL(string: "https://cdn.example.com/feed.xml")!

    init() {
        StubURLProtocol.removeStubs(withPathContaining: "add/byfeedurl")
        StubURLProtocol.removeStubs(withPathContaining: "api/ping")
    }

    @Test("ApplePodcastsTarget is guided mode with correct URL")
    func appleTarget() async throws {
        let target = ApplePodcastsTarget()
        #expect(target.mode == .guided)
        #expect(target.targetID == "apple")
        #expect(target.guidedURL.absoluteString == "https://podcasters.apple.com")

        let show = makeTestShowSnapshot()
        let result = try await target.submit(feedURL: feedURL, show: show)
        #expect(result.status == .pending)
        #expect(result.note?.contains("podcasters.apple.com") == true)
    }

    @Test("SpotifyTarget is guided mode with correct URL")
    func spotifyTarget() async throws {
        let target = SpotifyTarget()
        #expect(target.mode == .guided)
        #expect(target.targetID == "spotify")
        #expect(target.guidedURL.absoluteString == "https://podcasters.spotify.com")

        let show = makeTestShowSnapshot()
        let result = try await target.submit(feedURL: feedURL, show: show)
        #expect(result.status == .pending)
        #expect(result.note?.contains("podcasters.spotify.com") == true)
    }

    @Test("AmazonMusicTarget is guided mode with correct URL")
    func amazonTarget() async throws {
        let target = AmazonMusicTarget()
        #expect(target.mode == .guided)
        #expect(target.targetID == "amazon")
        #expect(target.guidedURL.absoluteString == "https://podcasters.amazon.com")

        let show = makeTestShowSnapshot()
        let result = try await target.submit(feedURL: feedURL, show: show)
        #expect(result.status == .pending)
        #expect(result.note?.contains("podcasters.amazon.com") == true)
    }

    @Test("PodcastIndexTarget is API mode")
    func podcastIndexMode() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: ["feedId": 42])
        StubURLProtocol.stub(path: "add/byfeedurl", response: .init(statusCode: 200, body: responseBody))

        let target = PodcastIndexTarget(
            apiKey: "test-key",
            apiSecret: "test-secret",
            session: makeStubSession()
        )
        #expect(target.mode == .api)
        #expect(target.targetID == "podcastindex")

        let show = makeTestShowSnapshot()
        let result = try await target.submit(feedURL: feedURL, show: show)
        #expect(result.externalShowID == "42")
        #expect(result.status == .pending)
    }

    @Test("PodpingTarget is API mode and returns live")
    func podpingTarget() async throws {
        StubURLProtocol.stub(path: "api/ping", response: .init(statusCode: 200))

        let target = PodpingTarget(session: makeStubSession())
        #expect(target.mode == .api)

        let show = makeTestShowSnapshot()
        let result = try await target.submit(feedURL: feedURL, show: show)
        #expect(result.status == .live)
    }
}
