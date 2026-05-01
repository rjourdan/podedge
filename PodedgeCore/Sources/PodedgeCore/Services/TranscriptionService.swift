import Foundation
import os

/// Orchestrates transcription of audio files through a ``TranscriptionEngine``,
/// providing progress reporting, VTT + plain text output, and persistence hooks.
///
/// `TranscriptionService` is an actor to serialize access to in-flight state
/// while remaining `Sendable`-safe across isolation boundaries.
public actor TranscriptionService {

    // MARK: - Dependencies

    private let engine: any TranscriptionEngine
    private let logger = PodedgeLogger.logger(category: "transcription")

    // MARK: - State

    /// Current transcription progress from 0.0 to 1.0, or `nil` if idle.
    public private(set) var progress: Double?

    // MARK: - Init

    /// Creates a transcription service backed by the given engine.
    ///
    /// - Parameter engine: The transcription engine to delegate to.
    public init(engine: any TranscriptionEngine) {
        self.engine = engine
    }

    // MARK: - Transcription

    /// Transcribes the audio file at `audioURL` and writes VTT + plain text
    /// files alongside it.
    ///
    /// - Parameters:
    ///   - audioURL: Path to the audio file to transcribe.
    ///   - language: BCP 47 language tag hint, or `nil` for auto-detection.
    ///   - outputDirectory: Directory where `.vtt` and `.txt` files are written.
    ///     Created if it does not exist.
    /// - Returns: A ``TranscriptionOutput`` with the result and written file URLs.
    /// - Throws: ``PodedgeError/transcriptionFailed(reason:)`` on failure.
    public func transcribe(
        audioURL: URL,
        language: String? = nil,
        outputDirectory: URL
    ) async throws -> TranscriptionOutput {
        progress = 0.0
        defer { progress = nil }

        logger.info("Starting transcription: \(audioURL.lastPathComponent, privacy: .public)")

        let result: TranscriptionResult
        do {
            result = try await engine.transcribe(audioURL: audioURL, language: language)
        } catch {
            logger.error("Transcription engine failed: \(error.localizedDescription, privacy: .public)")
            throw PodedgeError.transcriptionFailed(reason: error.localizedDescription)
        }

        progress = 0.8

        // Write output files.
        let fm = FileManager.default
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let baseName = audioURL.deletingPathExtension().lastPathComponent
        let vttURL = outputDirectory.appendingPathComponent("\(baseName).vtt")
        let txtURL = outputDirectory.appendingPathComponent("\(baseName).txt")

        do {
            try result.vttContent.write(to: vttURL, atomically: true, encoding: .utf8)
            try result.plainText.write(to: txtURL, atomically: true, encoding: .utf8)
        } catch {
            throw PodedgeError.transcriptionFailed(reason: "Failed to write output: \(error.localizedDescription)")
        }

        progress = 1.0
        logger.info("Transcription complete: \(result.segments.count) segments")

        return TranscriptionOutput(
            result: result,
            vttFileURL: vttURL,
            plainTextFileURL: txtURL
        )
    }
}

// MARK: - Output Type

/// The output of a transcription operation, including file URLs for persisted artifacts.
public struct TranscriptionOutput: Sendable {
    /// The full transcription result with segments, plain text, and VTT.
    public var result: TranscriptionResult
    /// URL of the written WebVTT file.
    public var vttFileURL: URL
    /// URL of the written plain-text file.
    public var plainTextFileURL: URL

    public init(result: TranscriptionResult, vttFileURL: URL, plainTextFileURL: URL) {
        self.result = result
        self.vttFileURL = vttFileURL
        self.plainTextFileURL = plainTextFileURL
    }
}
