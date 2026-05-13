import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Mock LLM Provider

/// A mock LLM provider that returns valid JSON for metadata generation prompts.
private struct MockLLMProvider: LLMProvider {

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        try await complete(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens, schema: "")
    }

    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        let text: String
        if schema.contains("subtitle") || prompt.contains("episode-metadata") || prompt.contains("title") {
            text = """
            {"title":"Test Title","subtitle":"Test Subtitle","description":"<p>Test description</p>","keywords":["test","podcast","episode"]}
            """
        } else if schema.contains("startTime") || prompt.contains("chapter") {
            text = """
            [{"title":"Intro","startTime":0,"endTime":60},{"title":"Main Content","startTime":60,"endTime":300}]
            """
        } else {
            text = """
            {"twitter":"Check out this episode!","linkedin":"New episode available.","mastodon":"Listen to our latest!"}
            """
        }
        return LLMResponse(text: text, inputTokens: 100, outputTokens: 50, finishReason: .stop)
    }
}

// MARK: - Tests

@Suite("GenerateMetadataJobHandler", .serialized, .tags(.swiftData))
@MainActor
struct GenerateMetadataJobHandlerTests {

    private static let db = "generateMetadataJobHandler"

    private func makeContainer() throws -> ModelContainer {
        let container = TestDatabase.container(for: Self.db)
        try TestDatabase.reset(container)
        // Also clean up EpisodeSuggestions since TestDatabase.reset doesn't cover it.
        let context = container.mainContext
        for obj in try context.fetch(FetchDescriptor<EpisodeSuggestions>()) {
            context.delete(obj)
        }
        try context.save()
        return container
    }

    /// Creates an episode with a transcript asset on disk and a pending generateMetadata job.
    private func setupEpisodeWithTranscript(
        container: ModelContainer
    ) throws -> (episode: Episode, job: Job, tempDir: URL) {
        let context = container.mainContext

        // Create a temp directory with transcript files.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let vttURL = dir.appendingPathComponent("episode.vtt")
        let txtURL = dir.appendingPathComponent("episode.txt")
        try Data("WEBVTT\n\n1\n00:00:00.000 --> 00:01:00.000\nHello world".utf8).write(to: vttURL)
        try Data("Hello world. This is a test transcript for the podcast episode.".utf8).write(to: txtURL)

        // Create transcript asset pointing to VTT file.
        let transcriptAsset = Asset(
            kind: .transcript,
            localURL: vttURL,
            sha256: String(repeating: "b", count: 64),
            byteSize: 100,
            contentType: "text/vtt"
        )
        context.insert(transcriptAsset)

        // Create show.
        let show = Show(
            title: "Test Podcast",
            author: "Test Author",
            summary: "A test podcast.",
            category: "Technology",
            ownerEmail: "test@example.com",
            ownerName: "Test Author",
            hostBindingID: UUID(),
            feedRemotePath: "shows/test/feed.xml"
        )
        context.insert(show)

        // Create episode with transcriptAssetID.
        let episode = Episode(
            title: "Test Episode",
            originalAssetID: UUID(),
            status: .ready
        )
        episode.transcriptAssetID = transcriptAsset.id
        episode.show = show
        episode.number = 1
        context.insert(episode)

        // Create job targeting the episode.
        let job = Job(kind: .generateMetadata, targetID: episode.id)
        context.insert(job)

        try context.save()
        return (episode, job, dir)
    }

    /// Builds a `GenerateMetadataJobHandler` backed by the mock LLM provider.
    private func makeHandler() -> GenerateMetadataJobHandler {
        let provider = MockLLMProvider()
        let llmService = LLMService(provider: provider)
        let metadataService = MetadataGenerationService(llmService: llmService)
        return GenerateMetadataJobHandler(metadataService: metadataService)
    }

    // MARK: - Task 2.2: Property test — at most one EpisodeSuggestions per episode

    @Test("At most one EpisodeSuggestions per episode after N runs", arguments: 1...5)
    func atMostOneSuggestionsPerEpisode(runCount: Int) async throws {
        let container = try makeContainer()
        let (episode, job, tempDir) = try setupEpisodeWithTranscript(container: container)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let handler = makeHandler()

        // Run the handler `runCount` times for the same episode.
        for _ in 0..<runCount {
            try await handler.execute(jobID: job.id, container: container)
        }

        // Assert: only 1 EpisodeSuggestions record exists for that episode.
        let context = ModelContext(container)
        let episodeID = episode.id
        let descriptor = FetchDescriptor<EpisodeSuggestions>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        let suggestions = try context.fetch(descriptor)
        #expect(suggestions.count == 1, "Expected exactly 1 EpisodeSuggestions after \(runCount) runs, got \(suggestions.count)")
    }

