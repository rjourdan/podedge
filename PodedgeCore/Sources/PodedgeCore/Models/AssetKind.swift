/// The kind of file an asset represents.
public enum AssetKind: String, Codable, Sendable {
    /// Original audio file as imported by the user.
    case audioOriginal
    /// Processed audio file ready for publication.
    case audioPublished
    /// Cover art image for a show or episode.
    case coverArt
    /// Text transcript of an episode.
    case transcript
    /// Waveform visualization data for the audio editor.
    case waveform
}
