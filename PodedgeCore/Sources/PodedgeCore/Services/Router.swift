import Foundation

/// Decision from the router about which agent should handle an utterance.
public enum RouterDecision: Sendable {
    case agent(id: String)
    case unknown
    case clarify(question: String)
}

/// Routes user utterances to the appropriate specialist agent.
///
/// Checks keyword rules first (O(1)), then falls back to an LLM classifier
/// call if no keyword matches.
public struct Router: Sendable {
    private let llmProvider: any LLMProvider

    public init(llmProvider: any LLMProvider) {
        self.llmProvider = llmProvider
    }

    /// Routes an utterance to an agent.
    ///
    /// Keyword rules:
    /// - "/promote" → PromoterAgent
    /// - "/publish" → PublishAssistantAgent
    ///
    /// Falls back to LLM classifier if no keyword match.
    public func route(utterance: String) async -> RouterDecision {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if trimmed.hasPrefix("/promote") {
            return .agent(id: "promoter")
        }
        if trimmed.hasPrefix("/publish") {
            return .agent(id: "publish-assistant")
        }

        return await classifyWithLLM(utterance: utterance)
    }

    private func classifyWithLLM(utterance: String) async -> RouterDecision {
        let systemPrompt = """
        You are a routing classifier. Given a user utterance, respond with ONLY one of these exact strings:
        - "promoter" if the user wants to create social media posts, blurbs, or promotional content
        - "publish-assistant" if the user wants to publish, schedule, unpublish, or manage episode publishing
        - "unknown" if you cannot determine the intent

        Respond with ONLY the agent ID string, nothing else.
        """

        do {
            let response = try await llmProvider.complete(
                prompt: utterance,
                systemPrompt: systemPrompt,
                maxTokens: 20
            )
            let result = response.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch result {
            case "promoter":
                return .agent(id: "promoter")
            case "publish-assistant":
                return .agent(id: "publish-assistant")
            default:
                return .unknown
            }
        } catch {
            return .unknown
        }
    }
}