    // MARK: - Task 2.3: Property test — chapter times are ordered

    @Test("Chapter startTime < endTime for all chapters", arguments: [1, 5, 20, 50])
    func chapterTimesAreOrdered(chapterCount: Int) throws {
        // Create chapters with sequential, non-overlapping times.
        var chapters: [GeneratedChapter] = []
        for i in 0..<chapterCount {
            let start = Double(i * 60)
            let end = Double((i + 1) * 60)
            chapters.append(GeneratedChapter(title: "Chapter \(i + 1)", startTime: start, endTime: end))
        }

        // Build a GeneratedMetadata and store in EpisodeSuggestions.
        let metadata = GeneratedMetadata(
            title: "Test",
            subtitle: "Sub",
            descriptionHTML: "<p>Desc</p>",
            chapters: chapters,
            keywords: ["test"],
            blurbs: GeneratedBlurbs(twitter: "tw", linkedin: "li", mastodon: "ma")
        )

        let suggestions = EpisodeSuggestions(episodeID: UUID(), metadata: metadata)

        // Verify startTime < endTime for each decoded chapter.
        let decoded = suggestions.chapters
        #expect(decoded.count == chapterCount)
        for chapter in decoded {
            #expect(
                chapter.startTime < chapter.endTime,
                "Chapter '\(chapter.title)' has startTime \(chapter.startTime) >= endTime \(chapter.endTime)"
            )
        }
    }

    // MARK: - Task 2.4: Unit tests

    @Test("Handler creates EpisodeSuggestions record with correct data")
    func testHandlerCreatesSuggestionsRecord() async throws {
        let container = try makeContainer()
        let (episode, job, tempDir) = try setupEpisodeWithTranscript(container: container)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let handler = makeHandler()
        try await handler.execute(jobID: job.id, container: container)

        // Re-fetch from a fresh context to verify persistence.
        let context = ModelContext(container)
        let episodeID = episode.id
        let descriptor = FetchDescriptor<EpisodeSuggestions>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        let results = try context.fetch(descriptor)
        let suggestions = try #require(results.first)

        #expect(suggestions.suggestedTitle == "Test Title")
        #expect(suggestions.suggestedSubtitle == "Test Subtitle")
        #expect(suggestions.suggestedDescriptionHTML == "<p>Test description</p>")
        #expect(suggestions.keywords.contains("test"))
        #expect(suggestions.keywords.contains("podcast"))
        #expect(suggestions.blurbTwitter == "Check out this episode!")
        #expect(suggestions.blurbLinkedIn == "New episode available.")
        #expect(suggestions.blurbMastodon == "Listen to our latest!")
        #expect(suggestions.chapters.count == 2)
        #expect(suggestions.chapters.first?.title == "Intro")
    }

    @Test("Handler replaces previous suggestions — only one record exists with latest data")
    func testHandlerReplacesPreviousSuggestions() async throws {
        let container = try makeContainer()
        let (episode, job, tempDir) = try setupEpisodeWithTranscript(container: container)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let handler = makeHandler()

        // Run twice.
        try await handler.execute(jobID: job.id, container: container)
        try await handler.execute(jobID: job.id, container: container)

        // Only one record should exist.
        let context = ModelContext(container)
        let episodeID = episode.id
        let descriptor = FetchDescriptor<EpisodeSuggestions>(
            predicate: #Predicate { $0.episodeID == episodeID }
        )
        let results = try context.fetch(descriptor)
        #expect(results.count == 1, "Expected 1 EpisodeSuggestions after two runs, got \(results.count)")

        // Verify it has the expected data (from the latest run).
        let suggestions = try #require(results.first)
        #expect(suggestions.suggestedTitle == "Test Title")
    }

    @Test("Handler fails without transcript — throws PodedgeError")
    func testHandlerFailsWithoutTranscript() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create show.
        let show = Show(
            title: "Test Podcast",
            author: "Test Author",
            summary: "A test podcast.",
            category: "Technology",
            ownerEmail: "test@example.com",
            ownerName: "Test Author",
            hostBindingID: UUID(),
            feedRemotePath: "shows/test/feed.xml"
        )
        context.insert(show)

        // Episode without transcriptAssetID.
        let episode = Episode(
            title: "No Transcript Episode",
            originalAssetID: UUID(),
            status: .ready
        )
        episode.show = show
        context.insert(episode)

        let job = Job(kind: .generateMetadata, targetID: episode.id)
        context.insert(job)
        try context.save()

        let handler = makeHandler()

        await #expect(throws: PodedgeError.self) {
            try await handler.execute(jobID: job.id, container: container)
        }
    }
}
