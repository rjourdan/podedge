import CryptoKit
import Foundation
import SwiftData

/// Bridges the job scheduler to the transcription service, executing
/// `.transcribe` jobs by reading the episode's audio and writing a
/// transcript asset.
public struct TranscribeJobHandler: JobHandler, Sendable {

    public let handledKind: JobKind = .transcribe

    private let transcriptionService: TranscriptionService

    /// Creates a handler that delegates transcription to the given service.
    ///
    /// - Parameter transcriptionService: The service used to run transcription.
    public init(transcriptionService: TranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    public func execute(jobID: UUID, container: ModelContainer) async throws {
        let context = ModelContext(container)

        // Fetch job.
        var jobDescriptor = FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        jobDescriptor.fetchLimit = 1
        guard let job = try context.fetch(jobDescriptor).first else {
            throw PodedgeError.notFound(entity: "Job", id: jobID.uuidString)
        }

        // Fetch episode.
        let targetID = job.targetID
        var episodeDescriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == targetID })
        episodeDescriptor.fetchLimit = 1
        guard let episode = try context.fetch(episodeDescriptor).first else {
            throw PodedgeError.notFound(entity: "Episode", id: targetID.uuidString)
        }

        // Fetch audio asset.
        let audioAssetID = episode.originalAssetID
        var assetDescriptor = FetchDescriptor<Asset>(predicate: #Predicate { $0.id == audioAssetID })
        assetDescriptor.fetchLimit = 1
        guard let audioAsset = try context.fetch(assetDescriptor).first else {
            throw PodedgeError.notFound(entity: "Asset", id: audioAssetID.uuidString)
        }

        guard FileManager.default.fileExists(atPath: audioAsset.localURL.path) else {
            throw PodedgeError.notFound(entity: "AudioFile", id: audioAsset.localURL.lastPathComponent)
        }

        // Determine output directory.
        let outputDirectory = outputDirectory(for: episode.id)

        // Run transcription.
        let output: TranscriptionOutput
        do {
            output = try await transcriptionService.transcribe(
                audioURL: audioAsset.localURL,
                language: nil,
                outputDirectory: outputDirectory
            )
        } catch {
            episode.status = .failed
            episode.updatedAt = Date()
            try context.save()
            throw error
        }

        // Compute SHA-256 of the VTT file.
        let sha256 = try sha256Hex(of: output.vttFileURL)
        let byteSize = try fileByteSize(of: output.vttFileURL)

        // Create transcript asset.
        let transcriptAsset = Asset(
            kind: .transcript,
            localURL: output.vttFileURL,
            sha256: sha256,
            byteSize: byteSize,
            contentType: "text/vtt"
        )
        context.insert(transcriptAsset)

        // Update episode.
        episode.transcriptAssetID = transcriptAsset.id
        if episode.status != .published {
            episode.status = .ready
        }
        episode.updatedAt = Date()

        try context.save()
    }

    // MARK: - Private Helpers

    private func outputDirectory(for episodeID: UUID) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Podedge", isDirectory: true)
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent(episodeID.uuidString, isDirectory: true)
    }

    private func sha256Hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65_536)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func fileByteSize(of url: URL) throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attrs[.size] as? Int64) ?? 0
    }
}
