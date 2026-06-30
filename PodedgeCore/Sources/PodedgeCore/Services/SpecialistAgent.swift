import Foundation

// MARK: - Model Capability Tier

/// Represents the quality tier of an LLM model for agent task suitability.
///
/// This is distinct from ``CapabilityTier`` which gates tool access permissions.
/// `ModelCapabilityTier` indicates whether a model is powerful enough to handle
/// multi-step agent workflows reliably.
public enum ModelCapabilityTier: Int, Codable, Sendable, Comparable {
    /// Large cloud models (GPT-4, Claude Opus) — best quality.
    case t1 = 1
    /// 24B+ models (Mistral Small 24B, Llama 70B, Qwen 72B) — good for multi-step.
    case t2 = 2
    /// Small local models (MLX 4B/8B) — basic structured flows.
    case t3 = 3

    public static func < (lhs: ModelCapabilityTier, rhs: ModelCapabilityTier) -> Bool {
        // Lower raw value means higher capability (t1 > t2 > t3).
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Agent Context

/// Contextual information passed to a specialist agent for a single run.
public struct AgentContext: Sendable {
    /// The currently selected show, if any.
    public var selectedShowID: UUID?
    /// The currently selected episode, if any.
    public var selectedEpisodeID: UUID?
    /// The LLM provider to use for completions.
    public var llmProvider: any LLMProvider
    /// Per-show guide content loaded by AssistantController before calling the agent.
    public var perShowGuide: String?

    public init(
        selectedShowID: UUID? = nil,
        selectedEpisodeID: UUID? = nil,
        llmProvider: any LLMProvider,
        perShowGuide: String? = nil
    ) {
        self.selectedShowID = selectedShowID
        self.selectedEpisodeID = selectedEpisodeID
        self.llmProvider = llmProvider
        self.perShowGuide = perShowGuide
    }
}

// MARK: - Agent Response

/// The result of a single specialist agent run.
public struct AgentResponse: Sendable {
    /// The final text response from the agent.
    public var text: String
    /// Records of tool calls made during the run.
    public var toolCalls: [ToolCallRecord]
    /// Number of LLM loop iterations consumed.
    public var iterationsUsed: Int
    /// Whether the agent hit its iteration cap before completing.
    public var didHitCap: Bool

    public init(
        text: String,
        toolCalls: [ToolCallRecord] = [],
        iterationsUsed: Int,
        didHitCap: Bool = false
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.iterationsUsed = iterationsUsed
        self.didHitCap = didHitCap
    }
}

// MARK: - Specialist Agent Protocol

/// A specialist agent handles a specific user intent within the Assistant.
///
/// Each agent has a narrow tool allowlist, a system prompt, an iteration cap,
/// and a minimum model capability tier. The agent's ``run(utterance:context:toolBroker:)``
/// method drives an LLM loop until the task is complete or the cap is reached.
public protocol SpecialistAgent: Sendable {
    /// Unique identifier for this agent (e.g. "promoter", "publish-assistant").
    var agentID: String { get }
    /// The set of tool names this agent is permitted to invoke.
    var toolAllowlist: Set<String> { get }
    /// Maximum number of LLM loop iterations before the agent must stop.
    var maxIterations: Int { get }
    /// Minimum model quality tier required for reliable execution.
    var minCapabilityTier: ModelCapabilityTier { get }
    /// Name of the bundled resource file containing this agent's system prompt.
    var systemPromptResourceName: String { get }

    /// Runs the agent for a single user utterance.
    ///
    /// - Parameters:
    ///   - utterance: The user's natural-language request.
    ///   - context: Contextual information including selected show/episode and LLM provider.
    ///   - toolBroker: The broker through which permitted tools are invoked.
    /// - Returns: An ``AgentResponse`` containing the result text, tool call records,
    ///   and iteration metadata.
    func run(
        utterance: String,
        context: AgentContext,
        toolBroker: ToolBroker
    ) async throws -> AgentResponse
}
