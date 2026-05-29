import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

@Suite("Publish Pipeline Properties")
struct PublishPipelinePropertyTests {

    // MARK: - Invariant 4: scheduledFor must be in the future

    @Test("Past scheduledFor is rejected", arguments: [-3600.0, -1.0, 0.0])
    func pastScheduledForRejected(offset: Double) {
        let pastDate = Date().addingTimeInterval(offset)
        #expect(throws: PodedgeError.self) {
            try Episode.validateScheduledFor(pastDate)
        }
    }

    @Test("Future scheduledFor is accepted")
    func futureScheduledForAccepted() throws {
        let futureDate = Date().addingTimeInterval(3600)
        try Episode.validateScheduledFor(futureDate)
    }

    // MARK: - Invariant 1: Published episode has pubDate

    @Test("Published episode has non-nil pubDate after publish", .tags(.swiftData))
    @MainActor
    func publishedEpisodeHasPubDate() async throws {
        let container = TestDatabase.container(for: "publishProperty")
        try TestDatabase.reset(container)
        let store = LibraryStore(modelContext: container.mainContext)

        let binding = HostBinding(
            displayName: "T", bucket: "b", region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.test.com")!,
            keychainRef: "unused"
        )
        store.addHostBinding(binding)

        let coverURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: coverURL)
        let coverAsset = Asset(
            kind: .coverArt, localURL: coverURL, remotePath: "art/c.jpg",
            sha256: "ch", byteSize: 4, contentType: "image/jpeg"
        )
        store.addAsset(coverAsset)

        let show = Show(
            title: "Prop Show", author: "A", summary: "S",
            category: "Tech", ownerEmail: "t@t.com", ownerName: "A",
            coverArtAssetID: coverAsset.id, hostBindingID: binding.id,
            feedRemotePath: "shows/prop/feed.xml"
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
            title: "Prop Ep", summary: "Test",
            originalAssetID: audioAsset.id, status: .ready
        )
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        #expect(episode.pubDate == nil)

        let mockHost = MockPodcastHost()
        let keychain = KeychainService(service: "com.podedge.test.prop.\(UUID())")
        let hostService = HostService(keychain: keychain)
        let publishService = PublishService(
            store: store, hostService: hostService,
            feedBuilder: FeedBuilder(resolveAsset: { _ in nil }),
            feedValidator: FeedValidator(),
            feedSerializer: FeedXMLSerializer(),
            distributionService: DistributionService(),
            artifactBuilder: PublishArtifactBuilder(pipeline: PassthroughPipeline())
        )

        try await publishService.publish(show: show, episode: episode, host: mockHost)

        #expect(episode.pubDate != nil)
        #expect(episode.status == .published)
    }
}
