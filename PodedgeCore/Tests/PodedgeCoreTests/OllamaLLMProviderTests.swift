import Testing
import Foundation
@testable import PodedgeCore

@Suite("OllamaLLMProvider")
struct OllamaLLMProviderTests {
    @Test("Tags parsing with zero models")
    func tagsParsingZeroModels() throws {
        let json = #"{"models": []}"#.data(using: .utf8)!
        let result = try OllamaLLMProvider.parseTagsResponse(data: json)
        #expect(result.isEmpty)
    }

    @Test("Tags parsing with multiple models")
    func tagsParsingWithModels() throws {
        let json = """
        {"models": [
            {"name": "llama3.1:8b", "size": 4000000000, "modified_at": "2024-01-01T00:00:00Z"},
            {"name": "mistral:7b", "size": 3500000000, "modified_at": "2024-02-01T00:00:00Z"}
        ]}
        """.data(using: .utf8)!
        let result = try OllamaLLMProvider.parseTagsResponse(data: json)
        #expect(result.count == 2)
        #expect(result[0].name == "llama3.1:8b")
        #expect(result[0].sizeBytes == 4_000_000_000)
        #expect(result[1].name == "mistral:7b")
    }

    @Test("Tags parsing with single model")
    func tagsParsingOneModel() throws {
        let json = #"{"models": [{"name": "phi3:mini", "size": 2000000000, "modified_at": "2024-03-15T10:30:00Z"}]}"#.data(using: .utf8)!
        let result = try OllamaLLMProvider.parseTagsResponse(data: json)
        #expect(result.count == 1)
        #expect(result[0].name == "phi3:mini")
    }

    @Test("Unreachable Ollama throws ollamaUnreachable")
    func unreachableThrows() async {
        // Use a port that nothing listens on
        let provider = OllamaLLMProvider(
            baseURL: URL(string: "http://localhost:19999")!,
            modelID: "any"
        )
        do {
            _ = try await provider.complete(prompt: "hi", systemPrompt: nil, maxTokens: 10)
            Issue.record("Expected ollamaUnreachable error")
        } catch let error as PodedgeError {
            if case .ollamaUnreachable = error {
                // expected
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Invalid JSON in tags response throws")
    func invalidTagsThrows() {
        let garbage = "not json".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try OllamaLLMProvider.parseTagsResponse(data: garbage)
        }
    }
}
