import Foundation
import os

#if canImport(MLXAudioSTT)
import MLXAudioSTT
import MLXAudioCore
import MLX
#endif

/// On-device speech-to-text engine backed by MLX Audio on Apple Silicon.
///
/// Actor isolation ensures the MLX model's GPU state is accessed from a
/// single isolation domain.
public actor MLXTranscriptionEngine: TranscriptionEngine {

    // MARK: - Properties

    private let modelID: String
    private let modelsDirectory: URL
    private let logger = PodedgeLogger.logger(category: "transcription")

    #if canImport(MLXAudioSTT)
    private var loadedModel: (any STTGenerationModel)?
    #endif

    // MARK: - Init

    /// Creates a transcription engine targeting the given model.
    ///
    /// - Parameters:
    ///   - modelID: The Hugging Face model identifier (e.g. `"mlx-community/parakeet-tdt-0.6b-v3"`).
    ///   - modelsDirectory: Directory where downloaded models are stored on disk.
    public init(modelID: String, modelsDirectory: URL) {
        self.modelID = modelID
        self.modelsDirectory = modelsDirectory
    }

    // MARK: - TranscriptionEngine

    public func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        #if canImport(MLXAudioSTT)
        let model = try await loadModel()

        // Load audio resampled to 16 kHz as required by STT models.
        let (_, audio) = try loadAudioArray(from: audioURL, sampleRate: 16000)

        // generate() is synchronous and GPU-bound; safe within actor isolation.
        let output = model.generate(audio: audio)

        // STTOutput.segments is [[String: Any]]? with keys "text", "start", "end".
        let segments: [TranscriptionSegment] = (output.segments ?? []).compactMap { dict in
            guard let text = dict["text"] as? String,
                  let start = dict["start"] as? Double,
                  let end = dict["end"] as? Double
            else { return nil }
            return TranscriptionSegment(startTime: start, endTime: end, text: text)
        }

        let plainText = output.text
        let vttContent = buildVTT(from: segments)

        return TranscriptionResult(
            plainText: plainText,
            vttContent: vttContent,
            segments: segments
        )
        #else
        throw PodedgeError.transcriptionFailed(reason: "MLXAudioSTT not available")
        #endif
    }

    public func availableModels() async throws -> [TranscriptionModelInfo] {
        let catalog: [(name: String, sizeBytes: Int64)] = [
            ("mlx-community/parakeet-tdt-0.6b-v3", 600_000_000),
            ("mlx-community/GLM-ASR-Nano-2512-4bit", 1_000_000_000),
            ("mlx-community/Qwen3-ASR-1.7B-bf16", 3_400_000_000),
        ]

        return catalog.map { entry in
            let sanitized = entry.name.replacingOccurrences(of: "/", with: "_")
            let modelDir = modelsDirectory.appendingPathComponent(sanitized, isDirectory: true)
            let isDownloaded = FileManager.default.fileExists(atPath: modelDir.path(percentEncoded: false))
            return TranscriptionModelInfo(
                name: entry.name,
                sizeBytes: entry.sizeBytes,
                isDownloaded: isDownloaded
            )
        }
    }

    public func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws {
        guard !name.contains("..") else {
            throw PodedgeError.preconditionViolated(reason: "Invalid model name: path traversal detected")
        }

        #if canImport(MLXAudioSTT)
        do {
            // fromPretrained downloads to HuggingFace cache automatically.
            // We load the model to trigger the download, then discard it.
            _ = try await ParakeetModel.fromPretrained(name)
            logger.info("Model downloaded: \(name, privacy: .public)")
        } catch {
            throw PodedgeError.transcriptionFailed(
                reason: "Model download failed for '\(name)': \(error.localizedDescription)"
            )
        }
        #else
        throw PodedgeError.transcriptionFailed(reason: "MLXAudioSTT not available")
        #endif
    }

    // MARK: - Private

    #if canImport(MLXAudioSTT)
    private func loadModel() async throws -> any STTGenerationModel {
        if let model = loadedModel { return model }

        let model = try await ParakeetModel.fromPretrained(modelID)
        loadedModel = model
        return model
    }
    #endif

    /// Builds a WebVTT string from transcription segments.
    private func buildVTT(from segments: [TranscriptionSegment]) -> String {
        var vtt = "WEBVTT\n\n"
        for (index, segment) in segments.enumerated() {
            vtt += "\(index + 1)\n"
            vtt += "\(formatTimestamp(segment.startTime)) --> \(formatTimestamp(segment.endTime))\n"
            vtt += "\(segment.text)\n\n"
        }
        return vtt
    }

    /// Formats a time in seconds to VTT timestamp format (HH:MM:SS.mmm).
    private func formatTimestamp(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}
