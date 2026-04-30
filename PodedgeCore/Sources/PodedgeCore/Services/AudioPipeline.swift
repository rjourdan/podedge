import Foundation

// MARK: - Supporting Types

/// Results from probing an audio file for technical metadata.
public struct AudioProbeResult: Sendable {
    /// Total duration of the audio in seconds.
    public var duration: Double
    /// Bitrate in bits per second.
    public var bitrate: Int
    /// Number of audio channels (e.g. 1 for mono, 2 for stereo).
    public var channels: Int
    /// Sample rate in Hz (e.g. 44100).
    public var sampleRate: Int
    /// Integrated loudness in LUFS, or `nil` if unavailable.
    public var loudnessLUFS: Double?

    public init(
        duration: Double,
        bitrate: Int,
        channels: Int,
        sampleRate: Int,
        loudnessLUFS: Double? = nil
    ) {
        self.duration = duration
        self.bitrate = bitrate
        self.channels = channels
        self.sampleRate = sampleRate
        self.loudnessLUFS = loudnessLUFS
    }
}

/// A single chapter marker within an audio file's ID3 tags.
public struct ID3Chapter: Sendable {
    /// Start time of the chapter in seconds.
    public var startTime: Double
    /// End time of the chapter in seconds.
    public var endTime: Double
    /// Human-readable chapter title.
    public var title: String

    public init(startTime: Double, endTime: Double, title: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
    }
}

/// ID3 tag metadata read from or written to an audio file.
public struct ID3Metadata: Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var coverImageData: Data?
    public var chapters: [ID3Chapter]

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        coverImageData: Data? = nil,
        chapters: [ID3Chapter] = []
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.coverImageData = coverImageData
        self.chapters = chapters
    }
}

// MARK: - Protocol

/// Abstraction over audio file operations: hashing, probing, waveform
/// generation, and ID3 tag reading/writing.
public protocol AudioPipeline: Sendable {
    /// Returns the hex-encoded SHA-256 digest of the file at `url`.
    func sha256(of url: URL) async throws -> String

    /// Probes the audio file at `url` for technical metadata.
    func probe(url: URL) async throws -> AudioProbeResult

    /// Generates a peak-amplitude waveform with `sampleCount` samples.
    func waveform(url: URL, sampleCount: Int) async throws -> [Float]

    /// Reads ID3 tag metadata from the audio file at `url`.
    func readID3(url: URL) async throws -> ID3Metadata

    /// Writes ID3 tag metadata to the audio file at `url`.
    func writeID3(to url: URL, metadata: ID3Metadata) async throws
}

// MARK: - Passthrough Implementation

/// A no-op ``AudioPipeline`` that returns empty or default values.
/// Useful for testing and previews.
public struct PassthroughPipeline: AudioPipeline {
    public init() {}

    public func sha256(of url: URL) async throws -> String {
        String(repeating: "0", count: 64)
    }

    public func probe(url: URL) async throws -> AudioProbeResult {
        AudioProbeResult(duration: 0, bitrate: 0, channels: 0, sampleRate: 0)
    }

    public func waveform(url: URL, sampleCount: Int) async throws -> [Float] {
        Array(repeating: Float(0), count: sampleCount)
    }

    public func readID3(url: URL) async throws -> ID3Metadata {
        ID3Metadata()
    }

    public func writeID3(to url: URL, metadata: ID3Metadata) async throws {
        // No-op
    }
}
