/// iTunes episode type for the `<itunes:episodeType>` element.
public enum EpisodeType: String, Codable, Sendable {
    /// A standard, full-length episode.
    case full
    /// A short promotional or preview episode.
    case trailer
    /// Supplementary content outside the regular schedule.
    case bonus
}
