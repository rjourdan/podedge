import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Mock Audio Pipeline

/// A controllable mock ``AudioPipeline`` for testing the ingest flow.
struct MockAudioPipeline: AudioPipeline, Sendable {

    var sha256Result: String = String(repeating: "a", count: 64)
    var probeResult: AudioProbeResult = AudioProbeResult(
        duration: 120.0,
        bitrate: 128_000,
        channels: 2,
        sampleRate: 44100
    )
    var waveformResult: [Float] = Array(repeating: Float(0.5), count: 1000)
    var id3Result: ID3Metadata = ID3Metadata(title: "Test Episode", artist: "Test Artist")

    var sha256Error: (any Error & Sendable)?
    var probeError: (any Error & Sendable)?
    var waveformError: (any Error & Sendable)?
    var id3Error: (any Error & Sendable)?

    func sha256(of url: URL) async throws -> String {
        if let error = sha256Error { throw error }
        return sha256Result
    }

    func probe(url: URL) async throws -> AudioProbeResult {
        if let error = probeError { throw error }
        return probeResult
    }

    func waveform(url: URL, sampleCount: Int) async throws -> [Float] {
        if let error = waveformError { throw error }
        return Array(waveformResult.prefix(sampleCount))
    }

    func readID3(url: URL) async throws -> ID3Metadata {
        if let error = id3Error { throw error }
        return id3Result
    }

    func writeID3(to url: URL, metadata: ID3Metadata) async throws {
        // No-op for tests.
    }
}

// MARK: - Test Fixture Helpers

/// Helpers for creating temporary test files.
enum IngestTestFixtures {

    /// Creates a temporary MP3 file with valid magic bytes for testing.
    static func createTestMP3(
        name: String = "test.mp3",
        sizeInBytes: Int = 4096
    ) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeIngestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent(name)

        // Build a minimal valid MP3-like file:
        // ID3 header (10 bytes) + MPEG sync word + filler
        var data = Data()
        // ID3v2 header: "ID3" + version 2.3 + no flags + size (synchsafe)
        data.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        data.append(contentsOf: [0x03, 0x00])         // v2.3
        data.append(0x00)                              // flags
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // synchsafe size = 0

        // MPEG sync word (valid frame header)
        data.append(contentsOf: [0xFF, 0xFB, 0x90, 0x00])

        // Fill to desired size
        let remaining = max(0, sizeInBytes - data.count)
        data.append(Data(repeating: 0x00, count: remaining))

        try data.write(to: fileURL)
        return fileURL
    }

    /// Creates a temporary file with invalid (non-MP3) content.
    static func createInvalidFile(name: String = "bad.txt") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeIngestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileURL = dir.appendingPathComponent(name)
        let data = Data("This is not an MP3 file at all, just plain text content padding.".utf8)
            + Data(repeating: 0x00, count: 2048)
        try data.write(to: fileURL)
        return fileURL
    }

    /// Creates a test ``Show`` and inserts it into the given context.
    @MainActor
    static func createTestShow(context: ModelContext) throws -> Show {
        let hostBinding = HostBinding(
            id: UUID(),
            kind: .s3,
            displayName: "Test Host",
            bucket: "test-bucket",
            region: "us-east-1",
            publicBaseURL: URL(string: "https://example.com")!,
            keychainRef: "test-key"
        )
        context.insert(hostBinding)

        let show = Show(
            title: "Test Podcast",
            author: "Tester",
            summary: "A test show",
            category: "Technology",
            ownerEmail: "test@example.com",
            ownerName: "Tester",
            hostBindingID: hostBinding.id,
            feedRemotePath: "shows/test/feed.xml"
        )
        context.insert(show)
        try context.save()
        return show
    }
}

// MARK: - MP3 Validator Tests

@Suite("MP3Validator")
struct MP3ValidatorTests {

    @Test("Validates a file with ID3 header and MPEG sync word")
    func validMP3WithID3() throws {
        let url = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try MP3Validator.validate(url: url)
    }

    @Test("Validates a file starting with MPEG sync word (no ID3)")
    func validMP3WithSyncOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeMP3Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("sync.mp3")
        var data = Data()
        data.append(contentsOf: [0xFF, 0xFB, 0x90, 0x00])
        data.append(Data(repeating: 0x00, count: 2048))
        try data.write(to: url)

