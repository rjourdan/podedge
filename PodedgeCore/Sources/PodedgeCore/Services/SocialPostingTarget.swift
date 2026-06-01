import Foundation

/// The mechanism used for posting to a social platform.
public enum SocialPostingMode: String, Sendable, Codable {
    case api
    case copyPaste
}

/// The result of a social post operation.
public struct SocialPostResult: Sendable {
    public var postURI: String
    public var mode: SocialPostingMode

    public init(postURI: String, mode: SocialPostingMode) {
        self.postURI = postURI
        self.mode = mode
    }
}

/// A target platform capable of receiving social posts.
public protocol SocialPostingTarget: Sendable {
    var platformID: String { get }
    var displayName: String { get }
    var mode: SocialPostingMode { get }
    func post(text: String, episodeURL: URL?) async throws -> SocialPostResult
}
