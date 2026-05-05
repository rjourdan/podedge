import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Pure Model Tests (no SwiftData container needed)

@Suite("Domain Models")
struct DomainModelTests {

    @Test("Episode GUID is locked at creation")
    func episodeGUIDLocked() {
        let ep = Episode(title: "Test", originalAssetID: UUID())
        #expect(!ep.guid.isEmpty)
    }

    @Test("Episode GUID defaults to ID when not provided")
    func episodeGUIDDefaultsToID() {
        let id = UUID()
        let ep = Episode(id: id, title: "Test", originalAssetID: UUID())
        #expect(ep.guid == id.uuidString)
    }

    @Test("Episode GUID uses custom value when provided")
    func episodeGUIDCustom() {
        let ep = Episode(title: "Test", guid: "custom-guid", originalAssetID: UUID())
        #expect(ep.guid == "custom-guid")
    }

    @Test("Show podcastGUID is set at creation")
    func showPodcastGUID() {
        let show = Show(
            title: "S", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        #expect(show.podcastGUID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
    }

    @Test("Show defaults to locked")
    func showDefaultsLocked() {
        let show = Show(
            title: "S", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        #expect(show.podcastLocked)
    }

    @Test("Episode defaults to draft status")
    func episodeDefaultsDraft() {
        let ep = Episode(title: "E", originalAssetID: UUID())
        #expect(ep.status == .draft)
    }

    @Test("Episode defaults to full type")
    func episodeDefaultsFull() {
        let ep = Episode(title: "E", originalAssetID: UUID())
        #expect(ep.type == .full)
    }

    @Test("Job defaults to pending state")
    func jobDefaultsPending() {
        let job = Job(kind: .ingest, targetID: UUID())
        #expect(job.state == .pending)
        #expect(job.attempts == 0)
    }

    @Test("Asset stores all required fields")
    func assetFields() {
        let asset = Asset(
            kind: .audioOriginal,
            localURL: URL(filePath: "/tmp/test.mp3"),
            sha256: "abc123",
            byteSize: 1024,
            contentType: "audio/mpeg",
            durationSeconds: 3600.0
        )
        #expect(asset.kind == .audioOriginal)
        #expect(asset.byteSize == 1024)
        #expect(asset.durationSeconds == 3600.0)
    }

    @Test("HostBinding stores all required fields")
    func hostBindingFields() {
        let binding = HostBinding(
            displayName: "My Bucket",
            bucket: "podcast-bucket",
            region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.example.com")!,
            keychainRef: "s3-key-ref"
        )
        #expect(binding.kind == .s3)
        #expect(binding.bucket == "podcast-bucket")
    }

    @Test("Episode snapshot populates enclosureByteSize from resolved asset")
    func episodeSnapshotEnclosureByteSize() {
        let assetID = UUID()
        let asset = Asset(
            id: assetID, kind: .audioPublished,
            localURL: URL(filePath: "/tmp/pub.mp3"),
            sha256: "deadbeef", byteSize: 98_765_432,
            contentType: "audio/mpeg"
        )
        let ep = Episode(
            title: "With Asset",
            originalAssetID: UUID(),
            publishedAssetID: assetID
        )

        let snap = ep.snapshot(resolvingAsset: { id in id == assetID ? asset : nil })
        #expect(snap.enclosureByteSize == 98_765_432)
    }

    @Test("Episode snapshot defaults enclosureByteSize to zero without resolver")
    func episodeSnapshotEnclosureByteSizeDefault() {
        let ep = Episode(
            title: "No Asset",
            originalAssetID: UUID(),
            publishedAssetID: UUID()
        )
        #expect(ep.snapshot.enclosureByteSize == 0)
    }

    @Test("PodedgeError provides localized descriptions")
    func errorDescriptions() {
        let error = PodedgeError.invalidMP3(reason: "not MPEG")
        #expect(error.errorDescription?.contains("not MPEG") == true)
    }

    @Test("AnalyticsBinding stores defaults correctly")
    func analyticsBindingDefaults() {
        let binding = AnalyticsBinding(
            prefixBaseURL: URL(string: "https://op3.dev/e")!
        )
        #expect(binding.provider == "op3")
        #expect(binding.keychainRef == nil)
        #expect(binding.externalShowID == nil)
    }

    @Test("DistributionRecord stores defaults correctly")
    func distributionRecordDefaults() {
        let record = DistributionRecord(targetID: "apple-podcasts")
        #expect(record.status == .notSubmitted)
        #expect(record.externalShowID == nil)
        #expect(record.submittedAt == nil)
        #expect(record.note == nil)
    }
}

// MARK: - SwiftData Integration Tests
// These tests require an app host (Xcode test runner) because SwiftData's
// ModelContainer crashes in the bare SPM test runner. They are tagged so
// they can be skipped in `swift test` and run in Xcode.

@Suite("LibraryStore CRUD", .serialized, .tags(.swiftData))
@MainActor
struct LibraryStoreTests {

    private func makeStore() throws -> LibraryStore {
        let container = TestDatabase.container(for: "library")
        try TestDatabase.reset(container)
        return LibraryStore(modelContext: container.mainContext)
    }

    // MARK: - Shows

    @Test("Create and fetch a show")
    func createShow() throws {
        let store = try makeStore()
        let show = Show(
            title: "Test Show",
            author: "Tester",
            summary: "A test podcast",
            category: "Technology",
            ownerEmail: "test@example.com",
            ownerName: "Tester",
            hostBindingID: UUID(),
            feedRemotePath: "shows/test/feed.xml"
        )
        store.addShow(show)
        try store.save()

        let fetched = try store.allShows()
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Test Show")
    }

    @Test("Fetch show by ID")
    func fetchShowByID() throws {
        let store = try makeStore()
        let id = UUID()
        let show = Show(
            id: id, title: "By ID", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        store.addShow(show)
        try store.save()

        let found = try store.show(id: id)
        #expect(found?.title == "By ID")

        let missing = try store.show(id: UUID())
        #expect(missing == nil)
    }

    @Test("Delete a show cascades episodes")
    func deleteShowCascadesEpisodes() throws {
        let store = try makeStore()
        let show = Show(
            title: "Cascade", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        store.addShow(show)

        let episode = Episode(title: "Ep1", originalAssetID: UUID())
        episode.show = show
        store.addEpisode(episode)
        try store.save()

        let episodeID = episode.id

        store.deleteShow(show)
        try store.save()

        let shows = try store.allShows()
        #expect(shows.isEmpty)

        let orphan = try store.episode(id: episodeID)
        #expect(orphan == nil)
    }

    // MARK: - Episodes

    @Test("Add and fetch episodes for a show")
    func episodesForShow() throws {
        let store = try makeStore()
        let show = Show(
            title: "S", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        store.addShow(show)

        let ep = Episode(title: "E1", originalAssetID: UUID())
        ep.show = show
        store.addEpisode(ep)
        try store.save()

        let eps = try store.episodes(for: show.id)
        #expect(eps.count == 1)
        #expect(eps.first?.title == "E1")
    }

    // MARK: - Assets

    @Test("Add and fetch asset by ID")
    func assetCRUD() throws {
        let store = try makeStore()
        let id = UUID()
        let asset = Asset(
            id: id, kind: .audioOriginal, localURL: URL(filePath: "/tmp/test.mp3"),
            sha256: "abc123", byteSize: 1024, contentType: "audio/mpeg"
        )
        store.addAsset(asset)
        try store.save()

        let found = try store.asset(id: id)
        #expect(found?.sha256 == "abc123")
    }

    // MARK: - Jobs

    @Test("Pending jobs are fetched in creation order")
    func pendingJobs() throws {
        let store = try makeStore()
        let target = UUID()
        let j1 = Job(kind: .ingest, targetID: target, createdAt: Date(timeIntervalSince1970: 1))
        let j2 = Job(kind: .transcribe, targetID: target, createdAt: Date(timeIntervalSince1970: 2))
        let j3 = Job(kind: .upload, targetID: target, state: .done, createdAt: Date(timeIntervalSince1970: 0))
        store.addJob(j1)
        store.addJob(j2)
        store.addJob(j3)
        try store.save()

        let pending = try store.pendingJobs()
        #expect(pending.count == 2)
        #expect(pending.first?.kind == .ingest)
    }

    // MARK: - Host Bindings

    @Test("Host binding CRUD")
    func hostBindingCRUD() throws {
        let store = try makeStore()
        let binding = HostBinding(
            displayName: "My Bucket", bucket: "podcast-bucket",
            region: "us-east-1",
            publicBaseURL: URL(string: "https://cdn.example.com")!,
            keychainRef: "s3-key-ref"
        )
        store.addHostBinding(binding)
        try store.save()

        let all = try store.allHostBindings()
        #expect(all.count == 1)
        #expect(all.first?.bucket == "podcast-bucket")
    }

    // MARK: - Analytics Snapshots

    @Test("Snapshots filtered by date")
    func snapshotsByDate() throws {
        let store = try makeStore()
        let show = Show(
            title: "S", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        store.addShow(show)

        let old = AnalyticsSnapshot(
            show: show,
            capturedAt: Date(timeIntervalSince1970: 100),
            windowStart: Date(timeIntervalSince1970: 0),
            windowEnd: Date(timeIntervalSince1970: 100),
            downloads: 10
        )
        let recent = AnalyticsSnapshot(
            show: show,
            capturedAt: Date(timeIntervalSince1970: 500),
            windowStart: Date(timeIntervalSince1970: 100),
            windowEnd: Date(timeIntervalSince1970: 500),
            downloads: 50
        )
        store.addSnapshot(old)
        store.addSnapshot(recent)
        try store.save()

        let since = Date(timeIntervalSince1970: 200)
        let results = try store.snapshots(for: show.id, since: since)
        #expect(results.count == 1)
        #expect(results.first?.downloads == 50)
    }

    // MARK: - Distribution Records

    @Test("Add and query distribution records for a show")
    func distributionsForShow() throws {
        let store = try makeStore()
        let show = Show(
            title: "S", author: "A", summary: "",
            category: "Arts", ownerEmail: "a@b.com", ownerName: "A",
            hostBindingID: UUID(), feedRemotePath: "feed.xml"
        )
        store.addShow(show)

        let record = DistributionRecord(show: show, targetID: "apple-podcasts")
        store.addDistribution(record)
        try store.save()

        let results = try store.distributions(for: show.id)
        #expect(results.count == 1)
        #expect(results.first?.targetID == "apple-podcasts")
    }
}

// MARK: - Custom Tags

extension Tag {
    /// Tests that require SwiftData ModelContainer (need Xcode test runner).
    @Tag static var swiftData: Self
}
