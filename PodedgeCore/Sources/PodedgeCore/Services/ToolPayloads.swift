import Foundation

// MARK: - Empty Input

/// Placeholder for tools that require no input parameters.
public struct EmptyInput: Codable, Sendable {
    public init() {}
}

/// Placeholder for tools that produce no meaningful output.
public struct EmptyOutput: Codable, Sendable {
    public init() {}
}

// MARK: - Library Payloads

/// Input for `library.get_show`.
public struct GetShowInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

/// Input for `library.list_episodes`.
public struct ListEpisodesInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

/// Input for `library.get_episode`.
public struct GetEpisodeInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

// MARK: - Feed Payloads

/// Input for `feed.build_preview`.
public struct BuildPreviewInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

/// Output for `feed.build_preview`.
public struct BuildPreviewOutput: Codable, Sendable {
    public var xml: String
    public init(xml: String) { self.xml = xml }
}

/// Input for `feed.validate`.
public struct ValidateFeedInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

/// Output for `feed.validate`.
public struct ValidateFeedOutput: Codable, Sendable {
    public var issues: [String]
    public init(issues: [String]) { self.issues = issues }
}

// MARK: - Analytics Payloads

/// Input for `analytics.query_cached`.
public struct AnalyticsQueryInput: Codable, Sendable {
    public var showID: UUID
    public var since: Date?
    public init(showID: UUID, since: Date? = nil) {
        self.showID = showID
        self.since = since
    }
}

/// Output for `analytics.query_cached`.
public struct AnalyticsQueryOutput: Codable, Sendable {
    public var snapshots: [AnalyticsSnapshotSummary]
    public init(snapshots: [AnalyticsSnapshotSummary]) { self.snapshots = snapshots }
}

/// Lightweight summary of an analytics snapshot.
public struct AnalyticsSnapshotSummary: Codable, Sendable {
    public var id: UUID
    public var capturedAt: Date
    public var windowStart: Date
    public var windowEnd: Date
    public var downloads: Int
    public var uniqueListeners: Int

    public init(id: UUID, capturedAt: Date, windowStart: Date, windowEnd: Date, downloads: Int, uniqueListeners: Int) {
        self.id = id
        self.capturedAt = capturedAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.downloads = downloads
        self.uniqueListeners = uniqueListeners
    }
}

// MARK: - Distribution Payloads

/// Input for `distribution.get_status`.
public struct GetDistributionStatusInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

/// Output for `distribution.get_status`.
public struct DistributionStatusOutput: Codable, Sendable {
    public var records: [DistributionRecordSummary]
    public init(records: [DistributionRecordSummary]) { self.records = records }
}

/// Lightweight summary of a distribution record.
public struct DistributionRecordSummary: Codable, Sendable {
    public var id: UUID
    public var targetID: String
    public var status: String
    public var externalShowID: String?
    public var submittedAt: Date?

    public init(id: UUID, targetID: String, status: String, externalShowID: String?, submittedAt: Date?) {
        self.id = id
        self.targetID = targetID
        self.status = status
        self.externalShowID = externalShowID
        self.submittedAt = submittedAt
    }
}

// MARK: - Jobs Payloads

/// Input for `jobs.list`.
public struct ListJobsInput: Codable, Sendable {
    public var state: String?
    public init(state: String? = nil) { self.state = state }
}

/// Output for `jobs.list`.
public struct ListJobsOutput: Codable, Sendable {
    public var jobs: [JobSummary]
    public init(jobs: [JobSummary]) { self.jobs = jobs }
}

/// Lightweight summary of a job.
public struct JobSummary: Codable, Sendable {
    public var id: UUID
    public var kind: String
    public var targetID: UUID
    public var state: String
    public var attempts: Int
    public var createdAt: Date

    public init(id: UUID, kind: String, targetID: UUID, state: String, attempts: Int, createdAt: Date) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.state = state
        self.attempts = attempts
        self.createdAt = createdAt
    }
}

