import AVFoundation
import Foundation

/// Generates peak-amplitude waveform data from audio files using AVFoundation.
///
/// Streams PCM samples via `AVAssetReader`, computing peak amplitude per
/// bucket on the fly without loading the entire file into memory.
/// All methods are static — no instance state is needed.
public struct WaveformGenerator: Sendable {

    /// Creates a new waveform generator.
    public init() {}

    /// Generates a peak-amplitude waveform from the audio file at `url`.
    ///
    /// Uses a streaming approach — determines total sample count from
    /// duration × sample rate, computes `samplesPerBucket`, then streams
    /// through the audio maintaining only the current bucket's peak.
    /// Never stores all samples in memory.
    ///
    /// - Parameters:
    ///   - url: A local file URL pointing to an audio file.
    ///   - sampleCount: The number of waveform samples (buckets) to produce.
    /// - Returns: An array of `Float` values in the range 0.0–1.0 representing
    ///   peak amplitude per bucket.
    /// - Throws: An error if the file cannot be read or contains no audio tracks.
    public static func generate(url: URL, sampleCount: Int) async throws -> [Float] {
        guard sampleCount > 0 else { return [] }

        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw PodedgeError.invalidMP3(reason: "No audio tracks found for waveform generation")
        }

        // Determine total sample count from duration × sample rate.
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let formatDescriptions = try await track.load(.formatDescriptions)
        var sampleRate: Double = 44100
        if let formatDescription = formatDescriptions.first {
            let audioDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
            if let desc = audioDescription?.pointee, desc.mSampleRate > 0 {
                sampleRate = desc.mSampleRate
            }
        }
        let totalSamples = Int(durationSeconds * sampleRate)
        let samplesPerBucket = max(totalSamples / sampleCount, 1)

        // Configure output to read linear PCM (Float32, mono, native sample rate).
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
        ]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        guard reader.startReading() else {
            let message = reader.error?.localizedDescription ?? "Unknown error"
            throw PodedgeError.invalidMP3(reason: "Cannot read audio for waveform: \(message)")
        }

        // Stream through audio, maintaining only the current bucket's peak.
        var peaks = [Float]()
        peaks.reserveCapacity(sampleCount)
        var currentBucketPeak: Float = 0
        var samplesInCurrentBucket = 0
        var globalSampleIndex = 0

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            let floatCount = length / MemoryLayout<Float>.size
            var data = Data(count: length)
            data.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: baseAddress)
            }
            data.withUnsafeBytes { rawBuffer in
                guard let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                    return
                }
                let buffer = UnsafeBufferPointer(start: pointer, count: floatCount)
                for sample in buffer {
                    let absolute = abs(sample)
                    if absolute > currentBucketPeak {
                        currentBucketPeak = absolute
                    }
                    samplesInCurrentBucket += 1
                    globalSampleIndex += 1

                    if samplesInCurrentBucket >= samplesPerBucket {
                        peaks.append(currentBucketPeak)
                        currentBucketPeak = 0
                        samplesInCurrentBucket = 0
                        // Stop once we have enough buckets.
                        if peaks.count >= sampleCount { return }
                    }
                }
            }
            if peaks.count >= sampleCount { break }
        }

        // Flush any remaining samples in the last bucket.
        if peaks.count < sampleCount && samplesInCurrentBucket > 0 {
            peaks.append(currentBucketPeak)
        }

        // Pad with zeros if we didn't fill all buckets.
        while peaks.count < sampleCount {
            peaks.append(0)
        }

        guard !peaks.isEmpty else {
            return Array(repeating: Float(0), count: sampleCount)
        }

        // Normalize to 0.0–1.0.
        let globalPeak = peaks.max() ?? 0
        guard globalPeak > 0 else {
            return peaks
        }
        return peaks.map { $0 / globalPeak }
    }

    /// Saves waveform data to a binary `.wfm` file as raw Float32 little-endian bytes.
    ///
    /// - Parameters:
    ///   - waveform: The array of peak amplitude values to save.
    ///   - url: The destination file URL.
    /// - Throws: An error if the file cannot be written.
    public static func save(waveform: [Float], to url: URL) throws {
        let data = waveform.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        try data.write(to: url, options: .atomic)
    }

    /// Loads waveform data from a binary `.wfm` file containing raw Float32 little-endian bytes.
    ///
    /// - Parameter url: The source file URL.
    /// - Returns: An array of `Float` values representing the waveform.
    /// - Throws: An error if the file cannot be read.
    public static func load(from url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        let floatCount = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { rawBuffer in
            guard let pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: Float.self) else {
                return []
            }
            return Array(UnsafeBufferPointer(start: pointer, count: floatCount))
        }
    }
}
