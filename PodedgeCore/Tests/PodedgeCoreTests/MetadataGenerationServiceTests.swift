import Foundation
import Testing

@testable import PodedgeCore

// MARK: - Mock LLM Provider

/// A controllable mock ``LLMProvider`` that returns scripted JSON responses.
private struct MockLLMProvider: LLMProvider, Sendable {

    /// Map from prompt substring → response text. The first matching key is used.
    var responses: [String: String] = [:]

    /// If set, all calls throw this error.
    var error: (any Error & Sendable)?

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        if let error { throw error }
        let text = responseText(for: prompt)
        return LLMResponse(text: text, inputTokens: 100, outputTokens: 50, finishReason: .stop)
    }

    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            if let error {
                continuation.finish(throwing: error)
                return
            }
            let text = responseText(for: prompt)
            continuation.yield(LLMStreamChunk(text: text, isComplete: true))
            continuation.finish()
        }
    }

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        if let error { throw error }
        let text = responseText(for: prompt)
        return LLMResponse(text: text, inputTokens: 100, outputTokens: 50, finishReason: .stop)
    }

    private func responseText(for prompt: String) -> String {
        for (key, value) in responses where prompt.contains(key) {
            return value
        }
        return "{}"
    }
}

// MARK: - LLMService Tests

@Suite("LLMService")
struct LLMServiceTests {

    @Test("Loads and renders prompt template")
    func loadAndRender() throws {
        let provider = MockLLMProvider()
        let service = LLMService(provider: provider)

        let template = try service.loadPrompt(named: "episode-metadata")
        #expect(template.contains("{{transcript}}"))
        #expect(template.contains("{{show_title}}"))

        let rendered = try service.render(template: template, variables: [
            "transcript": "Hello world",
            "show_title": "My Show",
            "episode_number": "1",
        ])
        #expect(rendered.contains("Hello world"))
        #expect(rendered.contains("My Show"))
        #expect(!rendered.contains("{{transcript}}"))
    }

    @Test("Missing prompt throws PodedgeError")
    func missingPrompt() throws {
        let provider = MockLLMProvider()
        let service = LLMService(provider: provider)

        do {
            _ = try service.loadPrompt(named: "nonexistent-prompt")
            Issue.record("Expected error for missing prompt")
        } catch let error as PodedgeError {
            guard case .llmFailed(let reason) = error else {
                Issue.record("Expected .llmFailed, got \(error)")
                return
            }
            #expect(reason.contains("not found"))
        }
    }

    @Test("Complete calls provider with rendered prompt")
    func completeCallsProvider() async throws {
        var provider = MockLLMProvider()
        provider.responses["Generate the following"] = """
        {"title":"Test","subtitle":"Sub","description":"Desc","keywords":["a"]}
        """
        let service = LLMService(provider: provider)

        let response = try await service.complete(
            promptName: "episode-metadata",
            variables: [
                "transcript": "Some transcript",
                "show_title": "Show",
                "episode_number": "1",
            ]
        )
        #expect(response.text.contains("Test"))
    }

