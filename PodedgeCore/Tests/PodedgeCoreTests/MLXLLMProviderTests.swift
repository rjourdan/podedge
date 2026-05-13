import Testing
@testable import PodedgeCore

@Suite("MLXLLMProvider")
struct MLXLLMProviderTests {
    @Test("Throws when model not loaded")
    func modelNotLoadedThrows() async {
        let provider = MLXLLMProvider(modelID: "test-model")
        await #expect(throws: PodedgeError.self) {
            try await provider.complete(prompt: "hello", systemPrompt: nil, maxTokens: 10)
        }
    }

    @Test("Model ID is stored correctly")
    func modelIDStored() async {
        let provider = MLXLLMProvider(modelID: "mlx-community/Qwen3-8B-4bit-DWQ-053125")
        let id = await provider.modelID
        #expect(id == "mlx-community/Qwen3-8B-4bit-DWQ-053125")
    }

    @Test("Stream throws when model not loaded")
    func streamThrowsWhenNotLoaded() async {
        let provider = MLXLLMProvider(modelID: "test-model")
        let stream = await provider.stream(prompt: "hello", systemPrompt: nil, maxTokens: 10)
        var threw = false
        do {
            for try await _ in stream {}
        } catch {
            threw = true
            #expect(error is PodedgeError)
        }
        #expect(threw)
    }

    @Test("Schema completion throws when model not loaded")
    func schemaCompletionThrowsWhenNotLoaded() async {
        let provider = MLXLLMProvider(modelID: "test-model")
        await #expect(throws: PodedgeError.self) {
            try await provider.complete(
                prompt: "Generate a title",
                systemPrompt: nil,
                maxTokens: 100,
                schema: #"{"type":"object","properties":{"title":{"type":"string"}}}"#
            )
        }
    }
}
