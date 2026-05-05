import Foundation
import Testing

@testable import PodedgeCore

// MARK: - Mock PodcastHost

final class MockPodcastHost: PodcastHost, @unchecked Sendable {
    private let lock = NSLock()
    private var _uploads: [(remotePath: String, contentType: String)] = []
    private var _headResults: [String: HostHeadResult] = [:]

    var uploads: [(remotePath: String, contentType: String)] {
        lock.withLock { _uploads }
    }

    func stubHead(remotePath: String, result: HostHeadResult) {
        lock.withLock { _headResults[remotePath] = result }
    }

    func put(
        localURL: URL, remotePath: String, contentType: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        lock.withLock { _uploads.append((remotePath, contentType)) }
        progress(1.0)
        return publicURL(for: remotePath)
    }

    func delete(remotePath: String) async throws {}

    func publicURL(for remotePath: String) -> URL {
        URL(string: "https://cdn.example.com/\(remotePath)")!
    }

    func head(remotePath: String) async throws -> HostHeadResult {
        lock.withLock { _headResults[remotePath] ?? HostHeadResult(exists: false) }
    }
}

// MARK: - Stub LLM Provider

struct PublishTestLLMProvider: LLMProvider {
    var responseText = "Check out this episode! #podcast"

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        LLMResponse(text: responseText, inputTokens: 10, outputTokens: 5, finishReason: .stop)
    }

    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
    }
}

// MARK: - Helpers

private func makeTempMP3() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("publish-tests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("\(UUID()).mp3")
    var data = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    data.append(Data([0xFF, 0xFB, 0x90, 0x00]))
    data.append(Data(repeating: 0x00, count: 128))
    try data.write(to: url)
    return url
}

// MARK: - PublishArtifactBuilder Tests

@Suite("PublishArtifactBuilder")
struct PublishArtifactBuilderTests {

    @Test("Returns original when no cover art or chapters")
    func noRewrite() async throws {
        let builder = PublishArtifactBuilder(pipeline: PassthroughPipeline())
        let url = try makeTempMP3()
        let artifact = try await builder.build(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(),
            originalURL: url, originalSHA256: "abc123", originalByteSize: 1000,
            coverArtData: nil, chaptersJSON: nil
        )
        #expect(!artifact.isRewritten)
        #expect(artifact.sha256 == "abc123")
        #expect(artifact.byteSize == 1000)
        #expect(artifact.localURL == url)
    }

    @Test("Rewrites when cover art is provided")
    func rewriteWithCoverArt() async throws {
        let builder = PublishArtifactBuilder(pipeline: PassthroughPipeline())
        let url = try makeTempMP3()
        let artifact = try await builder.build(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(),
            originalURL: url, originalSHA256: "abc123", originalByteSize: 1000,
            coverArtData: Data([0xFF, 0xD8, 0xFF, 0xE0]), chaptersJSON: nil
        )
        #expect(artifact.isRewritten)
        #expect(artifact.localURL != url)
        #expect(artifact.byteSize > 0)
    }

    @Test("Rewrites when chapters JSON is provided")
    func rewriteWithChapters() async throws {
        let builder = PublishArtifactBuilder(pipeline: PassthroughPipeline())
        let url = try makeTempMP3()
        let artifact = try await builder.build(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(),
            originalURL: url, originalSHA256: "abc123", originalByteSize: 1000,
            coverArtData: nil, chaptersJSON: "{\"chapters\":[]}"
        )
        #expect(artifact.isRewritten)
        #expect(artifact.localURL != url)
    }

    @Test("Rewritten file is larger when cover art embedded")
    func rewrittenFileGrows() async throws {
        let builder = PublishArtifactBuilder(pipeline: PassthroughPipeline())
        let url = try makeTempMP3()
        let artifact = try await builder.build(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(),
            originalURL: url, originalSHA256: "abc123", originalByteSize: 142,
            coverArtData: Data(repeating: 0xAB, count: 256), chaptersJSON: nil
        )
        #expect(artifact.byteSize > 142)
    }
}

// MARK: - Test Environment

@MainActor
private struct PublishTestEnv {
    let store: LibraryStore
    let show: Show
    let episode: Episode
    let mockHost: MockPodcastHost
    let distributionService: DistributionService
    let service: PublishService
    let dryRun: PublishDryRun

