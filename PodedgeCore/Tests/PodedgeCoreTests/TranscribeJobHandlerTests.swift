import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Test Helpers

/// A mock engine that always throws, used to verify failure handling.
private struct ThrowingMockEngine: TranscriptionEngine, Sendable {

    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        throw PodedgeError.transcriptionFailed(reason: "Mock failure")
    }

    func availableModels() async throws -> [TranscriptionModelInfo] { [] }
    func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws {}
}

/// A mock engine used exclusively for TranscribeJobHandler tests.
private struct JobTestMockEngine: TranscriptionEngine, Sendable {

    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        TranscriptionResult(
            plainText: "Hello from the handler test.",
            vttContent: "WEBVTT\n\n1\n00:00:00.000 --> 00:00:03.000\nHello from the handler test.\n",
            segments: [
                TranscriptionSegment(startTime: 0, endTime: 3, text: "Hello from the handler test.")
            ]
        )
    }

    func availableModels() async throws -> [TranscriptionModelInfo] { [] }
    func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws {}
}

// MARK: - Tests

@Suite("TranscribeJobHandler", .serialized, .tags(.swiftData))
@MainActor
struct TranscribeJobHandlerTests {

    private static let db = "transcribeJobHandler"

    private func makeContainer() throws -> ModelContainer {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        return container
    }

    /// Creates an episode with an audio asset file on disk and a pending transcribe job.
    private func setupEpisodeWithAudio(
        container: ModelContainer
    ) throws -> (episode: Episode, job: Job, audioURL: URL) {
        let context = container.mainContext

        // Create a temp audio file.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscribeHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let audioURL = dir.appendingPathComponent("episode.mp3")
        try Data("fake audio content".utf8).write(to: audioURL)

        // Create audio asset.
        let audioAsset = Asset(
            kind: .audioOriginal,
            localURL: audioURL,
            sha256: String(repeating: "a", count: 64),
            byteSize: 1024,
            contentType: "audio/mpeg",
            durationSeconds: 60.0
        )
        context.insert(audioAsset)

        // Create episode referencing the asset.
        let episode = Episode(
            title: "Test Episode",
            originalAssetID: audioAsset.id,
            status: .ready
        )
        context.insert(episode)

        // Create transcribe job targeting the episode.
        let job = Job(kind: .transcribe, targetID: episode.id)
        context.insert(job)

        try context.save()
        return (episode, job, audioURL)
    }

    @Test("Handler sets transcriptAssetID on episode after successful transcription")
    func testHandlerSetsTranscriptAssetID() async throws {
        let container = try makeContainer()
        let (episode, job, audioURL) = try setupEpisodeWithAudio(container: container)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        let engine = JobTestMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch episode from a fresh context to verify persistence.
        let context = ModelContext(container)
        let episodeID = episode.id
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
        descriptor.fetchLimit = 1
        let updated = try context.fetch(descriptor).first
        #expect(updated?.transcriptAssetID != nil)
    }

    @Test("Job state is .done after successful handler execution (via scheduler)")
    func testHandlerMarksJobDone() async throws {
        let container = try makeContainer()
        let (_, job, audioURL) = try setupEpisodeWithAudio(container: container)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        let engine = JobTestMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        let scheduler = JobScheduler(modelContainer: container)
        scheduler.registerHandler(handler)
        scheduler.start()

        // Poll for job completion (max 10 seconds).
        let context = container.mainContext
        let jobID = job.id
        var attempts = 0
        while attempts < 100 {
            try await Task.sleep(for: .milliseconds(100))
            let jobs = try context.fetch(FetchDescriptor<Job>())
            if let j = jobs.first(where: { $0.id == jobID }), j.state == .done {
                break
            }
            attempts += 1
        }
        scheduler.stop()

        // Verify job state.
        var descriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        descriptor.fetchLimit = 1
        let fetched = try context.fetch(descriptor).first
        #expect(fetched?.state == .done)
    }

    @Test("Handler throws when episode has no audio asset")
    func testHandlerFailsWithoutAudioAsset() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Episode with a non-existent asset ID.
        let episode = Episode(
            title: "No Audio",
            originalAssetID: UUID(),
            status: .ready
        )
        context.insert(episode)

        let job = Job(kind: .transcribe, targetID: episode.id)
        context.insert(job)
        try context.save()

        let engine = JobTestMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        await #expect(throws: PodedgeError.self) {
            try await handler.execute(jobID: job.id, container: container)
        }
    }

    @Test("Transcript asset sha256 is 64 hex characters")
    func testTranscriptAssetHasValidSHA256() async throws {
        let container = try makeContainer()
        let (_, job, audioURL) = try setupEpisodeWithAudio(container: container)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        let engine = JobTestMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        try await handler.execute(jobID: job.id, container: container)

        // Fetch the transcript asset.
        let context = ModelContext(container)
        let assets = try context.fetch(FetchDescriptor<Asset>())
        let transcriptAsset = try #require(assets.first { $0.kind == .transcript })

        #expect(transcriptAsset.sha256.count == 64)
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")
        let isAllHex = transcriptAsset.sha256.unicodeScalars.allSatisfy { hexCharacterSet.contains($0) }
        #expect(isAllHex)
    }

    @Test("transcriptAssetID is set after transcribe job completes")
    func testTranscriptAssetIDSetAfterJob() async throws {
        let container = try makeContainer()
        let (episode, job, audioURL) = try setupEpisodeWithAudio(container: container)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        // Verify precondition: no transcript yet.
        #expect(episode.transcriptAssetID == nil)

        let engine = JobTestMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch to verify.
        let context = ModelContext(container)
        let episodeID = episode.id
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
        descriptor.fetchLimit = 1
        let updated = try #require(try context.fetch(descriptor).first)
        #expect(updated.transcriptAssetID != nil)

        // Verify the referenced asset exists and is a transcript.
        let assetID = try #require(updated.transcriptAssetID)
        var assetDescriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == assetID })
        assetDescriptor.fetchLimit = 1
        let asset = try #require(try context.fetch(assetDescriptor).first)
        #expect(asset.kind == .transcript)
        #expect(asset.contentType == "text/vtt")
    }

    @Test("Handler marks episode as failed when engine throws")
    func testHandlerMarksJobFailedOnEngineError() async throws {
        let container = try makeContainer()
        let (episode, job, audioURL) = try setupEpisodeWithAudio(container: container)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        let engine = ThrowingMockEngine()
        let service = TranscriptionService(engine: engine)
        let handler = TranscribeJobHandler(transcriptionService: service)

        await #expect(throws: PodedgeError.self) {
            try await handler.execute(jobID: job.id, container: container)
        }

        // Re-fetch episode and verify status is .failed.
        let context = ModelContext(container)
        let episodeID = episode.id
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == episodeID })
        descriptor.fetchLimit = 1
        let updated = try #require(try context.fetch(descriptor).first)
        #expect(updated.status == .failed)
    }
}
