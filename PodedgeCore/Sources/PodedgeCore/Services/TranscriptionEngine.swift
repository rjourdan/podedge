import Foundation

// MARK: - Supporting Types

/// A single timed segment within a transcription.
public struct TranscriptionSegment: Sendable {
    /// Start time of the segment in seconds.
    public var startTime: Double
    /// End time of the segment in seconds.
    public var endTime: Double
    /// Transcribed text for this segment.
    public var text: String

    public init(startTime: Double, endTime: Double, text: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}

/// The output of a transcription operation.
public struct TranscriptionResult: Sendable {
    /// Plain-text transcription without timing information.
    public var plainText: String
    /// WebVTT-formatted transcription with timing cues.
    public var vttContent: String
    /// Individual timed segments that compose the transcription.
    public var segments: [TranscriptionSegment]

    public init(
        plainText: String,
        vttContent: String,
        segments: [TranscriptionSegment]
    ) {
        self.plainText = plainText
        self.vttContent = vttContent
        self.segments = segments
    }
}

/// Metadata about a transcription model available for download or use.
public struct TranscriptionModelInfo: Sendable {
    /// Machine-readable model name (e.g. `"base"`, `"large-v3"`).
    public var name: String
    /// Size of the model in bytes.
    public var sizeBytes: Int64
    /// Whether the model has been downloaded to the local machine.
    public var isDownloaded: Bool

    public init(name: String, sizeBytes: Int64, isDownloaded: Bool) {
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDownloaded = isDownloaded
    }
}

// MARK: - Protocol

/// Abstraction over speech-to-text transcription (e.g. local Whisper).
public protocol TranscriptionEngine: Sendable {
    /// Transcribes the audio file at `audioURL`.
    ///
    /// - Parameters:
    ///   - audioURL: Path to the audio file to transcribe.
    ///   - language: BCP 47 language tag hint, or `nil` for auto-detection.
    /// - Returns: The transcription result with plain text, VTT, and segments.
    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult

    /// Returns metadata for all models known to the engine.
    func availableModels() async throws -> [TranscriptionModelInfo]

    /// Downloads the model with the given name to the local machine.
    ///
    /// - Parameters:
    ///   - name: The model name as returned by ``availableModels()``.
    ///   - progress: Callback invoked with download progress from 0.0 to 1.0.
    func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws
}