        try MP3Validator.validate(url: url)
    }

    @Test("Rejects empty file")
    func emptyFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeMP3Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("empty.mp3")
        try Data().write(to: url)

        #expect(throws: PodedgeError.self) {
            try MP3Validator.validate(url: url)
        }
    }

    @Test("Rejects file smaller than 1 KB")
    func tooSmallFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeMP3Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("tiny.mp3")
        try Data(repeating: 0xFF, count: 512).write(to: url)

        #expect(throws: PodedgeError.self) {
            try MP3Validator.validate(url: url)
        }
    }

    @Test("Rejects non-MP3 file")
    func invalidMagicBytes() throws {
        let url = try IngestTestFixtures.createInvalidFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(throws: PodedgeError.self) {
            try MP3Validator.validate(url: url)
        }
    }

    @Test("Rejects nonexistent file")
    func nonexistentFile() throws {
        let url = URL(filePath: "/tmp/nonexistent-\(UUID().uuidString).mp3")

        #expect(throws: PodedgeError.self) {
            try MP3Validator.validate(url: url)
        }
    }
}

// MARK: - Waveform Save/Load Tests

@Suite("WaveformGenerator Save/Load")
struct WaveformSaveLoadTests {

    @Test("Round-trips waveform data through save and load")
    func roundTrip() throws {
        let original: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeWfmTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("test.wfm")
        try WaveformGenerator.save(waveform: original, to: url)

        let loaded = try WaveformGenerator.load(from: url)
        #expect(loaded.count == original.count)
        for (a, b) in zip(original, loaded) {
            #expect(abs(a - b) < 0.0001)
        }
    }

    @Test("Loading empty file returns empty array")
    func emptyFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeWfmTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("empty.wfm")
        try Data().write(to: url)

        let loaded = try WaveformGenerator.load(from: url)
        #expect(loaded.isEmpty)
    }
}

// MARK: - IngestService Tests

@Suite("IngestService", .serialized, .tags(.swiftData))
@MainActor
struct IngestServiceTests {

    private func makeStore() throws -> LibraryStore {
        try TestDatabase.reset()
        return LibraryStore(modelContext: TestDatabase.shared.mainContext)
    }

