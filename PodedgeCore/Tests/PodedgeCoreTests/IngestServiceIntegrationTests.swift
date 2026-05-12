import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

@Suite("IngestService Integration Tests", .tags(.swiftData), .serialized)
@MainActor
struct IngestServiceIntegrationTests {

    private static let db = "ingestIntegration"

    private func makeContext() throws -> (LibraryStore, ModelContainer) {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        let store = LibraryStore(modelContext: container.mainContext)
        return (store, container)
    }

    private func makeShow(store: LibraryStore) throws -> Show {
        let show = Show(
            title: "Test Show",
            author: "Author",
            summary: "Desc",
            language: "en-US",
            category: "Technology",
            explicit: false,
            ownerEmail: "test@test.com",
            ownerName: "Test",
            hostBindingID: UUID(),
            feedRemotePath: "feed.xml"
        )
        store.addShow(show)
        try store.modelContext.save()
        return show
    }

    @Test("Ingest creates episode and assets")
    func ingestCreatesEpisodeAndAssets() async throws {
        let (store, container) = try makeContext()
        let context = container.mainContext
        let scheduler = JobScheduler(modelContainer: container)
        let pipeline = MockAudioPipeline()
        let service = IngestService(pipeline: pipeline, store: store, scheduler: scheduler)

        let show = try makeShow(store: store)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let episode = try await service.ingest(fileURL: mp3URL, show: show)

        #expect(episode.status == .ready)
        #expect(episode.title == "Test Episode")

        // Verify assets were created
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let audioAssets = assets.filter { $0.kind == .audioOriginal }
        let waveformAssets = assets.filter { $0.kind == .waveform }
        #expect(audioAssets.count == 1)
        #expect(waveformAssets.count == 1)

        let audioAsset = try #require(audioAssets.first)
        #expect(audioAsset.sha256.count == 64)
        #expect(audioAsset.byteSize > 0)
        #expect(audioAsset.durationSeconds ?? 0 > 0)

        // Clean up managed directory
        try? FileManager.default.removeItem(at: audioAsset.localURL.deletingLastPathComponent())
    }

    @Test("Ingest enqueues transcribe and metadata jobs with correct parent")
    func ingestEnqueuesJobsWithParent() async throws {
        let (store, container) = try makeContext()
        let context = container.mainContext
        let scheduler = JobScheduler(modelContainer: container)
        let pipeline = MockAudioPipeline()
        let service = IngestService(pipeline: pipeline, store: store, scheduler: scheduler)

        let show = try makeShow(store: store)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let episode = try await service.ingest(fileURL: mp3URL, show: show)

        let jobs = try context.fetch(FetchDescriptor<Job>())
        let transcribeJob = try #require(jobs.first { $0.kind == .transcribe && $0.targetID == episode.id })
        let metadataJob = try #require(jobs.first { $0.kind == .generateMetadata && $0.targetID == episode.id })

        #expect(metadataJob.parentJobID == transcribeJob.id)

        // Clean up managed directory
        if let asset = try context.fetch(FetchDescriptor<Asset>()).first(where: { $0.kind == .audioOriginal }) {
            try? FileManager.default.removeItem(at: asset.localURL.deletingLastPathComponent())
        }
    }

    @Test("Ingest failure cleans up episode")
    func ingestFailureDeletesEpisode() async throws {
        let (store, container) = try makeContext()
        let context = container.mainContext
        let scheduler = JobScheduler(modelContainer: container)

        var pipeline = MockAudioPipeline()
        pipeline.probeError = PodedgeError.invalidMP3(reason: "Corrupted")
        let service = IngestService(pipeline: pipeline, store: store, scheduler: scheduler)

        let show = try makeShow(store: store)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        await #expect(throws: PodedgeError.self) {
            _ = try await service.ingest(fileURL: mp3URL, show: show)
        }

        // No orphaned episodes
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.isEmpty)
    }

    @Test("Ingest rejects invalid MP3 with validation error")
    func ingestRejectsInvalidMP3() async throws {
        let (store, container) = try makeContext()
        let context = container.mainContext
        let scheduler = JobScheduler(modelContainer: container)
        let pipeline = MockAudioPipeline()
        let service = IngestService(pipeline: pipeline, store: store, scheduler: scheduler)

        let show = try makeShow(store: store)

        // Create a file that fails MP3 validation (no MPEG sync word, no ID3 header)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InvalidMP3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let invalidURL = dir.appendingPathComponent("invalid.mp3")
        let invalidData = Data(repeating: 0x00, count: 4096)
        try invalidData.write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: dir) }

        await #expect(throws: PodedgeError.self) {
            _ = try await service.ingest(fileURL: invalidURL, show: show)
        }

        // No orphaned episodes
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(episodes.isEmpty)
    }
}
