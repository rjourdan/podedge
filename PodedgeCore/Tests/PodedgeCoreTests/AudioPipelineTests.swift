import Foundation
import Testing

@testable import PodedgeCore

@Suite("PassthroughPipeline")
struct PassthroughPipelineTests {

    private let pipeline = PassthroughPipeline()
    private let dummyURL = URL(filePath: "/tmp/test.mp3")

    @Test("sha256 returns 64 zeros")
    func sha256ReturnsZeros() async throws {
        let hash = try await pipeline.sha256(of: dummyURL)
        #expect(hash == String(repeating: "0", count: 64))
        #expect(hash.count == 64)
    }

    @Test("probe returns zero values")
    func probeReturnsZeros() async throws {
        let result = try await pipeline.probe(url: dummyURL)
        #expect(result.duration == 0)
        #expect(result.bitrate == 0)
        #expect(result.channels == 0)
        #expect(result.sampleRate == 0)
        #expect(result.loudnessLUFS == nil)
    }

    @Test("waveform returns correct count of zero samples")
    func waveformReturnsCorrectCount() async throws {
        let count = 128
        let waveform = try await pipeline.waveform(url: dummyURL, sampleCount: count)
        #expect(waveform.count == count)
        #expect(waveform.allSatisfy { $0 == 0 })
    }

    @Test("waveform with zero count returns empty array")
    func waveformZeroCount() async throws {
        let waveform = try await pipeline.waveform(url: dummyURL, sampleCount: 0)
        #expect(waveform.isEmpty)
    }

    @Test("readID3 returns empty metadata")
    func readID3ReturnsEmpty() async throws {
        let metadata = try await pipeline.readID3(url: dummyURL)
        #expect(metadata.title == nil)
        #expect(metadata.artist == nil)
        #expect(metadata.album == nil)
        #expect(metadata.coverImageData == nil)
        #expect(metadata.chapters.isEmpty)
    }

    @Test("writeID3 does not throw")
    func writeID3DoesNotThrow() async throws {
        let metadata = ID3Metadata(title: "Test", artist: "Artist")
        try await pipeline.writeID3(to: dummyURL, metadata: metadata)
        // No assertion needed — just verifying it doesn't throw.
    }
}
