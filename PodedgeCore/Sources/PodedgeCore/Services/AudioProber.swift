import AVFoundation
import Foundation

/// Probes audio files for technical metadata using AVFoundation.
///
/// Uses `AVAsset` and `AVAssetTrack` to extract duration, bitrate,
/// channel count, and sample rate from local audio files.
public struct AudioProber: Sendable {

    /// Creates a new audio prober.
    public init() {}

    /// Probes the audio file at `url` for technical metadata.
    ///
    /// - Parameter url: A local file URL pointing to an audio file.
    /// - Returns: An ``AudioProbeResult`` containing duration, bitrate, channels, and sample rate.
    /// - Throws: An error if the file cannot be read or contains no audio tracks.
    public func probe(url: URL) async throws -> AudioProbeResult {
        let asset = AVURLAsset(url: url)

        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Load audio tracks.
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw PodedgeError.invalidMP3(reason: "No audio tracks found in file")
        }

        let estimatedDataRate = try await track.load(.estimatedDataRate)
        let formatDescriptions = try await track.load(.formatDescriptions)

        var channels = 0
        var sampleRate = 0

        if let formatDescription = formatDescriptions.first {
            let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            if let desc = audioDescription?.pointee {
                channels = Int(desc.mChannelsPerFrame)
                sampleRate = Int(desc.mSampleRate)
            }
        }

        let bitrate = Int(estimatedDataRate)

        return AudioProbeResult(
            duration: durationSeconds.isNaN ? 0 : durationSeconds,
            bitrate: bitrate,
            channels: channels,
            sampleRate: sampleRate,
            loudnessLUFS: nil
        )
    }
}
