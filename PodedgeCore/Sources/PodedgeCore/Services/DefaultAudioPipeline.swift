import CryptoKit
import Foundation

/// Production `AudioPipeline` that composes `MP3Validator`, `AudioProber`,
/// `WaveformGenerator`, and `ID3TagService` with CryptoKit SHA-256.
public struct DefaultAudioPipeline: AudioPipeline, Sendable {

    // Stateless utilities stored to avoid repeated initialization cost.
    private let prober = AudioProber()
    private let id3Service = ID3TagService()

    public init() {}

    public func sha256(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65_536)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func probe(url: URL) async throws -> AudioProbeResult {
        try await prober.probe(url: url)
    }

    public func waveform(url: URL, sampleCount: Int) async throws -> [Float] {
        try await WaveformGenerator.generate(url: url, sampleCount: sampleCount)
    }

    public func readID3(url: URL) async throws -> ID3Metadata {
        try await id3Service.readTags(url: url)
    }

    public func writeID3(to url: URL, metadata: ID3Metadata) async throws {
        try id3Service.writeTags(to: url, metadata: metadata)
    }
}
