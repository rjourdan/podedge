import Foundation

// MARK: - Supporting Types

/// A planned upload action in the publish pipeline.
public struct PlannedUpload: Sendable {
    /// Destination remote path on the hosting backend.
    public var remotePath: String
    /// MIME type of the file.
    public var contentType: String
    /// Byte size of the local file.
    public var byteSize: Int64
    /// Whether the remote already has a matching copy (would be skipped).
    public var alreadyUploaded: Bool

    public init(remotePath: String, contentType: String, byteSize: Int64, alreadyUploaded: Bool) {
        self.remotePath = remotePath
        self.contentType = contentType
        self.byteSize = byteSize
        self.alreadyUploaded = alreadyUploaded
    }
}

/// The result of a publish dry run — a plan describing what would happen.
public struct PublishPlan: Sendable {
    /// Uploads that would be performed (audio, transcript, chapters, feed).
    public var uploads: [PlannedUpload]
    /// Feed validation issues, if any. Non-empty means publish would fail.
    public var feedValidationIssues: [String]
    /// Distribution target IDs that would be notified.
    public var distributionTargets: [String]

    public init(
        uploads: [PlannedUpload],
        feedValidationIssues: [String],
        distributionTargets: [String]
    ) {
        self.uploads = uploads
        self.feedValidationIssues = feedValidationIssues
        self.distributionTargets = distributionTargets
    }
}

// MARK: - Dry Run

/// Produces a ``PublishPlan`` describing what a publish would do, without
/// performing any uploads or notifications.
@MainActor
public final class PublishDryRun {

    private let store: LibraryStore
    private let hostService: HostService
    private let feedBuilder: FeedBuilder
    private let feedValidator: FeedValidator
    private let feedSerializer: FeedXMLSerializer
    private let distributionService: DistributionService
    private let artifactBuilder: PublishArtifactBuilder

    /// Creates a dry-run service with the same dependencies as ``PublishService``.
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

    /// Generates a publish plan for the given episode without side effects.
    ///
    /// - Parameters:
    ///   - show: The show model.
    ///   - episode: The episode model to plan for.
    /// - Returns: A ``PublishPlan`` describing uploads, validation issues, and targets.
    public func plan(show: Show, episode: Episode) async throws -> PublishPlan {
        let showSnap = show.snapshot
        guard let binding = try store.hostBinding(id: showSnap.hostBindingID) else {
            throw PodedgeError.notFound(entity: "HostBinding", id: showSnap.hostBindingID.uuidString)
        }
        let host = try await hostService.resolveHost(binding: binding.snapshot)
        return try await plan(show: show, episode: episode, host: host)
    }