    @Test("Full ingest flow creates Asset, Episode, and follow-up jobs")
    func fullIngestFlow() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)
        let mockPipeline = MockAudioPipeline()

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)
        let episode = try await service.ingest(fileURL: mp3URL, show: show)

        // Episode should be ready.
        #expect(episode.status == .ready)
        #expect(episode.title == "Test Episode") // From mock ID3

        // Audio asset should exist.
        let audioAsset = try store.asset(id: episode.originalAssetID)
        let unwrappedAudioAsset = try #require(audioAsset)
        #expect(unwrappedAudioAsset.kind == .audioOriginal)
        #expect(unwrappedAudioAsset.contentType == "audio/mpeg")
        #expect(unwrappedAudioAsset.sha256 == String(repeating: "a", count: 64))
        #expect(unwrappedAudioAsset.durationSeconds == 120.0)

        // Follow-up jobs should be enqueued.
        let jobs = try store.jobs(for: episode.id)
        let jobKinds = Set(jobs.map(\.kind))
        #expect(jobKinds.contains(.transcribe))
        #expect(jobKinds.contains(.generateMetadata))

        // Clean up managed directory.
        let managedDir = unwrappedAudioAsset.localURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: managedDir)
    }

    @Test("Ingest throws for invalid MP3 file")
    func invalidMP3Throws() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)
        let mockPipeline = MockAudioPipeline()

        let show = try IngestTestFixtures.createTestShow(context: context)
        let badURL = try IngestTestFixtures.createInvalidFile()
        defer { try? FileManager.default.removeItem(at: badURL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)

        var didThrow = false
        do {
            _ = try await service.ingest(fileURL: badURL, show: show)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected ingest to throw for invalid MP3")
    }

    @Test("Ingest throws when probe fails")
    func probeFailureThrows() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)

        var mockPipeline = MockAudioPipeline()
        mockPipeline.probeError = PodedgeError.invalidMP3(reason: "Simulated probe failure")

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)

        var didThrow = false
        do {
            _ = try await service.ingest(fileURL: mp3URL, show: show)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected ingest to throw for probe failure")
    }

    @Test("Ingest throws when SHA-256 fails")
    func hashFailureThrows() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)

        var mockPipeline = MockAudioPipeline()
        mockPipeline.sha256Error = PodedgeError.invalidMP3(reason: "Simulated hash failure")

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)

        var didThrow = false
        do {
            _ = try await service.ingest(fileURL: mp3URL, show: show)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected ingest to throw for hash failure")
    }

    @Test("Ingest uses filename as title when ID3 title is empty")
    func fallbackToFilename() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)

        var mockPipeline = MockAudioPipeline()
        mockPipeline.id3Result = ID3Metadata() // No title

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3(name: "My Great Episode.mp3")
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)
        let episode = try await service.ingest(fileURL: mp3URL, show: show)

        // Should fall back to filename without extension.
        #expect(episode.title == "My Great Episode")
        #expect(episode.status == .ready)

        // Clean up managed directory.
        if let asset = try store.asset(id: episode.originalAssetID) {
            try? FileManager.default.removeItem(at: asset.localURL.deletingLastPathComponent())
        }
    }

    @Test("Ingest cleans up episode when waveform generation fails")
    func waveformFailureCleansUp() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)

        var mockPipeline = MockAudioPipeline()
        mockPipeline.waveformError = PodedgeError.invalidMP3(reason: "Simulated waveform failure")

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)

        var didThrow = false
        do {
            _ = try await service.ingest(fileURL: mp3URL, show: show)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected ingest to throw for waveform failure")

        // Episode should have been deleted (not left as orphan).
        let allEpisodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(allEpisodes.isEmpty, "Orphaned episode should have been cleaned up")
    }

    @Test("Ingest cleans up episode when ID3 read fails")
    func id3ReadFailureCleansUp() async throws {
        let store = try makeStore()
        let context = TestDatabase.shared.mainContext
        let scheduler = JobScheduler(modelContainer: TestDatabase.shared)

        var mockPipeline = MockAudioPipeline()
        mockPipeline.id3Error = PodedgeError.invalidMP3(reason: "Simulated ID3 read failure")

        let show = try IngestTestFixtures.createTestShow(context: context)
        let mp3URL = try IngestTestFixtures.createTestMP3()
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let service = IngestService(pipeline: mockPipeline, store: store, scheduler: scheduler)

        var didThrow = false
        do {
            _ = try await service.ingest(fileURL: mp3URL, show: show)
        } catch {
            didThrow = true
        }
        #expect(didThrow, "Expected ingest to throw for ID3 read failure")

        // Episode should have been deleted (not left as orphan).
        let allEpisodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(allEpisodes.isEmpty, "Orphaned episode should have been cleaned up")
    }
}

// MARK: - ID3TagService Tests

@Suite("ID3TagService")
struct ID3TagServiceTests {

    @Test("Round-trips ID3 tags through write and read")
    func roundTrip() async throws {
        let service = ID3TagService()

        // Create a minimal valid MP3 file to write tags to.
        let mp3URL = try IngestTestFixtures.createTestMP3(sizeInBytes: 8192)
        defer { try? FileManager.default.removeItem(at: mp3URL.deletingLastPathComponent()) }

        let original = ID3Metadata(
            title: "Round Trip Title",
            artist: "Round Trip Artist",
            album: "Round Trip Album"
        )

        try service.writeTags(to: mp3URL, metadata: original)

        // Read back and verify.
        let readBack = try await service.readTags(url: mp3URL)
        #expect(readBack.title == original.title)
        #expect(readBack.artist == original.artist)
        #expect(readBack.album == original.album)
    }
}

// MARK: - MP3Validator ID3-Only Tests

@Suite("MP3Validator ID3-Only")
struct MP3ValidatorID3OnlyTests {

    @Test("Rejects ID3-only file with no MPEG sync word")
    func id3OnlyFileRejected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeMP3Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("id3only.mp3")

        // Build a file with a valid ID3 header but no MPEG sync word after it.
        var data = Data()
        // ID3v2 header: "ID3" + version 2.3 + no flags
        data.append(contentsOf: [0x49, 0x44, 0x33]) // "ID3"
        data.append(contentsOf: [0x03, 0x00])         // v2.3
        data.append(0x00)                              // flags
        // Synchsafe size = 100 bytes of tag body
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x64])
        // 100 bytes of zero padding (tag body, no MPEG sync bytes)
        data.append(Data(repeating: 0x00, count: 100))
        // More padding after the tag — still no sync word
        data.append(Data(repeating: 0x00, count: 2048))

        try data.write(to: url)

        #expect(throws: PodedgeError.self) {
            try MP3Validator.validate(url: url)
        }
    }
}
