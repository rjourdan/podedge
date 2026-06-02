import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Test Helpers

private struct MockTool: ToolDefinition {
    let name: String
    let description: String
    let scope: ToolScope
    let requiredTier: CapabilityTier = .full
    let parameterSchema: String = "{}"

    func execute(input: Data) async throws -> Data {
        Data("mock_output".utf8)
    }
}

private struct MockCaller: ToolCaller {
    let capabilityTier: CapabilityTier = .full
}

// MARK: - Tag

extension Tag {
    @Tag static var toolRegistry: Self
}

// MARK: - Tests

@Suite("ToolRegistryWiring", .tags(.toolRegistry))
struct ToolRegistryWiringTests {

    @Test("Duplicate registration replaces existing tool")
    func duplicateRegistrationReplaces() async throws {
        let registry = ToolRegistry()
        let first = MockTool(name: "dup_tool", description: "first", scope: .readOnly)
        let second = MockTool(name: "dup_tool", description: "second", scope: .mutating)

        await registry.register(first)
        await registry.register(second)

        let found = await registry.tool(named: "dup_tool")
        #expect(found?.description == "second")
        #expect(found?.scope == .mutating)
    }

    @Test("Destructive tool produces audit entry")
    @MainActor
    func destructiveToolProducesAuditEntry() async throws {
        let container = TestDatabase.container(for: "toolwiringaudit")
        try TestDatabase.reset(container)
        let context = container.mainContext
        let auditLog = AuditLogService(modelContext: context)

        let registry = ToolRegistry()
        let tool = MockTool(name: "destroy_it", description: "destroys things", scope: .destructive)
        await registry.register(tool)

        let broker = ToolBroker(registry: registry, auditLog: auditLog)
        let caller = MockCaller()
        let result = await broker.invokeConfirmed(
            toolNamed: "destroy_it",
            input: Data("test_input".utf8),
            caller: caller
        )

        if case .success = result {} else {
            Issue.record("Expected success, got \(result)")
        }

        try context.save()
        let entries = try auditLog.entries(toolName: "destroy_it")
        #expect(entries.count == 1)
        #expect(entries.first?.success == true)
        #expect(entries.first?.toolName == "destroy_it")
        #expect(entries.first?.scope == .destructive)
    }

    @Test("Read tool does not require confirmation")
    func readToolDoesNotRequireConfirmation() async {
        let registry = ToolRegistry()
        let tool = MockTool(name: "read_thing", description: "reads", scope: .readOnly)
        await registry.register(tool)

        let broker = ToolBroker(registry: registry)
        let caller = MockCaller()
        let result = await broker.invoke(toolNamed: "read_thing", input: Data(), caller: caller)

        if case .success(let data) = result {
            #expect(String(data: data, encoding: .utf8) == "mock_output")
        } else {
            Issue.record("Expected .success, got \(result)")
        }
    }

    @Test("Destructive tool returns needsConfirmation via invoke")
    func destructiveToolReturnsNeedsConfirmation() async {
        let registry = ToolRegistry()
        let tool = MockTool(name: "nuke_it", description: "nukes", scope: .destructive)
        await registry.register(tool)

        let broker = ToolBroker(registry: registry)
        let caller = MockCaller()
        let result = await broker.invoke(toolNamed: "nuke_it", input: Data("payload".utf8), caller: caller)

        if case .needsConfirmation(let name, _) = result {
            #expect(name == "nuke_it")
        } else {
            Issue.record("Expected .needsConfirmation, got \(result)")
        }
    }

    @Test("All 23 tools registered")
    @MainActor
    func allToolsRegisteredCount() async throws {
        let container = TestDatabase.container(for: "toolwiringcount")
        try TestDatabase.reset(container)
        let context = container.mainContext
        let store = LibraryStore(modelContext: context)
        let scheduler = JobScheduler(modelContainer: container)
        let keychain = KeychainService()
        let host = HostService(keychain: keychain)
        let feedBuilder = FeedBuilder(resolveAsset: { _ in nil }, rewriteEnclosure: nil)
        let feedValidator = FeedValidator()
        let feedSerializer = FeedXMLSerializer()
        let llmService = LLMService(provider: StubLLMProvider())
        let socialPostingService = SocialPostingService()

        let registry = ToolRegistry()

        await registry.register(ListShowsTool(store: store))
        await registry.register(GetShowTool(store: store))
        await registry.register(ListEpisodesTool(store: store))
        await registry.register(GetEpisodeTool(store: store))
        await registry.register(BuildPreviewTool(store: store, feedBuilder: feedBuilder, serializer: feedSerializer))
        await registry.register(ValidateFeedTool(store: store, feedBuilder: feedBuilder, validator: feedValidator))
        await registry.register(QueryCachedAnalyticsTool(store: store))
        await registry.register(GetDistributionStatusTool(store: store))
        await registry.register(CreateDraftTool(store: store))
        await registry.register(UpdateMetadataTool(store: store))
        await registry.register(TranscribeTool(store: store, scheduler: scheduler))
        await registry.register(PublishTool(store: store, scheduler: scheduler))
        await registry.register(UnpublishTool(store: store))
        await registry.register(DeleteEpisodeTool(store: store))
        await registry.register(CreateShowTool(store: store))
        await registry.register(UpdateShowMetadataTool(store: store))
        await registry.register(DeleteShowTool(store: store))
        await registry.register(GenerateMetadataTool(store: store, scheduler: scheduler))
        await registry.register(GenerateBlurbTool(store: store, renderer: .bluesky(llmService: llmService)))
        await registry.register(TestBindingTool(store: store, hostService: host))
        await registry.register(RemoveBindingTool(store: store))
        await registry.register(SocialPostTool(socialService: socialPostingService))
        await registry.register(ListJobsTool(store: store))

        let all = await registry.allTools()
        #expect(all.count == 23)
    }
}

// MARK: - Stubs for allToolsRegisteredCount

private struct StubLLMProvider: LLMProvider {
    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        LLMResponse(text: "stub", inputTokens: 0, outputTokens: 0, finishReason: .stop)
    }
    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        LLMResponse(text: "stub", inputTokens: 0, outputTokens: 0, finishReason: .stop)
    }
}

private struct StubAudioPipeline: AudioPipeline {
    func sha256(of url: URL) async throws -> String { String(repeating: "0", count: 64) }
    func probe(url: URL) async throws -> AudioProbeResult { AudioProbeResult(duration: 0, bitrate: 0, channels: 0, sampleRate: 0) }
    func waveform(url: URL, sampleCount: Int) async throws -> [Float] { [] }
    func readID3(url: URL) async throws -> ID3Metadata { ID3Metadata() }
    func writeID3(to url: URL, metadata: ID3Metadata) async throws {}
}
