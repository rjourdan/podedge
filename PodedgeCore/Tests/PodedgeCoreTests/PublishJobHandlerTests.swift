import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Mock Notification Service

private final class MockNotificationService: NotificationServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _successCalls: [String] = []
    private var _failureCalls: [(title: String, reason: String)] = []

    var successCalls: [String] { lock.withLock { _successCalls } }
    var failureCalls: [(title: String, reason: String)] { lock.withLock { _failureCalls } }

    func sendPublishSuccess(episodeTitle: String) async {
        lock.withLock { _successCalls.append(episodeTitle) }
    }

    func sendPublishFailure(episodeTitle: String, reason: String) async {
        lock.withLock { _failureCalls.append((episodeTitle, reason)) }
    }
}

// MARK: - Tests

@Suite("PublishJobHandler", .serialized, .tags(.swiftData))
@MainActor
struct PublishJobHandlerTests {

    private static let db = "publishJobHandler"

    private func makeContainer() throws -> ModelContainer {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        return container
    }

    /// Creates a full test environment with stubbed network and keychain.
    private func makeEnv(container: ModelContainer) async throws -> (
        handler: PublishJobHandler,
        notifications: MockNotificationService,
        show: Show,
        episode: Episode,
        job: Job
    ) {
        let context = container.mainContext
        let store = LibraryStore(modelContext: context)

        let keychainRef = "publish-test-\(UUID())"
        let binding = HostBinding(
            displayName: "Test", bucket: "test-bucket", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: keychainRef
        )
        store.addHostBinding(binding)

        // Store credential so resolveHost succeeds.
        let keychain = KeychainService(service: "com.podedge.test.publishhandler")
        try await keychain.storeCredential(
            HostCredential(accessKeyID: "AKIA", secretAccessKey: "secret"),
            forKey: keychainRef
        )

        let coverURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: coverURL)
        let coverAsset = Asset(
            kind: .coverArt, localURL: coverURL, remotePath: "art/cover.jpg",
            sha256: "coverhash", byteSize: 4, contentType: "image/jpeg"
        )
        store.addAsset(coverAsset)

        let show = Show(
            title: "Test Show", author: "Author", summary: "Summary",
            category: "Technology", ownerEmail: "t@t.com", ownerName: "Author",
            coverArtAssetID: coverAsset.id, hostBindingID: binding.id,
            feedRemotePath: "shows/test/feed.xml"
        )
        store.addShow(show)

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        var data = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        data.append(Data([0xFF, 0xFB, 0x90, 0x00]))
        data.append(Data(repeating: 0x00, count: 128))
        try data.write(to: audioURL)

        let audioAsset = Asset(
            kind: .audioOriginal, localURL: audioURL,
            sha256: String(repeating: "a", count: 64),
            byteSize: 142, contentType: "audio/mpeg", durationSeconds: 60
        )
        store.addAsset(audioAsset)

        let episode = Episode(
            title: "Ep 1", summary: "First episode",
            originalAssetID: audioAsset.id, status: .ready
        )
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        let job = Job(kind: .publish, targetID: episode.id)
        context.insert(job)
        try context.save()

        // Stub all S3 requests to succeed.
        StubURLProtocol.stub(path: "test-bucket", response: .init(statusCode: 200, body: Data()))
        let session = makeStubSession()

        let hostService = HostService(keychain: keychain, sessionProvider: { session })
        let publishService = PublishService(
            store: store, hostService: hostService,
            feedBuilder: FeedBuilder(resolveAsset: { _ in nil }),
            feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: DistributionService(),
            artifactBuilder: PublishArtifactBuilder(pipeline: PassthroughPipeline())
        )

        let notifications = MockNotificationService()
        let handler = PublishJobHandler(publishService: publishService, notificationService: notifications)

