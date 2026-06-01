import Foundation

/// A social target that defers to the UI layer for clipboard operations.
public struct CopyPasteTarget: SocialPostingTarget {
    public let platformID: String
    public let displayName: String
    public let mode: SocialPostingMode = .copyPaste

    public init(platformID: String, displayName: String) {
        self.platformID = platformID
        self.displayName = displayName
    }

    /// Returns immediately; the UI layer handles the actual clipboard write.
    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult {
        SocialPostResult(postURI: "", mode: .copyPaste)
    }
}