    static func make(chaptersJSON: String? = nil) throws -> PublishTestEnv {
        let container = TestDatabase.container(for: "publish")
        try TestDatabase.reset(container)
        let store = LibraryStore(modelContext: container.mainContext)

        let binding = HostBinding(
            displayName: "Test Host", bucket: "b", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.example.com")!,
            keychainRef: "unused"
        )
        store.addHostBinding(binding)

        // Cover art with remotePath so feed builder can resolve it.
        let coverURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]).write(to: coverURL)
        let coverAsset = Asset(
            kind: .coverArt, localURL: coverURL, remotePath: "art/cover.jpg",
            sha256: "coverhash", byteSize: 6, contentType: "image/jpeg"
        )
        store.addAsset(coverAsset)

        let show = Show(
            title: "Test Podcast", author: "Author", summary: "Summary",
            category: "Technology", ownerEmail: "t@t.com", ownerName: "Author",
            coverArtAssetID: coverAsset.id, hostBindingID: binding.id,
            feedRemotePath: "shows/test/feed.xml"
        )
        store.addShow(show)

        let audioURL = try makeTempMP3()
        let originalAsset = Asset(
            kind: .audioOriginal, localURL: audioURL,
            sha256: String(repeating: "a", count: 64),
            byteSize: 142, contentType: "audio/mpeg", durationSeconds: 60
        )
        store.addAsset(originalAsset)

        let episode = Episode(
            title: "Ep 1", summary: "First episode",
            originalAssetID: originalAsset.id, status: .ready,
            chaptersJSON: chaptersJSON
        )
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        let mockHost = MockPodcastHost()
        let distService = DistributionService()
        let keychain = KeychainService(service: "com.podedge.test.unused.\(UUID())")
        let hostService = HostService(keychain: keychain)
        let feedBuilder = FeedBuilder(resolveAsset: { _ in nil })
        let artifactBuilder = PublishArtifactBuilder(pipeline: PassthroughPipeline())

        let service = PublishService(
            store: store, hostService: hostService,
            feedBuilder: feedBuilder, feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: distService, artifactBuilder: artifactBuilder
        )
        let dryRun = PublishDryRun(
            store: store, hostService: hostService,
            feedBuilder: feedBuilder, feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: distService, artifactBuilder: artifactBuilder
        )

        return PublishTestEnv(
            store: store, show: show, episode: episode,
            mockHost: mockHost, distributionService: distService,
            service: service, dryRun: dryRun
        )
    }
}

// MARK: - Publish Pipeline Tests (serialized — shares SwiftData container)

@Suite("PublishService", .serialized, .tags(.swiftData))
struct PublishServiceTests {

    @Test("Full pipeline uploads audio then feed")
    @MainActor func fullPipeline() async throws {
        let env = try PublishTestEnv.make()
        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)

        let paths = env.mockHost.uploads.map(\.remotePath)
        let audioIdx = paths.firstIndex { $0.hasSuffix(".mp3") }
        let feedIdx = paths.firstIndex { $0.hasSuffix("feed.xml") }
        #expect(audioIdx != nil)
        #expect(feedIdx != nil)
        if let a = audioIdx, let f = feedIdx { #expect(a < f) }
        #expect(env.episode.status == .published)
        #expect(env.episode.pubDate != nil)
        #expect(env.episode.publishedAssetID != nil)
    }

    @Test("Idempotent upload skips when ETag matches")
    @MainActor func idempotentSkip() async throws {
        let env = try PublishTestEnv.make()
        let sha = String(repeating: "a", count: 64)
        let audioPath = "shows/test-podcast/\(env.episode.id).mp3"
        env.mockHost.stubHead(remotePath: audioPath, result: HostHeadResult(exists: true, eTag: "\"\(sha)\""))

        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)

