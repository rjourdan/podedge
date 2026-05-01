import Foundation
import os

// MARK: - Supporting Types

/// The result of preparing an episode's audio for publication.
public struct PublishArtifact: Sendable {
    /// Local file URL of the publish-ready audio.
    public var localURL: URL
    /// Hex-encoded SHA-256 digest of the file.
    public var sha256: String
    /// File size in bytes.
    public var byteSize: Int64
    /// Whether the file was rewritten with embedded tags.
    public var isRewritten: Bool

    public init(localURL: URL, sha256: String, byteSize: Int64, isRewritten: Bool) {
        self.localURL = localURL
        self.sha256 = sha256
        self.byteSize = byteSize
        self.isRewritten = isRewritten
    }
}

// MARK: - Builder

/// Prepares an episode's audio file for publication, optionally embedding
/// ID3 tags (cover art, chapters, title/artist/album) into a rewritten copy.
public struct PublishArtifactBuilder: Sendable {

    private let pipeline: any AudioPipeline
    private let tagService: ID3TagService
    private let logger = PodedgeLogger.upload

    /// Creates an artifact builder.
    ///
    /// - Parameters:
    ///   - pipeline: Audio pipeline for SHA-256 hashing.
    ///   - tagService: Service for writing ID3 tags.
    public init(pipeline: any AudioPipeline, tagService: ID3TagService = ID3TagService()) {
        self.pipeline = pipeline
        self.tagService = tagService
    }

    /// Builds a publish artifact for the given episode.
    ///
    /// If neither cover art nor chapters are provided, returns the original
    /// asset URL and hash without copying. Otherwise, copies the original to
    /// a temporary location, embeds ID3 tags, and returns the rewritten file.
    ///
    /// - Parameters:
    ///   - episode: A sendable snapshot of the episode.
    ///   - show: A sendable snapshot of the show (for artist/album tags).
    ///   - originalURL: Local URL of the original audio asset.
    ///   - originalSHA256: SHA-256 of the original file.
    ///   - originalByteSize: Byte size of the original file.
    ///   - coverArtData: Optional cover art image data to embed.
    ///   - chaptersJSON: Optional Podcasting 2.0 chapters JSON string.
    /// - Returns: A ``PublishArtifact`` describing the publish-ready file.
    public func build(
        episode: EpisodeSnapshot,
        show: ShowSnapshot,
        originalURL: URL,
        originalSHA256: String,
        originalByteSize: Int64,
        coverArtData: Data?,
        chaptersJSON: String?
    ) async throws -> PublishArtifact {
        let needsRewrite = coverArtData != nil || chaptersJSON != nil

        guard needsRewrite else {
            logger.info("No rewrite needed for episode \(episode.id)")
            return PublishArtifact(
                localURL: originalURL,
                sha256: originalSHA256,
                byteSize: originalByteSize,
                isRewritten: false
            )
        }

        logger.info("Rewriting audio for episode \(episode.id)")

        // Copy original to temp location.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("podedge-publish", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempURL = tempDir.appendingPathComponent("\(episode.id)-published.mp3")

        // Remove any leftover from a previous attempt.
        try? FileManager.default.removeItem(at: tempURL)
        try FileManager.default.copyItem(at: originalURL, to: tempURL)

        // Build ID3 metadata.
        let metadata = ID3Metadata(
            title: episode.title,
            artist: show.author,
            album: show.title,
            coverImageData: coverArtData
        )

        try tagService.writeTags(to: tempURL, metadata: metadata)

        // Compute hash and size of the rewritten file.
        let sha256 = try await pipeline.sha256(of: tempURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path(percentEncoded: false))
        let byteSize = (attrs[.size] as? Int64) ?? 0

        logger.info("Rewrite complete: \(sha256.prefix(16), privacy: .public)… (\(byteSize) bytes)")

        return PublishArtifact(
            localURL: tempURL,
            sha256: sha256,
            byteSize: byteSize,
            isRewritten: true
        )
    }
}
