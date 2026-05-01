import Foundation
import os

/// Orchestrates the full episode publish pipeline: artifact preparation,
/// uploads (audio, transcript, chapters, feed), distribution notification,
/// and state updates.
///
/// `PublishService` is `@MainActor`-isolated because it writes to
/// ``LibraryStore``, which is `@MainActor`-bound.
@MainActor
public final class PublishService {

    // MARK: - Dependencies

    private let store: LibraryStore
    private let hostService: HostService
    private let feedBuilder: FeedBuilder
    private let feedValidator: FeedValidator
    private let feedSerializer: FeedXMLSerializer
    private let distributionService: DistributionService
    private let artifactBuilder: PublishArtifactBuilder
    private let logger = PodedgeLogger.upload

    // MARK: - Init

    /// Creates a publish service with the given dependencies.
    public init(
        store: LibraryStore,
        hostService: HostService,
        feedBuilder: FeedBuilder,
        feedValidator: FeedValidator,
        feedSerializer: FeedXMLSerializer,
        distributionService: DistributionService,
        artifactBuilder: PublishArtifactBuilder
    ) {
        self.store = store
        self.hostService = hostService
        self.feedBuilder = feedBuilder
        self.feedValidator = feedValidator
        self.feedSerializer = feedSerializer
        self.distributionService = distributionService
        self.artifactBuilder = artifactBuilder
    }

    // MARK: - Publish

    /// Publishes an episode through the full pipeline.
    ///
    /// Steps:
    /// 1. Prepare publish artifact (embed ID3 tags if needed).
    /// 2. Upload audio (idempotent via HEAD-before-PUT).
    /// 3. Upload transcript VTT if available.
    /// 4. Upload chapters JSON if available.
    /// 5. Create/update published asset record.
    /// 6. Regenerate, validate, serialize, and upload the RSS feed.
    /// 7. Notify distribution directories.
    /// 8. Update episode status to `.published`.
    ///
    /// - Parameters:
    ///   - show: The show model.
    ///   - episode: The episode model to publish.
    /// - Throws: ``PodedgeError`` if any step fails.
    public func publish(show: Show, episode: Episode) async throws {
        let showSnap = show.snapshot
        guard let binding = try store.hostBinding(id: showSnap.hostBindingID) else {
            throw PodedgeError.notFound(entity: "HostBinding", id: showSnap.hostBindingID.uuidString)
        }
        let host = try await hostService.resolveHost(binding: binding.snapshot)
        try await publish(show: show, episode: episode, host: host)
    }

