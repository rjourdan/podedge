import Foundation
import os
import SwiftData

/// Orchestrates the full audio ingest pipeline: validation, hashing, probing,
/// waveform generation, ID3 reading, and record creation.
///
/// `IngestService` is `@MainActor`-isolated because it writes to ``LibraryStore``
/// and ``JobScheduler``, both of which are `@MainActor`-bound.
@MainActor
public final class IngestService {

    // MARK: - Dependencies

    private let pipeline: any AudioPipeline
    private let store: LibraryStore
    private let scheduler: JobScheduler

    /// Default number of waveform samples to generate during ingest.
    private static let defaultWaveformSampleCount = 1000

    private let logger = PodedgeLogger.ingest

    // MARK: - Init

    /// Creates an ingest service with the given dependencies.
    ///
    /// - Parameters:
    ///   - pipeline: The audio pipeline used for hashing, probing, waveform, and ID3 operations.
    ///   - store: The library store for persisting Asset and Episode records.
    ///   - scheduler: The job scheduler for enqueuing follow-up jobs.
    public init(pipeline: any AudioPipeline, store: LibraryStore, scheduler: JobScheduler) {
        self.pipeline = pipeline
        self.store = store
        self.scheduler = scheduler
    }

    // MARK: - Ingest

    /// Ingests an audio file into the library, creating all necessary records.
    ///
    /// Pipeline steps:
    /// 1. Copy file to the app's managed audio directory.
    /// 2. Validate the MP3 file.
    /// 3. Compute SHA-256 hash.
    /// 4. Probe audio metadata (duration, bitrate, channels, sample rate).
    /// 5. Generate waveform (1000 samples).
    /// 6. Read ID3 tags for initial metadata.
    /// 7. Create an ``Asset`` record (kind: `.audioOriginal`).
    /// 8. Create an ``Episode`` record (status: `.processing` → `.ready`).
    /// 9. Create a waveform ``Asset`` record (kind: `.waveform`).
    /// 10. Enqueue follow-up jobs (transcribe, generateMetadata).
    ///
    /// - Parameters:
    ///   - fileURL: The local file URL of the audio file to ingest.
    ///   - show: The show this episode belongs to.
    /// - Returns: The newly created ``Episode``.
    /// - Throws: ``PodedgeError`` if any step fails.
    /// - SeeAlso: ``MP3Validator``, ``WaveformGenerator``, ``ID3TagService``
    @discardableResult
    public func ingest(fileURL: URL, show: Show) async throws -> Episode {
        let episodeID = UUID()
        logger.info("Starting ingest for episode \(episodeID) from \(fileURL.lastPathComponent, privacy: .public)")

        // Create a placeholder episode so we can mark it failed if anything goes wrong.
        let audioAssetID = UUID()
        let episode = Episode(
            id: episodeID,
            title: fileURL.deletingPathExtension().lastPathComponent,
            summary: "",
            originalAssetID: audioAssetID,
            status: .processing
        )
        store.addEpisode(episode)
        episode.show = show
        try store.save()

        do {
            // Step 1: Copy file to managed directory.
            let managedURL = try copyToManagedDirectory(fileURL: fileURL, episodeID: episodeID)
            logger.info("Copied file to managed directory: \(managedURL.lastPathComponent, privacy: .public)")

            // Step 2: Validate MP3.
            try MP3Validator.validate(url: managedURL)
            logger.info("MP3 validation passed")

            // Step 3: Compute SHA-256 hash.
            let sha256Hash = try await pipeline.sha256(of: managedURL)
            logger.info("SHA-256: \(sha256Hash.prefix(16), privacy: .public)…")

            // Step 4: Probe audio metadata.
            let probeResult = try await pipeline.probe(url: managedURL)
            logger.info("Probe: \(probeResult.duration, privacy: .public)s, \(probeResult.bitrate, privacy: .public)bps")

            // Step 5: Generate waveform.
            let waveformSamples = try await pipeline.waveform(url: managedURL, sampleCount: Self.defaultWaveformSampleCount)

            // Step 6: Read ID3 tags.
            let id3 = try await pipeline.readID3(url: managedURL)
            logger.info("ID3 title: \(id3.title ?? "(none)", privacy: .public)")

            // Step 7: Create audio Asset record.
            let fileSize = try fileByteSize(url: managedURL)
            let audioAsset = Asset(
                id: audioAssetID,
                kind: .audioOriginal,
                localURL: managedURL,
                sha256: sha256Hash,
                byteSize: fileSize,
                contentType: "audio/mpeg",
                durationSeconds: probeResult.duration
            )
            store.addAsset(audioAsset)

            // Step 8: Update episode with metadata from ID3 tags.
            if let id3Title = id3.title, !id3Title.isEmpty {
                episode.title = id3Title
            }
            episode.status = .ready
            episode.updatedAt = Date()

            // Step 9: Save waveform and create waveform Asset record.
            let waveformURL = managedAudioDirectory(for: episodeID)
                .appendingPathComponent("\(episodeID)-waveform.wfm")
            try WaveformGenerator.save(waveform: waveformSamples, to: waveformURL)

            let waveformSize = try fileByteSize(url: waveformURL)
            let waveformSHA256 = try await pipeline.sha256(of: waveformURL)
            let waveformAsset = Asset(
                id: UUID(),
                kind: .waveform,
                localURL: waveformURL,
                sha256: waveformSHA256,
                byteSize: waveformSize,
                contentType: "application/octet-stream"
            )
            store.addAsset(waveformAsset)

            try store.save()

            // Step 10: Enqueue follow-up jobs.
            let transcribeJob = Job(kind: .transcribe, targetID: episodeID)
            try scheduler.enqueue(transcribeJob)

            let metadataJob = Job(kind: .generateMetadata, targetID: episodeID, parentJobID: transcribeJob.id)
            try scheduler.enqueue(metadataJob)

            logger.info("Ingest complete for episode \(episodeID)")
            return episode

        } catch {
            // Clean up the placeholder episode to avoid orphaned records.
            logger.error("Ingest failed for episode \(episodeID): \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.removeItem(at: managedAudioDirectory(for: episodeID))
            store.deleteEpisode(episode)
            try? store.save()
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Returns the managed audio directory for a given episode, creating it if needed.
    private func managedAudioDirectory(for episodeID: UUID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Podedge", isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent(episodeID.uuidString, isDirectory: true)
    }

    /// Copies the source file into the app's managed audio directory.
    private func copyToManagedDirectory(fileURL: URL, episodeID: UUID) throws -> URL {
        let directory = managedAudioDirectory(for: episodeID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destinationURL = directory.appendingPathComponent("\(episodeID).mp3")
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)
        return destinationURL
    }

    /// Returns the byte size of the file at `url`.
    private func fileByteSize(url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes[.size] as? Int64) ?? 0
    }
}
