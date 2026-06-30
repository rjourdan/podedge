import Foundation

// MARK: - Supporting Types

/// The reason an LLM stopped generating tokens.
public enum LLMFinishReason: String, Codable, Sendable {
    /// The model reached a natural stopping point.
    case stop
    /// The model hit the maximum token limit.
    case length
    /// The model invoked a tool.
    case toolUse
    /// An error occurred during generation.
    case error
}

/// A tool call extracted from an LLM response.
public struct LLMToolCall: Sendable {
    /// Unique identifier for this tool call.
    public var id: String
    /// The name of the tool to invoke.
    public var name: String
    /// JSON-encoded arguments for the tool.
    public var arguments: Data

    public init(id: String, name: String, arguments: Data) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// The response from a non-streaming LLM completion.
public struct LLMResponse: Sendable {
    /// The generated text.
    public var text: String
    /// Number of tokens in the input prompt.
    public var inputTokens: Int
    /// Number of tokens in the generated output.
    public var outputTokens: Int
    /// The reason the model stopped generating.
    public var finishReason: LLMFinishReason
    /// Tool calls extracted from the response, if any.
    public var toolCalls: [LLMToolCall]

    public init(
        text: String,
        inputTokens: Int,
        outputTokens: Int,
        finishReason: LLMFinishReason,
        toolCalls: [LLMToolCall] = []
    ) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.finishReason = finishReason
        self.toolCalls = toolCalls
    }
}

/// A single chunk from a streaming LLM completion.
public struct LLMStreamChunk: Sendable {
    /// The text fragment in this chunk.
    public var text: String
    /// Whether this is the final chunk in the stream.
    public var isComplete: Bool

    public init(text: String, isComplete: Bool) {
        self.text = text
        self.isComplete = isComplete
    }
}

/// Describes the capabilities of an LLM provider.
public struct LLMProviderCapabilities: Sendable {
    /// Whether the provider supports native tool-use (function calling).
    public var supportsNativeToolUse: Bool
    /// Whether the provider supports streaming completions.
    public var supportsStreaming: Bool
    /// Maximum context window in tokens.
    public var maxContextTokens: Int
    /// The model identifier.
    public var modelID: String
    /// The provider identifier (e.g. "mlx", "ollama").
    public var providerID: String

    public init(
        supportsNativeToolUse: Bool,
        supportsStreaming: Bool,
        maxContextTokens: Int,
        modelID: String,
        providerID: String
    ) {
        self.supportsNativeToolUse = supportsNativeToolUse
        self.supportsStreaming = supportsStreaming
        self.maxContextTokens = maxContextTokens
        self.modelID = modelID
        self.providerID = providerID
    }
}

/// An event emitted during streaming completion with tool support.
public enum LLMStreamEvent: Sendable {
    /// A fragment of generated text.
    case textDelta(String)
    /// A tool call detected in the stream.
    case toolCall(id: String, name: String, arguments: Data)
    /// The stream completed.
    case done(finishReason: LLMFinishReason)
}

// MARK: - Protocol

/// Abstraction over large language model providers (e.g. local Llama, OpenAI).
public protocol LLMProvider: Sendable {
    /// The provider's capabilities.
    var capabilities: LLMProviderCapabilities { get }

    /// Generates a completion for the given prompt.
    func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse

    /// Streams a completion for the given prompt, yielding chunks as they arrive.
    func stream(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error>

    /// Generates a schema-constrained JSON completion for the given prompt.
    func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        schema: String
    ) async throws -> LLMResponse

    /// Generates a completion with optional tool definitions.
    func complete(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) async throws -> LLMResponse

    /// Streams a completion with optional tool definitions, emitting structured events.
    func stream(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>
}

// MARK: - Default Implementations

extension LLMProvider {
    /// Default capabilities for providers that haven't declared theirs.
    public var capabilities: LLMProviderCapabilities {
        LLMProviderCapabilities(
            supportsNativeToolUse: false,
            supportsStreaming: true,
            maxContextTokens: 4096,
            modelID: "unknown",
            providerID: "unknown"
        )
    }

    /// Default tool-aware completion delegates to the basic completion.
    public func complete(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) async throws -> LLMResponse {
        try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
    }

    /// Default tool-aware stream maps `LLMStreamChunk` to `LLMStreamEvent`.
    public func stream(
        _ prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        tools: [any ToolDefinition]?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let chunkStream = stream(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in chunkStream {
                        if Task.isCancelled { break }
                        continuation.yield(.textDelta(chunk.text))
                        if chunk.isComplete {
                            continuation.yield(.done(finishReason: .stop))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

// MARK: - Tool Schema Helpers

/// Builds a prompt-emulated tool schema string for providers without native tool support.
func buildToolSchemaPrompt(tools: [any ToolDefinition]) -> String {
    var lines = [
        "<tools>",
        "You have access to the following tools. To use a tool, respond with ONLY a JSON object in this exact format:",
        "{\"tool\": \"tool_name\", \"arguments\": {\"param\": \"value\"}}",
        "",
        "Available tools:"
    ]
    for tool in tools {
        lines.append("- \(tool.name): \(tool.description). Parameters: \(tool.parameterSchema)")
    }
    lines.append("</tools>")
    return lines.joined(separator: "\n")
}

/// Attempts to parse a tool call JSON from LLM text output.
///
/// Looks for `{"tool": "name", "arguments": {...}}` patterns.
/// - Returns: An `LLMToolCall` if a valid pattern is found, nil otherwise.
func parseToolCallFromText(_ text: String) -> LLMToolCall? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Try to find JSON object containing "tool" key
    guard let startIndex = trimmed.firstIndex(of: "{") else { return nil }
    let candidate = String(trimmed[startIndex...])
    guard let data = candidate.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let toolName = json["tool"] as? String,
          let arguments = json["arguments"] else { return nil }
    let argsData: Data
    if let argsDict = arguments as? [String: Any] {
        argsData = (try? JSONSerialization.data(withJSONObject: argsDict)) ?? Data()
    } else {
        argsData = Data()
    }
    return LLMToolCall(id: UUID().uuidString, name: toolName, arguments: argsData)
}
