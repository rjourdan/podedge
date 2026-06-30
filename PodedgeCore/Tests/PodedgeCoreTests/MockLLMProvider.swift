import Foundation
@testable import PodedgeCore

/// A controllable mock LLM provider for testing Router and AssistantController.
final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    var completeCallCount = 0
    var completeResponse: String
    var shouldThrow = false

    init(completeResponse: String = "I'm a mock assistant") {
        self.completeResponse = completeResponse
    }

    var capabilities: LLMProviderCapabilities {
        LLMProviderCapabilities(
            supportsNativeToolUse: false,
            supportsStreaming: true,
            maxContextTokens: 4096,
            modelID: "mock-model",
            providerID: "mock"
        )
    }

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        completeCallCount += 1
        if shouldThrow { throw PodedgeError.llmFailed(reason: "Mock error") }
        return LLMResponse(text: completeResponse, inputTokens: 10, outputTokens: 5, finishReason: .stop)
    }

    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LLMStreamChunk(text: self.completeResponse, isComplete: true))
            continuation.finish()
        }
    }

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
    }

    func complete(_ prompt: String, systemPrompt: String?, maxTokens: Int, tools: [any ToolDefinition]?) async throws -> LLMResponse {
        try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
    }

    func stream(_ prompt: String, systemPrompt: String?, maxTokens: Int, tools: [any ToolDefinition]?) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta(self.completeResponse))
            continuation.yield(.done(finishReason: .stop))
            continuation.finish()
        }
    }
}

/// A minimal tool caller for testing.
struct MockToolCaller: ToolCaller {
    var capabilityTier: CapabilityTier = .full
}