    /// Publishes an episode using a pre-resolved host. Visible for testing.
    func publish(show: Show, episode: Episode, host: any PodcastHost) async throws {
        let showSnap = show.snapshot
        let episodeSnap = episode.snapshot(resolvingAsset: { [store] id in
            try? store.asset(id: id)
        })

        guard let originalAsset = try store.asset(id: episode.originalAssetID) else {
            throw PodedgeError.notFound(entity: "Asset", id: episode.originalAssetID.uuidString)
        }

        let coverArtData: Data? = try episode.coverArtAssetID
            .flatMap { try store.asset(id: $0) }
            .flatMap { try? Data(contentsOf: $0.localURL) }

        // Pre-resolve all episodes and asset remote paths before async work
        // to avoid re-fetching from the store after suspension points.
        let allEpisodes = try store.episodes(for: show.id)
        let transcriptAsset: Asset? = try episode.transcriptAssetID.flatMap {
            try store.asset(id: $0)
        }

        // Build a map of asset IDs to their remote paths for feed generation.
        var assetRemotePaths: [UUID: String] = [:]
        for ep in allEpisodes where ep.id != episode.id && ep.status == .published {
            if let pubID = ep.publishedAssetID,
               let a = try store.asset(id: pubID), let rp = a.remotePath {
                assetRemotePaths[pubID] = rp
            }
        }
        // Cover art assets.
        for ep in allEpisodes {
            if let coverID = ep.coverArtAssetID ?? show.coverArtAssetID {
                if assetRemotePaths[coverID] == nil,
                   let a = try store.asset(id: coverID), let rp = a.remotePath {
                    assetRemotePaths[coverID] = rp
                }
            }
        }
        if let showCoverID = show.coverArtAssetID {
            if assetRemotePaths[showCoverID] == nil,
               let a = try store.asset(id: showCoverID), let rp = a.remotePath {
                assetRemotePaths[showCoverID] = rp
            }
        }

        // Snapshot all other published episodes before async work.
        var otherPublishedSnapshots: [EpisodeSnapshot] = []
        for ep in allEpisodes where ep.id != episode.id && ep.status == .published {
            otherPublishedSnapshots.append(ep.snapshot(resolvingAsset: { [store] id in
                try? store.asset(id: id)
            }))
        }

        // Step 1: Prepare artifact.
        let artifact = try await artifactBuilder.build(
            episode: episodeSnap, show: showSnap,
            originalURL: originalAsset.localURL,
            originalSHA256: originalAsset.sha256,
            originalByteSize: originalAsset.byteSize,
            coverArtData: coverArtData,
            chaptersJSON: episode.chaptersJSON
        )

        let showSlug = showSnap.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Step 2: Upload audio (idempotent).
        let audioRemotePath = "shows/\(showSlug)/\(episode.id).mp3"
        let audioURL = try await idempotentUpload(
            host: host, localURL: artifact.localURL,
            remotePath: audioRemotePath, contentType: "audio/mpeg",
            sha256: artifact.sha256
        )

        // Step 3: Upload transcript if available.
        var transcriptRemoteURL: URL?
        if let transcriptAsset {
            let path = "shows/\(showSlug)/\(episode.id).vtt"
            transcriptRemoteURL = try await idempotentUpload(
                host: host, localURL: transcriptAsset.localURL,
                remotePath: path, contentType: "text/vtt",
                sha256: transcriptAsset.sha256
            )
        }

        // Step 4: Upload chapters if available.
        if let chaptersJSON = episode.chaptersJSON {
            let path = "shows/\(showSlug)/chapters/\(episodeSnap.guid).json"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(episode.id)-chapters.json")
            try chaptersJSON.data(using: .utf8)?.write(to: tempURL, options: .atomic)
            _ = try await idempotentUpload(
                host: host, localURL: tempURL,
                remotePath: path, contentType: "application/json",
                sha256: nil
            )
        }

        // Step 5: Create/update published asset record before feed generation.
        if let existingID = episode.publishedAssetID,
           let existing = try store.asset(id: existingID) {
            existing.localURL = artifact.localURL
            existing.sha256 = artifact.sha256
            existing.byteSize = artifact.byteSize
            existing.remotePath = audioRemotePath
            existing.remoteURL = audioURL
        } else {
            let publishedAsset = Asset(
                kind: .audioPublished, localURL: artifact.localURL,
                remotePath: audioRemotePath, remoteURL: audioURL,
                sha256: artifact.sha256, byteSize: artifact.byteSize,
                contentType: "audio/mpeg", durationSeconds: originalAsset.durationSeconds
            )
            store.addAsset(publishedAsset)
            episode.publishedAssetID = publishedAsset.id
        }

        // Step 6: Build, validate, serialize, and upload feed.
        // Use pre-resolved remote paths to build the asset URL map.
        var assetURLMap: [UUID: URL] = [:]
        if let pubID = episode.publishedAssetID {
            assetURLMap[pubID] = audioURL
        }
        for (assetID, remotePath) in assetRemotePaths {
            if assetURLMap[assetID] == nil {
                assetURLMap[assetID] = host.publicURL(for: remotePath)
            }
        }

        let resolvedAssetURLs = assetURLMap
        let localFeedBuilder = FeedBuilder(resolveAsset: { resolvedAssetURLs[$0] })

        var publishedSnapshots: [EpisodeSnapshot] = []

        // Build snapshot for the current episode.
        var currentSnap = episodeSnap
        currentSnap.enclosureByteSize = artifact.byteSize
        currentSnap.transcriptURL = transcriptRemoteURL
        currentSnap.status = .published
        currentSnap.pubDate = episode.scheduledFor ?? Date()
        currentSnap.publishedAssetID = episode.publishedAssetID
        publishedSnapshots.append(currentSnap)

        // Add pre-resolved snapshots for other published episodes.
        publishedSnapshots.append(contentsOf: otherPublishedSnapshots)

        let feedURL = host.publicURL(for: showSnap.feedRemotePath)
        let feed = localFeedBuilder.build(show: showSnap, episodes: publishedSnapshots, feedURL: feedURL)

        let issues = feedValidator.validate(feed)
        if !issues.isEmpty {
            throw PodedgeError.feedValidation(reason: issues.joined(separator: "; "))
        }

        let feedData = feedSerializer.serialize(feed)
        let feedTempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("podedge-feed-\(show.id).xml")
        try feedData.write(to: feedTempURL, options: .atomic)
        _ = try await host.put(
            localURL: feedTempURL, remotePath: showSnap.feedRemotePath,
            contentType: "application/rss+xml", progress: { _ in }
        )

        // Step 7: Distribution notify.
        _ = await distributionService.submitToAll(feedURL: feedURL, show: showSnap)

        // Step 8: Update episode state.
        episode.status = .published
        episode.pubDate = episode.scheduledFor ?? Date()
        episode.updatedAt = Date()
        try store.save()

        logger.info("Episode \(episode.id) published successfully")
    }

    // MARK: - Private

    /// Uploads a file only if the remote copy doesn't match the expected SHA-256.
    @discardableResult
    private func idempotentUpload(
        host: any PodcastHost,
        localURL: URL,
        remotePath: String,
        contentType: String,
        sha256: String?
    ) async throws -> URL {
        if let sha256 {
            let headResult = try await host.head(remotePath: remotePath)
            let remoteETag = headResult.eTag?.replacingOccurrences(of: "\"", with: "")
            if headResult.exists, remoteETag == sha256 {
                logger.info("Skipping upload (ETag match): \(remotePath, privacy: .public)")
                return host.publicURL(for: remotePath)
            }
        }
        return try await host.put(
            localURL: localURL, remotePath: remotePath,
            contentType: contentType, progress: { _ in }
        )
    }
}
