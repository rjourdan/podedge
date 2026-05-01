import Foundation

/// A ``PromotionRenderer`` that generates social media blurbs using an LLM.
///
/// Each instance targets a specific platform with its character limit.
/// The renderer calls ``LLMService/complete(promptName:variables:systemPrompt:maxTokens:schema:)``
/// with the `social-blurbs` prompt template.
public struct SocialBlurbRenderer: PromotionRenderer, Sendable {

    /// The target platform identifier.
    public let platform: String

    /// Maximum character count for the platform, or `nil` if unlimited.
    public let maxLength: Int?

    private let llmService: LLMService

    /// Creates a social blurb renderer for the given platform.
    ///
    /// - Parameters:
    ///   - platform: Platform identifier (e.g. `"x"`, `"bluesky"`).
    ///   - maxLength: Character limit for the platform.
    ///   - llmService: The LLM service for generating blurbs.
    public init(platform: String, maxLength: Int?, llmService: LLMService) {
        self.platform = platform
        self.maxLength = maxLength
        self.llmService = llmService
    }

    /// Renders a promotional blurb for the given episode.
    ///
    /// - Parameters:
    ///   - episode: A sendable snapshot of the episode to promote.
    ///   - show: A sendable snapshot of the show.
    ///   - transcript: An optional transcript to inform the copy.
    /// - Returns: The rendered promotional output.
    public func render(
        episode: EpisodeSnapshot,
        show: ShowSnapshot,
        transcript: String?
    ) async throws -> PromotionOutput {
        let variables: [String: String] = [
            "show_title": show.title,
            "episode_number": episode.number.map(String.init) ?? "",
            "transcript": transcript ?? episode.summary,
        ]

        let response = try await llmService.complete(
            promptName: "social-blurbs",
            variables: variables,
            maxTokens: 512
        )

        var text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to platform limit if needed.
        if let maxLength, text.count > maxLength {
            text = String(text.prefix(maxLength))
        }

        // Extract hashtags (words starting with #).
        let hashtags = text.components(separatedBy: .whitespaces)
            .filter { $0.hasPrefix("#") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }

        return PromotionOutput(
            text: text,
            hashtags: hashtags,
            characterCount: text.count
        )
    }

    // MARK: - Factory Methods

    /// Creates a renderer for X (formerly Twitter) with a 280-character limit.
    public static func x(llmService: LLMService) -> SocialBlurbRenderer {
        SocialBlurbRenderer(platform: "x", maxLength: 280, llmService: llmService)
    }

    /// Creates a renderer for Bluesky with a 300-character limit.
    public static func bluesky(llmService: LLMService) -> SocialBlurbRenderer {
        SocialBlurbRenderer(platform: "bluesky", maxLength: 300, llmService: llmService)
    }

    /// Creates a renderer for Mastodon with a 500-character limit.
    public static func mastodon(llmService: LLMService) -> SocialBlurbRenderer {
        SocialBlurbRenderer(platform: "mastodon", maxLength: 500, llmService: llmService)
    }

    /// Creates a renderer for LinkedIn with a 3000-character limit.
    public static func linkedIn(llmService: LLMService) -> SocialBlurbRenderer {
        SocialBlurbRenderer(platform: "linkedin", maxLength: 3000, llmService: llmService)
    }

    /// Creates a renderer for Threads with a 500-character limit.
    public static func threads(llmService: LLMService) -> SocialBlurbRenderer {
        SocialBlurbRenderer(platform: "threads", maxLength: 500, llmService: llmService)
    }
}