        return (handler, notifications, show, episode, job)
    }

    @Test("Handler calls publish service and sets episode published")
    func testPublishCallsService() async throws {
        let container = try makeContainer()
        let (handler, _, _, episode, job) = try await makeEnv(container: container)
        let episodeID = episode.id

        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch from main context since handler uses its own ModelContext.
        var desc = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
        desc.fetchLimit = 1
        let updated = try container.mainContext.fetch(desc).first
        #expect(updated?.status == .published)
    }

    @Test("Handler sets episode status to failed on error")
    func testPublishSetsFailedOnError() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = LibraryStore(modelContext: context)

        // Create show with non-existent host binding to force failure.
        let show = Show(
            title: "Fail Show", author: "A", summary: "S",
            category: "Tech", ownerEmail: "t@t.com", ownerName: "A",
            hostBindingID: UUID(),
            feedRemotePath: "shows/fail/feed.xml"
        )
        store.addShow(show)

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try Data(repeating: 0xFF, count: 100).write(to: audioURL)
        let asset = Asset(kind: .audioOriginal, localURL: audioURL, sha256: "aaa", byteSize: 100, contentType: "audio/mpeg")
        store.addAsset(asset)

        let episode = Episode(title: "Fail Ep", originalAssetID: asset.id, status: .ready)
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        let job = Job(kind: .publish, targetID: episode.id)
        context.insert(job)
        try context.save()

        let keychain = KeychainService(service: "com.podedge.test.fail.\(UUID())")
        let hostService = HostService(keychain: keychain)
        let publishService = PublishService(
            store: store, hostService: hostService,
            feedBuilder: FeedBuilder(resolveAsset: { _ in nil }),
            feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: DistributionService(),
            artifactBuilder: PublishArtifactBuilder(pipeline: PassthroughPipeline())
        )

        let notifications = MockNotificationService()
        let handler = PublishJobHandler(publishService: publishService, notificationService: notifications)

        let episodeID = episode.id
        await #expect(throws: PodedgeError.self) {
            try await handler.execute(jobID: job.id, container: container)
        }

        // Re-fetch episode since handler uses its own ModelContext.
        var desc = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
        desc.fetchLimit = 1
        let updated = try context.fetch(desc).first
        #expect(updated?.status == .failed)
    }

    @Test("Handler sends success notification")
    func testPublishSendsSuccessNotification() async throws {
        let container = try makeContainer()
        let (handler, notifications, _, _, job) = try await makeEnv(container: container)

        try await handler.execute(jobID: job.id, container: container)

        #expect(notifications.successCalls == ["Ep 1"])
    }

    @Test("Handler sends failure notification on error")
    func testPublishSendsFailureNotification() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = LibraryStore(modelContext: context)

        let show = Show(
            title: "Notif Show", author: "A", summary: "S",
            category: "Tech", ownerEmail: "t@t.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "shows/notif/feed.xml"
        )
        store.addShow(show)

        let audioURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).mp3")
        try Data(repeating: 0xFF, count: 100).write(to: audioURL)
        let asset = Asset(kind: .audioOriginal, localURL: audioURL, sha256: "aaa", byteSize: 100, contentType: "audio/mpeg")
        store.addAsset(asset)

        let episode = Episode(title: "Notif Ep", originalAssetID: asset.id, status: .ready)
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        let job = Job(kind: .publish, targetID: episode.id)
        context.insert(job)
        try context.save()

        let keychain = KeychainService(service: "com.podedge.test.notif.\(UUID())")
        let hostService = HostService(keychain: keychain)
        let publishService = PublishService(
            store: store, hostService: hostService,
            feedBuilder: FeedBuilder(resolveAsset: { _ in nil }),
            feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: DistributionService(),
            artifactBuilder: PublishArtifactBuilder(pipeline: PassthroughPipeline())
        )

        let notifications = MockNotificationService()
        let handler = PublishJobHandler(publishService: publishService, notificationService: notifications)

        _ = try? await handler.execute(jobID: job.id, container: container)

        #expect(notifications.failureCalls.count == 1)
        #expect(notifications.failureCalls.first?.title == "Notif Ep")
    }

    @Test("Handler skips already published episode")
    func testPublishSkipsAlreadyPublished() async throws {
        let container = try makeContainer()
        let (handler, notifications, _, episode, job) = try await makeEnv(container: container)

        // Mark as already published.
        episode.status = .published
        try container.mainContext.save()

        try await handler.execute(jobID: job.id, container: container)

        #expect(notifications.successCalls.isEmpty)
        #expect(notifications.failureCalls.isEmpty)
    }
}
