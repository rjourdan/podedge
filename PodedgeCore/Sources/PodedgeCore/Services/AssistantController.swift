import Foundation
import Observation

/// Controls a single assistant conversation session.
///
/// Orchestrates routing, agent execution, tool calls, and rate-limit enforcement.
/// Each ⌘K invocation creates a fresh session via `reset()`.
@MainActor
@Observable
public final class AssistantController {
    // MARK: - Public State

    public private(set) var messages: [AssistantMessage] = []
    public private(set) var isRunning: Bool = false

    /// Human-readable label for the active LLM provider (e.g. "llama3 · OLLAMA").
    public let providerLabel: String

    // MARK: - Rate Limits

    public var maxToolCallsPerMinute: Int = 60
    public var maxDestructivePerHour: Int = 10

    // MARK: - Private

    private let router: Router
    private let toolBroker: ToolBroker
    private let auditLog: AuditLogService
    private let llmProvider: any LLMProvider
    private let escapeHatch: EscapeHatchResponder

    private var sessionDestructiveCount: Int = 0
    private var toolCallTimestamps: [Date] = []

    // MARK: - Init

    /// Creates a new assistant controller.
    ///
    /// - Parameters:
    ///   - router: Routes utterances to specialist agents.
    ///   - toolBroker: Mediates tool invocations.
    ///   - auditLog: Records tool usage for audit trail.
    ///   - llmProvider: The LLM provider for generating responses.
    ///   - providerLabel: Display label for the active provider.
    public init(
        router: Router,
        toolBroker: ToolBroker,
        auditLog: AuditLogService,
        llmProvider: any LLMProvider,
        providerLabel: String
    ) {
        self.router = router
        self.toolBroker = toolBroker
        self.auditLog = auditLog
        self.llmProvider = llmProvider
        self.providerLabel = providerLabel
        self.escapeHatch = EscapeHatchResponder()
    }

    // MARK: - Public API

    /// Submits a user utterance and generates an assistant response.
    public func submit(_ utterance: String) async {
        guard !isRunning else { return }
        isRunning = true

        let userMsg = AssistantMessage(role: .user, text: utterance)
        messages.append(userMsg)

        let decision = await router.route(utterance: utterance)

        switch decision {
        case .agent(let id):
            await generateResponse(utterance: utterance, agentID: id)
        case .unknown:
            appendAssistantMessage(text: escapeHatch.response(for: .unknownIntent))
        case .clarify(let question):
            appendAssistantMessage(text: question)
        }

        isRunning = false
    }

    /// Resets the conversation, clearing all messages and rate-limit counters.
    public func reset() {
        messages = []
        sessionDestructiveCount = 0
        toolCallTimestamps = []
        isRunning = false
    }

    /// Wraps untrusted content with XML tags to prevent prompt injection.
    public static func wrapUntrusted(_ content: String, source: String) -> String {
        "<untrusted_content source=\"\(source)\">\n\(content)\n</untrusted_content>"
    }

    /// Attempts to invoke a destructive tool, respecting rate limits.
    public func invokeDestructiveTool(
        _ toolName: String,
        input: Data = Data(),
        caller: any ToolCaller
    ) async -> ToolResult {
        guard sessionDestructiveCount < maxDestructivePerHour else {
            return .failure(escapeHatch.response(for: .rateLimitHit(type: "destructive")))
        }
        guard checkMinuteRateLimit() else {
            return .failure(escapeHatch.response(for: .rateLimitHit(type: "per-minute")))
        }
        sessionDestructiveCount += 1
        toolCallTimestamps.append(Date())
        return await toolBroker.invoke(toolNamed: toolName, input: input, caller: caller)
    }

    // MARK: - Private

    private func generateResponse(utterance: String, agentID: String) async {
        let assistantMsg = AssistantMessage(
            role: .assistant,
            text: "",
            providerLabel: providerLabel,
            isStreaming: true
        )
        messages.append(assistantMsg)
        let msgIndex = messages.count - 1

        let systemPrompt = "You are a helpful podcast assistant. The user's request was routed to agent: \(agentID). Help them with their request."

        // Get available tools for the assistant caller
        let tools = await toolBroker.availableTools(for: AssistantCaller())

        do {
            let stream = llmProvider.stream(
                utterance,
                systemPrompt: systemPrompt,
                maxTokens: 2048,
                tools: tools.isEmpty ? nil : tools
            )
            for try await event in stream {
                switch event {
                case .textDelta(let delta):
                    messages[msgIndex].text += delta
                case .toolCall(let id, let name, let arguments):
                    guard checkMinuteRateLimit() else {
                        messages[msgIndex].text += "\n\n" + escapeHatch.response(for: .rateLimitHit(type: "per-minute"))
                        break
                    }
                    toolCallTimestamps.append(Date())
                    let record = ToolCallRecord(id: id, toolName: name, arguments: arguments)
                    messages[msgIndex].toolCalls.append(record)
                    let result = await toolBroker.invoke(toolNamed: name, input: arguments, caller: AssistantCaller())
                    if let lastIdx = messages[msgIndex].toolCalls.indices.last {
                        messages[msgIndex].toolCalls[lastIdx].result = result
                    }
                case .done:
                    messages[msgIndex].isStreaming = false
                }
            }
            messages[msgIndex].isStreaming = false
        } catch {
            messages[msgIndex].text = escapeHatch.response(
                for: .providerUnreachable(providerID: providerLabel)
            )
            messages[msgIndex].isStreaming = false
        }
    }

    private func appendAssistantMessage(text: String) {
        let msg = AssistantMessage(
            role: .assistant,
            text: text,
            providerLabel: providerLabel
        )
        messages.append(msg)
    }

    private func checkMinuteRateLimit() -> Bool {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        toolCallTimestamps = toolCallTimestamps.filter { $0 > oneMinuteAgo }
        return toolCallTimestamps.count < maxToolCallsPerMinute
    }
}


// MARK: - Assistant Caller

/// Tool caller identity used when the assistant invokes tools.
public struct AssistantCaller: ToolCaller, Sendable {
    public var capabilityTier: CapabilityTier = .full
    public init() {}
}
