import Foundation
import Testing

@testable import PodedgeCore

@Suite("OP3AnalyticsProvider", .serialized)
struct OP3AnalyticsProviderTests {

    private static let testGUID = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!

    init() {
        StubURLProtocol.removeStubs(withPathContaining: "api/1/shows")
        StubURLProtocol.removeStubs(withPathContaining: "op3-show-")
    }

    private func makeProvider(session: URLSession = makeStubSession()) -> OP3AnalyticsProvider {
        OP3AnalyticsProvider(
            baseURL: URL(string: "https://op3.dev")!,
            apiToken: "test-token",
            session: session
        )
    }

    @Test("prefixURL rewrites enclosure URL correctly — exact byte-for-byte match")
    func prefixURL() {
        let provider = makeProvider()
        let original = URL(string: "https://cdn.example.com/audio/ep1.mp3")!
        let prefixed = provider.prefixURL(for: original)
        #expect(prefixed.absoluteString == "https://op3.dev/e/cdn.example.com/audio/ep1.mp3")
    }

    @Test("prefixURL handles http URLs")
    func prefixURLHTTP() {
        let provider = makeProvider()
        let original = URL(string: "http://cdn.example.com/audio/ep1.mp3")!
        let prefixed = provider.prefixURL(for: original)
        #expect(prefixed.absoluteString == "https://op3.dev/e/cdn.example.com/audio/ep1.mp3")
    }

    @Test("register parses showUuid from response")
    func registerSuccess() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: ["showUuid": "abc-123"])
        StubURLProtocol.stub(path: "api/1/shows", response: .init(statusCode: 200, body: responseBody))

        let provider = makeProvider()
        let showID = try await provider.register(
            feedURL: URL(string: "https://example.com/feed.xml")!,
            podcastGUID: Self.testGUID
        )
        #expect(showID == "abc-123")
    }

    @Test("register throws on missing showUuid")
    func registerMissingID() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: ["status": "ok"])
        StubURLProtocol.stub(path: "api/1/shows", response: .init(statusCode: 200, body: responseBody))

        let provider = makeProvider()
        await #expect(throws: PodedgeError.self) {
            try await provider.register(
                feedURL: URL(string: "https://example.com/feed.xml")!,
                podcastGUID: Self.testGUID
            )
        }
    }

    @Test("register throws on HTTP error")
    func registerHTTPError() async throws {
        StubURLProtocol.stub(path: "api/1/shows", response: .init(statusCode: 500))

        let provider = makeProvider()
        await #expect(throws: PodedgeError.self) {
            try await provider.register(
                feedURL: URL(string: "https://example.com/feed.xml")!,
                podcastGUID: Self.testGUID
            )
        }
    }

    @Test("fetchSnapshot parses downloads and listeners")
    func fetchSnapshotSuccess() async throws {
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "downloads": 1500,
            "uniqueListeners": 800,
            "apps": ["Apple Podcasts": 600, "Overcast": 400],
            "geos": ["US": 1000, "UK": 300],
        ] as [String: Any])
        StubURLProtocol.stub(path: "op3-show-abc/downloads", response: .init(statusCode: 200, body: responseBody))

        let provider = makeProvider()
        let window = DateInterval(start: Date().addingTimeInterval(-3600), end: Date())
        let result = try await provider.fetchSnapshot(externalShowID: "op3-show-abc", window: window)

        #expect(result.downloads == 1500)
        #expect(result.uniqueListeners == 800)
        #expect(result.appBreakdown["Apple Podcasts"] == 600)
        #expect(result.geoBreakdown["US"] == 1000)
    }

    @Test("fetchSnapshot throws on HTTP error")
    func fetchSnapshotHTTPError() async throws {
        StubURLProtocol.stub(path: "op3-show-fail/downloads", response: .init(statusCode: 401))

        let provider = makeProvider()
        let window = DateInterval(start: Date().addingTimeInterval(-3600), end: Date())
        await #expect(throws: PodedgeError.self) {
            try await provider.fetchSnapshot(externalShowID: "op3-show-fail", window: window)
        }
    }

    @Test("providerName is op3")
    func providerName() {
        let provider = makeProvider()
        #expect(provider.providerName == "op3")
    }
}
