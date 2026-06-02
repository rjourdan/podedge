import Foundation

/// Posts a blurb to a social platform for an episode.
public struct SocialPostTool: ToolDefinition, Sendable {
    public let name = "social.post"
    public let description = "Posts text to a social platform on behalf of an episode."
    public let scope: ToolScope = .destructive
    public let requiredTier: CapabilityTier = .full
    public let parameterSchema = #"{"episodeID":"UUID","platformID":"String","text":"String"}"#

    private let socialService: SocialPostingService

    public init(socialService: SocialPostingService) {
        self.socialService = socialService
    }

    public func execute(input: Data) async throws -> Data {
        let params = try JSONDecoder().decode(SocialPostInput.self, from: input)
        let result = try await socialService.post(
            platformID: params.platformID,
            text: params.text,
            episodeURL: nil
        )
        let output = SocialPostOutput(postURI: result.postURI, mode: result.mode.rawValue)
        return try JSONEncoder().encode(output)
    }
}