// MARK: - Episode Payloads

/// Input for `episode.create_draft`.
public struct CreateDraftInput: Codable, Sendable {
    public var showID: UUID
    public var title: String
    public init(showID: UUID, title: String) {
        self.showID = showID
        self.title = title
    }
}

/// Input for `episode.update_metadata`.
public struct UpdateEpisodeMetadataInput: Codable, Sendable {
    public var episodeID: UUID
    public var title: String?
    public var subtitle: String?
    public var summary: String?
    public init(episodeID: UUID, title: String? = nil, subtitle: String? = nil, summary: String? = nil) {
        self.episodeID = episodeID
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
    }
}

/// Input for `episode.transcribe`.
public struct TranscribeInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

/// Input for `episode.publish`.
public struct PublishInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

/// Input for `episode.unpublish`.
public struct UnpublishInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

/// Input for `episode.delete`.
public struct DeleteEpisodeInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

// MARK: - Show Payloads

/// Input for `show.create`.
public struct CreateShowInput: Codable, Sendable {
    public var title: String
    public var author: String
    public var summary: String
    public var language: String
    public var category: String
    public var ownerEmail: String
    public var ownerName: String

    public init(title: String, author: String, summary: String, language: String, category: String, ownerEmail: String, ownerName: String) {
        self.title = title
        self.author = author
        self.summary = summary
        self.language = language
        self.category = category
        self.ownerEmail = ownerEmail
        self.ownerName = ownerName
    }
}

/// Input for `show.update_metadata`.
public struct UpdateShowMetadataInput: Codable, Sendable {
    public var showID: UUID
    public var title: String?
    public var author: String?
    public var summary: String?
    public init(showID: UUID, title: String? = nil, author: String? = nil, summary: String? = nil) {
        self.showID = showID
        self.title = title
        self.author = author
        self.summary = summary
    }
}

/// Input for `show.delete`.
public struct DeleteShowInput: Codable, Sendable {
    public var showID: UUID
    public init(showID: UUID) { self.showID = showID }
}

// MARK: - LLM Payloads

/// Input for `llm.generate_metadata`.
public struct GenerateMetadataInput: Codable, Sendable {
    public var episodeID: UUID
    public init(episodeID: UUID) { self.episodeID = episodeID }
}

/// Input for `llm.generate_blurb`.
public struct GenerateBlurbInput: Codable, Sendable {
    public var episodeID: UUID
    public var platform: String
    public init(episodeID: UUID, platform: String) {
        self.episodeID = episodeID
        self.platform = platform
    }
}

/// Output for `llm.generate_blurb`.
public struct GenerateBlurbOutput: Codable, Sendable {
    public var blurb: String
    public init(blurb: String) { self.blurb = blurb }
}

// MARK: - Host Payloads

/// Input for `host.test_binding`.
public struct TestBindingInput: Codable, Sendable {
    public var bindingID: UUID
    public init(bindingID: UUID) { self.bindingID = bindingID }
}

/// Output for `host.test_binding`.
public struct TestBindingOutput: Codable, Sendable {
    public var reachable: Bool
    public init(reachable: Bool) { self.reachable = reachable }
}

/// Input for `host.remove_binding`.
public struct RemoveBindingInput: Codable, Sendable {
    public var bindingID: UUID
    public init(bindingID: UUID) { self.bindingID = bindingID }
}

// MARK: - Social Payloads

/// Input for `social.post`.
public struct SocialPostInput: Codable, Sendable {
    public var episodeID: UUID
    public var platformID: String
    public var text: String
    public init(episodeID: UUID, platformID: String, text: String) {
        self.episodeID = episodeID
        self.platformID = platformID
        self.text = text
    }
}

/// Output for `social.post`.
public struct SocialPostOutput: Codable, Sendable {
    public var postURI: String
    public var mode: String

    public init(postURI: String, mode: String) {
        self.postURI = postURI
        self.mode = mode
    }
}
