/// The kind of work a job performs.
public enum JobKind: String, Codable, Sendable, CaseIterable {
    /// Import and validate an audio file into the library.
    case ingest
    /// Generate a text transcript from the episode audio.
    case transcribe
    /// Auto-generate episode metadata (title, description, chapters).
    case generateMetadata
    /// Upload processed assets to the hosting backend.
    case upload
    /// Regenerate and upload the RSS feed.
    case publish
    /// Poll the OP3 analytics API for updated statistics.
    case op3Poll
}
