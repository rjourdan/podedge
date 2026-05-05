import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

/// Provides SwiftData containers for tests.
///
/// Each test suite that uses SwiftData should call ``container(for:)`` with a
/// unique label. This returns a dedicated ``ModelContainer`` backed by its own
/// on-disk store, eliminating cross-suite interference when suites run in parallel.
enum TestDatabase {
    /// The shared container, used by suites that need a stable container reference
    /// (e.g. ``JobScheduler`` which takes a ``ModelContainer`` at init).
    @MainActor
    static let shared: ModelContainer = container(for: "shared")

    /// Returns a container for the given label, creating it on first access.
    ///
    /// Containers are cached so that repeated calls with the same label within
    /// a suite return the same container.
    @MainActor
    static func container(for label: String) -> ModelContainer {
        if let existing = containers[label] { return existing }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeCoreTests", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(label)-\(ProcessInfo.processInfo.processIdentifier).store")
        try? FileManager.default.removeItem(at: url)
        let c = try! PodedgeSchema.makeContainer(url: url)
        containers[label] = c
        return c
    }

    @MainActor
    private static var containers: [String: ModelContainer] = [:]

    /// Deletes all model objects from the given container's main context.
    ///
    /// Call at the start of each test to ensure a clean slate.
    @MainActor
    static func reset(_ container: ModelContainer) throws {
        let context = container.mainContext

        // Delete leaf entities first, then parents.
        for obj in try context.fetch(FetchDescriptor<AnalyticsSnapshot>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<DistributionRecord>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<Episode>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<Job>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<Asset>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<AgentAuditEntry>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<HostBinding>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<AnalyticsBinding>()) { context.delete(obj) }
        for obj in try context.fetch(FetchDescriptor<Show>()) { context.delete(obj) }

        try context.save()
    }

    /// Deletes all model objects from the shared container's main context.
    @MainActor
    static func reset() throws {
        try reset(shared)
    }
}

// MARK: - StubURLProtocol

/// A `URLProtocol` subclass that returns pre-configured responses for testing.
///
/// Register stub responses before creating a `URLSession` with a configuration
/// that includes this protocol class.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    /// Thread-safe storage for stub responses keyed by URL path.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stubs: [String: StubResponse] = [:]

    /// A pre-configured HTTP response for testing.
    struct StubResponse: Sendable {
        var statusCode: Int
        var headers: [String: String]
        var body: Data

        init(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    /// Registers a stub response for requests matching the given path suffix.
    static func stub(path: String, response: StubResponse) {
        lock.withLock { _stubs[path] = response }
    }

    /// Removes all registered stubs.
    static func reset() {
        lock.withLock { _stubs.removeAll() }
    }

    /// Removes stubs whose path key contains the given substring.
    ///
    /// Use instead of ``reset()`` when multiple stub-using test suites run in
    /// parallel. Each suite removes only its own stubs, avoiding cross-suite
    /// interference.
    static func removeStubs(withPathContaining substring: String) {
        lock.withLock {
            _stubs = _stubs.filter { !$0.key.contains(substring) }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let urlString = request.url?.absoluteString ?? ""
        let stub: StubResponse? = Self.lock.withLock {
            // Prefer the longest matching path to avoid greedy short matches.
            var bestMatch: (String, StubResponse)?
            for (path, response) in Self._stubs {
                if urlString.contains(path) {
                    if bestMatch == nil || path.count > bestMatch!.0.count {
                        bestMatch = (path, response)
                    }
                }
            }
            return bestMatch?.1
        }

        let response = stub ?? StubResponse(statusCode: 404, body: Data())
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!

        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Creates a `URLSession` configured to use ``StubURLProtocol``.
func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Test Fixture Helpers

/// Creates a minimal ``ShowSnapshot`` for testing.
func makeTestShowSnapshot(
    id: UUID = UUID(),
    title: String = "Test Podcast",
    podcastGUID: UUID = UUID(),
    hostBindingID: UUID = UUID(),
    analyticsBindingID: UUID? = nil,
    coverArtAssetID: UUID? = nil
) -> ShowSnapshot {
    ShowSnapshot(
        id: id,
        title: title,
        author: "Test Author",
        summary: "A test podcast about testing.",
        language: "en-US",
        category: "Technology",
        subcategory: "Software How-To",
        explicit: false,
        copyright: "© 2026 Test Author",
        ownerEmail: "test@example.com",
        ownerName: "Test Author",
        podcastGUID: podcastGUID,
        podcastLocked: true,
        feedRemotePath: "shows/test/feed.xml",
        hostBindingID: hostBindingID,
        analyticsBindingID: analyticsBindingID,
        coverArtAssetID: coverArtAssetID
    )
}

/// Creates a minimal ``EpisodeSnapshot`` for testing.
func makeTestEpisodeSnapshot(
    id: UUID = UUID(),
    title: String = "Episode 1",
    guid: String? = nil,
    pubDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
    publishedAssetID: UUID? = UUID(),
    chaptersJSON: String? = nil,
    coverArtAssetID: UUID? = nil,
    season: Int? = 1,
    number: Int? = 1
) -> EpisodeSnapshot {
    EpisodeSnapshot(
        id: id,
        title: title,
        subtitle: "A test episode",
        summary: "Summary of \(title)",
        descriptionHTML: "<p>Description of \(title)</p>",
        season: season,
        number: number,
        type: .full,
        explicit: false,
        guid: guid ?? id.uuidString,
        status: .published,
        pubDate: pubDate,
        chaptersJSON: chaptersJSON,
        originalAssetID: UUID(),
        publishedAssetID: publishedAssetID,
        coverArtAssetID: coverArtAssetID
    )
}
