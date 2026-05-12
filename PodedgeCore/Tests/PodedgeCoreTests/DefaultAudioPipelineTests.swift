import CryptoKit
import Foundation
import Testing

@testable import PodedgeCore

@Suite("DefaultAudioPipeline Tests")
struct DefaultAudioPipelineTests {

    private func makeTempFile(bytes: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PipelineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.bin")
        var data = Data(count: bytes)
        for i in 0..<bytes {
            data[i] = UInt8(i % 256)
        }
        try data.write(to: url)
        return url
    }

    @Test("SHA-256 is always 64 lowercase hex chars", arguments: [1, 100, 1024, 65536, 1_048_576])
    func sha256IsAlways64HexChars(byteCount: Int) async throws {
        let url = try makeTempFile(bytes: byteCount)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pipeline = DefaultAudioPipeline()
        let hash = try await pipeline.sha256(of: url)
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
        #expect(hash == hash.lowercased())
    }

    @Test("SHA-256 is deterministic for same file")
    func sha256Deterministic() async throws {
        let url = try makeTempFile(bytes: 2048)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pipeline = DefaultAudioPipeline()
        let hash1 = try await pipeline.sha256(of: url)
        let hash2 = try await pipeline.sha256(of: url)
        #expect(hash1 == hash2)
    }

    @Test("SHA-256 matches CryptoKit reference")
    func sha256MatchesReference() async throws {
        let url = try makeTempFile(bytes: 4096)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pipeline = DefaultAudioPipeline()
        let hash = try await pipeline.sha256(of: url)

        // Reference: compute with CryptoKit directly
        let data = try Data(contentsOf: url)
        let reference = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hash == reference)
    }
}
