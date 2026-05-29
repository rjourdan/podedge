import Foundation
import os
import Testing

@testable import PodedgeCore

// MARK: - Mock Transcription Engine

/// A controllable mock ``TranscriptionEngine`` for deterministic testing.
struct MockTranscriptionEngine: TranscriptionEngine, Sendable {

    var transcribeResult: TranscriptionResult = TranscriptionResult(
        plainText: "Hello world. This is a test transcript.",
        vttContent: """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        Hello world.

        00:00:02.000 --> 00:00:05.000
        This is a test transcript.
        """,
        segments: [
            TranscriptionSegment(startTime: 0, endTime: 2, text: "Hello world."),
            TranscriptionSegment(startTime: 2, endTime: 5, text: "This is a test transcript."),
        ]
    )

    var transcribeError: (any Error & Sendable)?

    var models: [TranscriptionModelInfo] = [
        TranscriptionModelInfo(name: "base", sizeBytes: 150_000_000, isDownloaded: true),
        TranscriptionModelInfo(name: "large-v3", sizeBytes: 3_000_000_000, isDownloaded: false),
    ]

    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        if let error = transcribeError { throw error }
        return transcribeResult
    }

    func availableModels() async throws -> [TranscriptionModelInfo] {
        models
    }

    func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws {
        progress(0.5)
        progress(1.0)
    }
}

// MARK: - TranscriptionService Tests

@Suite("TranscriptionService")
struct TranscriptionServiceTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeTranscriptionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Transcribes audio and writes VTT + plain text files")
    func transcribeWritesFiles() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine)
        let outputDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let audioURL = outputDir.appendingPathComponent("episode.mp3")
        try Data("fake audio".utf8).write(to: audioURL)

        let output = try await service.transcribe(
            audioURL: audioURL,
            outputDirectory: outputDir
        )

        #expect(output.result.segments.count == 2)
        #expect(output.result.plainText.contains("Hello world"))

        // Verify files were written.
        let vttData = try Data(contentsOf: output.vttFileURL)
        let txtData = try Data(contentsOf: output.plainTextFileURL)
        #expect(!vttData.isEmpty)
        #expect(!txtData.isEmpty)

        let vttString = String(data: vttData, encoding: .utf8)!
        #expect(vttString.contains("WEBVTT"))

        let txtString = String(data: txtData, encoding: .utf8)!
        #expect(txtString.contains("Hello world"))
    }

    @Test("Transcription failure wraps error as PodedgeError")
    func transcribeFailure() async throws {
        var engine = MockTranscriptionEngine()
        engine.transcribeError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "engine broke"])
        let service = TranscriptionService(engine: engine)
        let outputDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let audioURL = outputDir.appendingPathComponent("episode.mp3")
        try Data("fake audio".utf8).write(to: audioURL)

        do {
            _ = try await service.transcribe(audioURL: audioURL, outputDirectory: outputDir)
            Issue.record("Expected transcription to throw")
        } catch let error as PodedgeError {
            guard case .transcriptionFailed(let reason) = error else {
                Issue.record("Expected .transcriptionFailed, got \(error)")
                return
            }
            #expect(reason.contains("engine broke"))
        }
    }

    @Test("Progress resets to nil after transcription completes")
    func progressResetsAfterCompletion() async throws {
        let engine = MockTranscriptionEngine()
        let service = TranscriptionService(engine: engine)
        let outputDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let audioURL = outputDir.appendingPathComponent("episode.mp3")
        try Data("fake audio".utf8).write(to: audioURL)

        _ = try await service.transcribe(audioURL: audioURL, outputDirectory: outputDir)

        let progress = await service.progress
        #expect(progress == nil)
    }
}

// MARK: - ModelManager Tests

@Suite("ModelManager")
struct ModelManagerTests {

    @Test("Lists available models from engine")
    func availableModels() async throws {
        let engine = MockTranscriptionEngine()
        let manager = ModelManager(engine: engine)
        let models = try await manager.availableModels()
        #expect(models.count == 2)
        #expect(models[0].name == "base")
    }

    @Test("isModelDownloaded returns false for missing directory")
    func modelNotDownloaded() async throws {
        let engine = MockTranscriptionEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelManager(engine: engine, modelsDirectory: tempDir)
        let downloaded = try await manager.isModelDownloaded(named: "nonexistent")
        #expect(!downloaded)
    }

    @Test("isModelDownloaded returns true for existing directory")
    func modelIsDownloaded() async throws {
        let engine = MockTranscriptionEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeModelTests-\(UUID().uuidString)", isDirectory: true)
        let modelDir = tempDir.appendingPathComponent("base", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelManager(engine: engine, modelsDirectory: tempDir)
        let downloaded = try await manager.isModelDownloaded(named: "base")
        #expect(downloaded)
    }

    @Test("deleteModel removes model directory")
    func deleteModel() async throws {
        let engine = MockTranscriptionEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeModelTests-\(UUID().uuidString)", isDirectory: true)
        let modelDir = tempDir.appendingPathComponent("base", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        // Write a file so the directory isn't empty.
        try Data("model data".utf8).write(to: modelDir.appendingPathComponent("weights.bin"))
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelManager(engine: engine, modelsDirectory: tempDir)
        try await manager.deleteModel(named: "base")

        let exists = FileManager.default.fileExists(atPath: modelDir.path(percentEncoded: false))
        #expect(!exists)
    }

    @Test("totalStorageBytes sums file sizes")
    func totalStorage() async throws {
        let engine = MockTranscriptionEngine()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PodedgeModelTests-\(UUID().uuidString)", isDirectory: true)
        let modelDir = tempDir.appendingPathComponent("base", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        let testData = Data(repeating: 0xAB, count: 1024)
        try testData.write(to: modelDir.appendingPathComponent("weights.bin"))
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = ModelManager(engine: engine, modelsDirectory: tempDir)
        let bytes = try await manager.totalStorageBytes()
        #expect(bytes >= 1024)
    }

    @Test("Rejects model names with path traversal characters")
    func pathTraversalRejected() async {
        let engine = MockTranscriptionEngine()
        let manager = ModelManager(engine: engine)

        for badName in ["../etc/passwd", "foo/bar", "a\\b", ".."] {
            await #expect(throws: PodedgeError.self) {
                try await manager.isModelDownloaded(named: badName)
            }
            await #expect(throws: PodedgeError.self) {
                try await manager.deleteModel(named: badName)
            }
            await #expect(throws: PodedgeError.self) {
                try await manager.downloadModel(named: badName)
            }
        }
    }

    @Test("downloadModel reports progress and clears it on completion")
    func downloadProgress() async throws {
        let engine = MockTranscriptionEngine()
        let manager = ModelManager(engine: engine)

        let collected = OSAllocatedUnfairLock(initialState: [Double]())
        try await manager.downloadModel(named: "base") { fraction in
            collected.withLock { $0.append(fraction) }
        }

        let progressValues = collected.withLock { $0 }
        // (a) onProgress callbacks received values
        #expect(!progressValues.isEmpty)
        // (b) Values are in ascending order
        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i - 1])
        }
        // (c) downloadProgress is nil after completion
        let remaining = await manager.downloadProgress["base"]
        #expect(remaining == nil)
    }
}

// MLXLLMProvider tests are in MLXLLMProviderTests.swift
