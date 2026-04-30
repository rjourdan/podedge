import Foundation

// MARK: - Supporting Types

/// The reason an LLM stopped generating tokens.
public enum LLMFinishReason: String, Codable, Sendable {
    /// The model reached a natural stopping point.
    case stop
    /// The model hit the maximum token limit.
    case length
    /// An error occurred during generation.
    case error
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

    public init(
        text: String,
        inputTokens: Int,
        outputTokens: Int,
        finishReason: LLMFinishReason
    ) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.finishReason = finishReason
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

// MARK: - Protocol

/// Abstraction over large language model providers (e.g. local Llama, OpenAI).
public protocol LLMProvider: Sendable {
    /// Generates a completion for the given prompt.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt.
    ///   - systemPrompt: An optional system-level instruction.
    ///   - maxTokens: Maximum number of tokens to generate.
    /// - Returns: The complete response including token counts.
    func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> LLMResponse

    /// Streams a completion for the given prompt, yielding chunks as they arrive.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt.
    ///   - systemPrompt: An optional system-level instruction.
    ///   - maxTokens: Maximum number of tokens to generate.
    /// - Returns: An asynchronous stream of text chunks.
    func stream(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<LLMStreamChunk, Error>

    /// Generates a schema-constrained JSON completion for the given prompt.
    ///
    /// - Parameters:
    ///   - prompt: The user prompt.
    ///   - systemPrompt: An optional system-level instruction.
    ///   - maxTokens: Maximum number of tokens to generate.
    ///   - schema: A JSON Schema string that constrains the output format.
    /// - Returns: The complete response with JSON text conforming to `schema`.
    func complete(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        schema: String
    ) async throws -> LLMResponse
}