        let audioPuts = env.mockHost.uploads.filter { $0.remotePath.hasSuffix(".mp3") }
        #expect(audioPuts.isEmpty)
        let feedPuts = env.mockHost.uploads.filter { $0.contentType == "application/rss+xml" }
        #expect(!feedPuts.isEmpty)
    }

    @Test("Episode status transitions to published")
    @MainActor func statusTransition() async throws {
        let env = try PublishTestEnv.make()
        #expect(env.episode.status == .ready)
        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(env.episode.status == .published)
    }

    @Test("Feed validation issues block publish")
    @MainActor func feedValidationBlocks() async throws {
        let env = try PublishTestEnv.make()
        env.show.author = ""
        env.show.ownerEmail = ""
        await #expect(throws: PodedgeError.self) {
            try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)
        }
        #expect(env.episode.status != .published)
    }

    @Test("Distribution fan-out after feed upload")
    @MainActor func distributionFanOut() async throws {
        let env = try PublishTestEnv.make()
        await env.distributionService.register(StubDistributionTarget(targetID: "test-dist", displayName: "Test"))
        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)
        let feedPuts = env.mockHost.uploads.filter { $0.contentType == "application/rss+xml" }
        #expect(!feedPuts.isEmpty)
        #expect(env.episode.status == .published)
    }

    @Test("Uploads transcript when available")
    @MainActor func uploadsTranscript() async throws {
        let env = try PublishTestEnv.make()
        let txURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).vtt")
        try "WEBVTT\n\n00:00.000 --> 00:01.000\nHello".data(using: .utf8)!.write(to: txURL)
        let txAsset = Asset(kind: .transcript, localURL: txURL, sha256: "txhash", byteSize: 40, contentType: "text/vtt")
        env.store.addAsset(txAsset)
        env.episode.transcriptAssetID = txAsset.id
        try env.store.save()
        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(env.mockHost.uploads.contains { $0.contentType == "text/vtt" })
    }

    @Test("Uploads chapters when available")
    @MainActor func uploadsChapters() async throws {
        let env = try PublishTestEnv.make(chaptersJSON: "{\"chapters\":[]}")
        try await env.service.publish(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(env.mockHost.uploads.contains { $0.contentType == "application/json" })
    }

    // MARK: - Dry Run

    @Test("Dry run produces correct plan")
    @MainActor func dryRunBasicPlan() async throws {
        let env = try PublishTestEnv.make()
        let plan = try await env.dryRun.plan(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(plan.uploads.count >= 2)
        #expect(plan.uploads.contains { $0.contentType == "audio/mpeg" })
        #expect(plan.uploads.contains { $0.contentType == "application/rss+xml" })
    }

    @Test("Dry run marks audio as already uploaded when ETag matches")
    @MainActor func dryRunAlreadyUploaded() async throws {
        let env = try PublishTestEnv.make()
        let sha = String(repeating: "a", count: 64)
        let audioPath = "shows/test-podcast/\(env.episode.id).mp3"
        env.mockHost.stubHead(remotePath: audioPath, result: HostHeadResult(exists: true, eTag: sha))
        let plan = try await env.dryRun.plan(show: env.show, episode: env.episode, host: env.mockHost)
        let audioUpload = plan.uploads.first { $0.contentType == "audio/mpeg" }
        #expect(audioUpload?.alreadyUploaded == true)
    }

    @Test("Dry run includes chapters upload")
    @MainActor func dryRunChapters() async throws {
        let env = try PublishTestEnv.make(chaptersJSON: "{\"chapters\":[]}")
        let plan = try await env.dryRun.plan(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(plan.uploads.contains { $0.contentType == "application/json" })
    }

    @Test("Dry run includes distribution targets")
    @MainActor func dryRunDistTargets() async throws {
        let env = try PublishTestEnv.make()
        await env.distributionService.register(StubDistributionTarget(targetID: "apple", displayName: "Apple"))
        let plan = try await env.dryRun.plan(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(plan.distributionTargets.contains("apple"))
    }

    @Test("Dry run reports feed validation issues")
    @MainActor func dryRunValidationIssues() async throws {
        let env = try PublishTestEnv.make()
        env.show.author = ""
        let plan = try await env.dryRun.plan(show: env.show, episode: env.episode, host: env.mockHost)
        #expect(!plan.feedValidationIssues.isEmpty)
    }
}

// MARK: - SocialBlurbRenderer Tests

@Suite("SocialBlurbRenderer")
struct SocialBlurbRendererTests {

    @Test("X renderer has 280 char limit")
    func xPlatform() {
        let r = SocialBlurbRenderer.x(llmService: LLMService(provider: PublishTestLLMProvider()))
        #expect(r.platform == "x")
        #expect(r.maxLength == 280)
    }

    @Test("Bluesky renderer has 300 char limit")
    func blueskyPlatform() {
        let r = SocialBlurbRenderer.bluesky(llmService: LLMService(provider: PublishTestLLMProvider()))
        #expect(r.platform == "bluesky")
        #expect(r.maxLength == 300)
    }

    @Test("Mastodon renderer has 500 char limit")
    func mastodonPlatform() {
        let r = SocialBlurbRenderer.mastodon(llmService: LLMService(provider: PublishTestLLMProvider()))
        #expect(r.platform == "mastodon")
        #expect(r.maxLength == 500)
    }

    @Test("LinkedIn renderer has 3000 char limit")
    func linkedInPlatform() {
        let r = SocialBlurbRenderer.linkedIn(llmService: LLMService(provider: PublishTestLLMProvider()))
        #expect(r.platform == "linkedin")
        #expect(r.maxLength == 3000)
    }

    @Test("Threads renderer has 500 char limit")
    func threadsPlatform() {
        let r = SocialBlurbRenderer.threads(llmService: LLMService(provider: PublishTestLLMProvider()))
        #expect(r.platform == "threads")
        #expect(r.maxLength == 500)
    }

    @Test("Render produces output with hashtags")
    func renderOutput() async throws {
        let r = SocialBlurbRenderer.x(llmService: LLMService(provider: PublishTestLLMProvider()))
        let output = try await r.render(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(), transcript: "Some text"
        )
        #expect(!output.text.isEmpty)
        #expect(output.characterCount > 0)
        #expect(output.hashtags.contains("podcast"))
    }

    @Test("Render truncates to maxLength")
    func renderTruncates() async throws {
        let provider = PublishTestLLMProvider(responseText: String(repeating: "A", count: 500))
        let r = SocialBlurbRenderer.x(llmService: LLMService(provider: provider))
        let output = try await r.render(
            episode: makeTestEpisodeSnapshot(), show: makeTestShowSnapshot(), transcript: nil
        )
        #expect(output.characterCount <= 280)
    }
}
