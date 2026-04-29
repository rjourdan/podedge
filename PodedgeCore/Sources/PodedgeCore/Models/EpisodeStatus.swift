/// Lifecycle state of an episode from import through publication.
public enum EpisodeStatus: String, Codable, Sendable {
    /// Newly created; not yet processed or scheduled.
    case draft
    /// Audio is being ingested, transcribed, or otherwise processed.
    case processing
    /// Processing complete; ready to be scheduled or published.
    case ready
    /// Queued for automatic publication at a future date.
    case scheduled
    /// Live in the RSS feed and available to listeners.
    case published
    /// Processing or publication failed; see the associated job for details.
    case failed
}
