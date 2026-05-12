import Foundation
import Testing

@testable import PodedgeCore

@Suite("MLXTranscriptionEngine")
struct MLXTranscriptionEngineTests {

    @Test("availableModels returns at least 3 known models")
    func testAvailableModelsReturnsKnownModels() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = MLXTranscriptionEngine(
            modelID: "mlx-community/parakeet-tdt-0.6b-v3",
            modelsDirectory: tempDir
        )

        let models = try await engine.availableModels()
        #expect(models.count >= 3)
        #expect(models.contains { $0.name.contains("parakeet") })
        #expect(models.contains { $0.name.contains("GLM-ASR") })
        #expect(models.contains { $0.name.contains("Qwen3-ASR") })
    }

    @Test("downloadModel rejects names with path traversal characters")
    func testModelNameValidationRejectsPathTraversal() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = MLXTranscriptionEngine(
            modelID: "mlx-community/parakeet-tdt-0.6b-v3",
            modelsDirectory: tempDir
        )

        for badName in ["../etc/passwd", "foo/../bar", ".."] {
            await #expect(throws: PodedgeError.self) {
                try await engine.downloadModel(named: badName, progress: { _ in })
            }
        }
    }

    @Test("TranscriptionService with mock engine produces non-empty result")
    func testTranscribeWithMockEngine() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine)

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let audioURL = outputDir.appendingPathComponent("test.mp3")
        try Data("fake audio".utf8).write(to: audioURL)

        let output = try await service.transcribe(
            audioURL: audioURL,
            outputDirectory: outputDir
        )

        #expect(!output.result.plainText.isEmpty)
        #expect(!output.result.vttContent.isEmpty)
        #expect(output.result.segments.count > 0)
        #expect(output.result.vttContent.contains("WEBVTT"))
    }
}