    /// Generates a publish plan using a pre-resolved host. Visible for testing.
    func plan(show: Show, episode: Episode, host: any PodcastHost) async throws -> PublishPlan {
        let showSnap = show.snapshot
        let episodeSnap = episode.snapshot(resolvingAsset: { [store] id in
            try? store.asset(id: id)
        })

        // Resolve original asset.
        guard let originalAsset = try store.asset(id: episode.originalAssetID) else {
            throw PodedgeError.notFound(entity: "Asset", id: episode.originalAssetID.uuidString)
        }

        // Load optional cover art data.
        let coverArtData: Data? = try episode.coverArtAssetID
            .flatMap { try store.asset(id: $0) }
            .flatMap { try? Data(contentsOf: $0.localURL) }

        // Prepare artifact to determine size and rewrite status.
        let artifact = try await artifactBuilder.build(
            episode: episodeSnap,
            show: showSnap,
            originalURL: originalAsset.localURL,
            originalSHA256: originalAsset.sha256,
            originalByteSize: originalAsset.byteSize,
            coverArtData: coverArtData,
            chaptersJSON: episode.chaptersJSON
        )

        let showSlug = showSnap.title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        var uploads: [PlannedUpload] = []

        // Audio upload.
        let audioPath = "shows/\(showSlug)/\(episode.id).mp3"
        let audioHead = try await host.head(remotePath: audioPath)
        let audioETag = audioHead.eTag?.replacingOccurrences(of: "\"", with: "")
        uploads.append(PlannedUpload(
            remotePath: audioPath,
            contentType: "audio/mpeg",
            byteSize: artifact.byteSize,
            alreadyUploaded: audioHead.exists && audioETag == artifact.sha256
        ))

        // Transcript upload.
        if let transcriptAssetID = episode.transcriptAssetID,
           let transcriptAsset = try store.asset(id: transcriptAssetID) {
            let transcriptPath = "shows/\(showSlug)/\(episode.id).vtt"
            let transcriptHead = try await host.head(remotePath: transcriptPath)
            let transcriptETag = transcriptHead.eTag?.replacingOccurrences(of: "\"", with: "")
            uploads.append(PlannedUpload(
                remotePath: transcriptPath,
                contentType: "text/vtt",
                byteSize: transcriptAsset.byteSize,
                alreadyUploaded: transcriptHead.exists && transcriptETag == transcriptAsset.sha256
            ))
        }

        // Chapters upload.
        if let chaptersJSON = episode.chaptersJSON,
           let chaptersData = chaptersJSON.data(using: .utf8) {
            let chaptersPath = "shows/\(showSlug)/chapters/\(episodeSnap.guid).json"
            let chaptersHead = try await host.head(remotePath: chaptersPath)
            uploads.append(PlannedUpload(
                remotePath: chaptersPath,
                contentType: "application/json",
                byteSize: Int64(chaptersData.count),
                alreadyUploaded: chaptersHead.exists
            ))
        }

        // Build feed to validate.
        let allEpisodes = try store.episodes(for: show.id)
        var publishedSnapshots: [EpisodeSnapshot] = []

        // Pre-build asset URL map for the feed builder.
        var assetURLMap: [UUID: URL] = [:]
        for ep in allEpisodes {
            if ep.id == episode.id {
                // Use the expected audio URL for this episode.
                // Map both publishedAssetID and originalAssetID so the
                // feed builder can resolve whichever the snapshot uses.
                let audioURL = host.publicURL(for: audioPath)
                if let pubID = ep.publishedAssetID {
                    assetURLMap[pubID] = audioURL
                }
                assetURLMap[ep.originalAssetID] = audioURL
            } else if ep.status == .published, let pubID = ep.publishedAssetID {
                if let a = try store.asset(id: pubID), let rp = a.remotePath {
                    assetURLMap[pubID] = host.publicURL(for: rp)
                }
            }
            // Cover art assets.
            if let coverID = ep.coverArtAssetID ?? show.coverArtAssetID {
                if assetURLMap[coverID] == nil, let a = try store.asset(id: coverID), let rp = a.remotePath {
                    assetURLMap[coverID] = host.publicURL(for: rp)
                }
            }
        }
        if let showCoverID = show.coverArtAssetID {
            if let a = try store.asset(id: showCoverID), let rp = a.remotePath {
                assetURLMap[showCoverID] = host.publicURL(for: rp)
            }
        }

        let resolvedURLs = assetURLMap
        let localFeedBuilder = FeedBuilder(resolveAsset: { id in resolvedURLs[id] })

        for ep in allEpisodes {
            if ep.id == episode.id {
                var snap = episodeSnap
                snap.enclosureByteSize = artifact.byteSize
                snap.status = .published
                snap.pubDate = episode.scheduledFor ?? Date()
                // Ensure the snapshot has a publishedAssetID for the resolver.
                if snap.publishedAssetID == nil {
                    snap.publishedAssetID = ep.publishedAssetID ?? ep.originalAssetID
                }
                publishedSnapshots.append(snap)
            } else if ep.status == .published {
                publishedSnapshots.append(ep.snapshot(resolvingAsset: { [store] id in
                    try? store.asset(id: id)
                }))
            }
        }

        let feedURL = host.publicURL(for: showSnap.feedRemotePath)
        let feed = localFeedBuilder.build(show: showSnap, episodes: publishedSnapshots, feedURL: feedURL)
        let issues = feedValidator.validate(feed)

        // Feed upload (always needed).
        let feedData = feedSerializer.serialize(feed)
        uploads.append(PlannedUpload(
            remotePath: showSnap.feedRemotePath,
            contentType: "application/rss+xml",
            byteSize: Int64(feedData.count),
            alreadyUploaded: false
        ))

        // Distribution targets.
        let targetIDs = await distributionService.registeredTargetIDs

        return PublishPlan(
            uploads: uploads,
            feedValidationIssues: issues,
            distributionTargets: targetIDs
        )
    }
}