    @Test("Provider error is wrapped as PodedgeError")
    func providerErrorWrapped() async {
        var provider = MockLLMProvider()
        provider.error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "provider broke"])
        let service = LLMService(provider: provider)

        do {
            _ = try await service.complete(
                promptName: "episode-metadata",
                variables: ["transcript": "x", "show_title": "x", "episode_number": "1"]
            )
            Issue.record("Expected error")
        } catch let error as PodedgeError {
            guard case .llmFailed(let reason) = error else {
                Issue.record("Expected .llmFailed")
                return
            }
            #expect(reason.contains("provider broke"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - MetadataGenerationService Tests

@Suite("MetadataGenerationService")
struct MetadataGenerationServiceTests {

    /// Creates a mock provider that returns valid JSON for each prompt type.
    private func makeProvider() -> MockLLMProvider {
        var provider = MockLLMProvider()
        provider.responses["Generate the following fields as JSON"] = """
        {
            "title": "Deep Dive into Swift Concurrency",
            "subtitle": "Actors, tasks, and async/await explained",
            "description": "<p>In this episode we explore Swift Concurrency.</p>",
            "keywords": ["swift", "concurrency", "async", "actors"]
        }
        """
        provider.responses["Generate a JSON array of chapter"] = """
        [
            {"title": "Introduction", "startTime": 0.0, "endTime": 60.0},
            {"title": "Actors Deep Dive", "startTime": 60.0, "endTime": 300.0}
        ]
        """
        provider.responses["Generate a JSON object with"] = """
        {
            "twitter": "🎙️ New episode! Deep dive into Swift Concurrency #swift #podcast",
            "linkedin": "Excited to share our latest episode covering Swift Concurrency patterns.",
            "mastodon": "Just dropped a new episode on Swift Concurrency — actors, tasks, and more!"
        }
        """
        return provider
    }

    @Test("Generates complete metadata from transcript")
    func generateMetadata() async throws {
        let provider = makeProvider()
        let llmService = LLMService(provider: provider)
        let service = MetadataGenerationService(llmService: llmService)

        let metadata = try await service.generate(
            transcript: "Hello, welcome to the show. Today we discuss Swift Concurrency.",
            showTitle: "Swift Talk",
            episodeNumber: "42"
        )

        #expect(metadata.title == "Deep Dive into Swift Concurrency")
        #expect(metadata.subtitle == "Actors, tasks, and async/await explained")
        #expect(metadata.descriptionHTML.contains("Swift Concurrency"))
        #expect(metadata.keywords.contains("swift"))
        #expect(metadata.chapters.count == 2)
        #expect(metadata.chapters[0].title == "Introduction")
        #expect(metadata.chapters[0].startTime == 0.0)
        #expect(metadata.blurbs.twitter.contains("Swift Concurrency"))
        #expect(metadata.blurbs.linkedin.contains("episode"))
    }

    @Test("Throws PodedgeError when LLM returns invalid JSON")
    func invalidJSON() async {
        var provider = MockLLMProvider()
        provider.responses["Generate the following fields as JSON"] = "not valid json"
        provider.responses["Generate a JSON array of chapter"] = "[]"
        provider.responses["Generate a JSON object with"] = """
        {"twitter":"a","linkedin":"b","mastodon":"c"}
        """
        let llmService = LLMService(provider: provider)
        let service = MetadataGenerationService(llmService: llmService)

        do {
            _ = try await service.generate(
                transcript: "test",
                showTitle: "Show",
                episodeNumber: "1"
            )
            Issue.record("Expected error for invalid JSON")
        } catch let error as PodedgeError {
            guard case .llmFailed(let reason) = error else {
                Issue.record("Expected .llmFailed, got \(error)")
                return
            }
            #expect(reason.contains("decode") || reason.contains("JSON"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws PodedgeError when provider fails")
    func providerFailure() async {
        var provider = MockLLMProvider()
        provider.error = PodedgeError.llmFailed(reason: "out of memory")
        let llmService = LLMService(provider: provider)
        let service = MetadataGenerationService(llmService: llmService)

        do {
            _ = try await service.generate(
                transcript: "test",
                showTitle: "Show",
                episodeNumber: "1"
            )
            Issue.record("Expected error")
        } catch let error as PodedgeError {
            guard case .llmFailed(let reason) = error else {
                Issue.record("Expected .llmFailed")
                return
            }
            #expect(reason.contains("out of memory"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("GeneratedMetadata is Equatable")
    func metadataEquatable() {
        let blurbs = GeneratedBlurbs(twitter: "a", linkedin: "b", mastodon: "c")
        let m1 = GeneratedMetadata(
            title: "T", subtitle: "S", descriptionHTML: "D",
            chapters: [], keywords: ["k"], blurbs: blurbs
        )
        let m2 = m1
        #expect(m1 == m2)
    }

    @Test("render throws when unrendered placeholders remain")
    func unrenderedPlaceholders() throws {
        let provider = MockLLMProvider()
        let service = LLMService(provider: provider)

        #expect(throws: PodedgeError.self) {
            _ = try service.render(
                template: "Hello {{name}}, welcome to {{show}}!",
                variables: ["name": "Alice"]
            )
        }
    }

    @Test("decodeOrThrow strips markdown code fences from JSON response")
    func stripCodeFences() async throws {
        var provider = MockLLMProvider()
        provider.responses["Generate the following fields as JSON"] = """
        ```json
        {
            "title": "Fenced Title",
            "subtitle": "Sub",
            "description": "Desc",
            "keywords": ["a"]
        }
        ```
        """
        provider.responses["Generate a JSON array of chapter"] = """
        ```
        [{"title": "Ch1", "startTime": 0.0, "endTime": 60.0}]
        ```
        """
        provider.responses["Generate a JSON object with"] = """
        {"twitter":"t","linkedin":"l","mastodon":"m"}
        """
        let llmService = LLMService(provider: provider)
        let service = MetadataGenerationService(llmService: llmService)

        let metadata = try await service.generate(
            transcript: "test",
            showTitle: "Show",
            episodeNumber: "1"
        )
        #expect(metadata.title == "Fenced Title")
        #expect(metadata.chapters[0].title == "Ch1")
    }

    @Test("GeneratedMetadata is Codable")
    func metadataCodable() throws {
        let blurbs = GeneratedBlurbs(twitter: "a", linkedin: "b", mastodon: "c")
        let original = GeneratedMetadata(
            title: "T", subtitle: "S", descriptionHTML: "D",
            chapters: [GeneratedChapter(title: "Ch", startTime: 0, endTime: 60)],
            keywords: ["k"], blurbs: blurbs
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeneratedMetadata.self, from: data)
        #expect(original == decoded)
    }
}
