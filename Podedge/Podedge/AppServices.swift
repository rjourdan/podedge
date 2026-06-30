import Foundation
import PodedgeCore
import SwiftData
import SwiftUI

/// The composition root — single owner of every service in the app.
///
/// Constructed once in `PodedgeApp.init()` and injected into the SwiftUI
/// environment. Views access services through `@Environment(\.appServices)`.
@MainActor
public final class AppServices {

    // MARK: - Services

    public let modelContainer: ModelContainer
    public let libraryStore: LibraryStore
    public let jobScheduler: JobScheduler
    public let keychainService: KeychainService
    public let hostService: HostService
    public let modelManager: ModelManager
    public let analyticsService: AnalyticsService
    public let distributionService: DistributionService
    public let toolRegistry: ToolRegistry
    public let toolBroker: ToolBroker
    public let auditLogService: AuditLogService
    public let audioPipeline: any AudioPipeline
    public let feedBuilder: FeedBuilder
    public let feedValidator: FeedValidator
    public let feedSerializer: FeedXMLSerializer
    public let publishArtifactBuilder: PublishArtifactBuilder
    public let publishService: PublishService
    public let publishDryRun: PublishDryRun
    public let ingestService: IngestService
    public let transcriptionService: TranscriptionService
    public private(set) var llmProvider: any LLMProvider
    public let llmService: LLMService
    public let metadataGenerationService: MetadataGenerationService
    public let bgTaskCoordinator: BGTaskCoordinator
    public let socialPostingService: SocialPostingService
    public let router: Router
    public let assistantController: AssistantController
    let confirmationCoordinator: ConfirmationCoordinator

    // MARK: - State

    private var hasBootstrapped = false

    // MARK: - Init

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let modelContext = ModelContext(modelContainer)
        let store = LibraryStore(modelContext: modelContext)
        self.libraryStore = store

        let scheduler = JobScheduler(modelContainer: modelContainer)
        self.jobScheduler = scheduler

        let keychain = KeychainService()
        self.keychainService = keychain

        let host = HostService(keychain: keychain)
        self.hostService = host

        let pipeline: any AudioPipeline = DefaultAudioPipeline()
        self.audioPipeline = pipeline
        let llmProvider: any LLMProvider = Self.resolveProvider()
        self.llmProvider = llmProvider
        let analyticsProvider: any AnalyticsProvider = PlaceholderAnalyticsProvider()

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory unavailable")
        }
        let modelsDir = appSupportDir
            .appendingPathComponent("Podedge", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let engine: any TranscriptionEngine = MLXTranscriptionEngine(modelID: "mlx-community/parakeet-tdt-0.6b-v3", modelsDirectory: modelsDir)
        self.modelManager = ModelManager(engine: engine, modelsDirectory: modelsDir)
        self.transcriptionService = TranscriptionService(engine: engine)

        self.analyticsService = AnalyticsService(
            provider: analyticsProvider,
            pollingInterval: .seconds(6 * 3600),
            persistSnapshot: { _, _ in }
        )

        let distribution = DistributionService()
        self.distributionService = distribution

        let registry = ToolRegistry()
        self.toolRegistry = registry
        let auditLog = AuditLogService(modelContext: modelContext)
        self.auditLogService = auditLog
        let broker = ToolBroker(registry: registry, auditLog: auditLog)
        self.toolBroker = broker

        let router = Router(llmProvider: llmProvider)
        self.router = router

        let caps = llmProvider.capabilities
        let label = "\(caps.modelID) · \(caps.providerID.uppercased())"
        self.assistantController = AssistantController(
            router: router,
            toolBroker: broker,
            auditLog: auditLog,
            llmProvider: llmProvider,
            providerLabel: label
        )

        let feed = FeedBuilder(resolveAsset: { _ in nil }, rewriteEnclosure: nil)
        self.feedBuilder = feed

        let validator = FeedValidator()
        self.feedValidator = validator

        let serializer = FeedXMLSerializer()
        self.feedSerializer = serializer

        let artifactBuilder = PublishArtifactBuilder(pipeline: pipeline)
        self.publishArtifactBuilder = artifactBuilder

        self.publishService = PublishService(
            store: store,
            hostService: host,
            feedBuilder: feed,
            feedValidator: validator,
            feedSerializer: serializer,
            distributionService: distribution,
            artifactBuilder: artifactBuilder
        )

        self.publishDryRun = PublishDryRun(
            store: store,
            hostService: host,
            feedBuilder: feed,
            feedValidator: validator,
            feedSerializer: serializer,
            distributionService: distribution,
            artifactBuilder: artifactBuilder
        )

        self.ingestService = IngestService(pipeline: pipeline, store: store, scheduler: scheduler)

        let llm = LLMService(provider: llmProvider)
        self.llmService = llm
        self.metadataGenerationService = MetadataGenerationService(llmService: llm)

        self.confirmationCoordinator = ConfirmationCoordinator()
        self.socialPostingService = SocialPostingService()

        self.bgTaskCoordinator = BGTaskCoordinator(
            jobScheduler: scheduler,
            libraryStore: store
        )
    }

    // MARK: - Provider Resolution

    private static func resolveProvider() -> any LLMProvider {
        let activeID = UserDefaults.standard.string(forKey: "llm.provider.activeID")
        let modelID = UserDefaults.standard.string(forKey: "llm.provider.modelID")
        switch activeID {
        case "mlx":
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelsDir = appSupport
                .appendingPathComponent("Podedge", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent("LLM", isDirectory: true)
            let sanitized = (modelID ?? "mlx-community/Qwen3-8B-4bit-DWQ-053125").replacingOccurrences(of: "/", with: "_")
            let modelDir = modelsDir.appendingPathComponent(sanitized, isDirectory: true)
            return MLXLLMProvider(modelID: modelID ?? "mlx-community/Qwen3-8B-4bit-DWQ-053125", modelsDirectory: modelDir)
        case "ollama":
            return OllamaLLMProvider(modelID: modelID ?? "llama3.1:8b")
        default:
            return DisabledLLMProvider()
        }
    }

    /// Replaces the active LLM provider. Called when user changes provider in Settings.
    public func updateLLMProvider() {
        llmProvider = Self.resolveProvider()
    }

    // MARK: - Bootstrap

    /// Registers job handlers for all job kinds and starts the scheduler.
    /// Must be called exactly once before any user interaction.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // Register real handlers
        jobScheduler.registerHandler(TranscribeJobHandler(transcriptionService: transcriptionService))
        jobScheduler.registerHandler(GenerateMetadataJobHandler(metadataService: metadataGenerationService))
        jobScheduler.registerHandler(PublishJobHandler(publishService: publishService, notificationService: NotificationService.shared))
        jobScheduler.registerHandler(UploadJobHandler(hostService: hostService))
        jobScheduler.registerHandler(OP3PollJobHandler(analyticsService: analyticsService))

        // Placeholder handlers for unimplemented job kinds
        for kind in JobKind.allCases where kind != .transcribe && kind != .generateMetadata && kind != .publish && kind != .upload && kind != .op3Poll {
            jobScheduler.registerHandler(PlaceholderJobHandler(handledKind: kind))
        }

        // Register copy-paste social targets (always available)
        await socialPostingService.register(CopyPasteTarget(platformID: "x", displayName: "X (Twitter)"))
        await socialPostingService.register(CopyPasteTarget(platformID: "linkedin", displayName: "LinkedIn"))
        await socialPostingService.register(CopyPasteTarget(platformID: "threads", displayName: "Threads"))

        bgTaskCoordinator.registerTasks()

        // Register tools
        await toolRegistry.register(ListShowsTool(store: libraryStore))
        await toolRegistry.register(GetShowTool(store: libraryStore))
        await toolRegistry.register(ListEpisodesTool(store: libraryStore))
        await toolRegistry.register(GetEpisodeTool(store: libraryStore))
        await toolRegistry.register(BuildPreviewTool(store: libraryStore, feedBuilder: feedBuilder, serializer: feedSerializer))
        await toolRegistry.register(ValidateFeedTool(store: libraryStore, feedBuilder: feedBuilder, validator: feedValidator))
        await toolRegistry.register(QueryCachedAnalyticsTool(store: libraryStore))
        await toolRegistry.register(GetDistributionStatusTool(store: libraryStore))
        await toolRegistry.register(CreateDraftTool(store: libraryStore))
        await toolRegistry.register(UpdateMetadataTool(store: libraryStore))
        await toolRegistry.register(TranscribeTool(store: libraryStore, scheduler: jobScheduler))
        await toolRegistry.register(PublishTool(store: libraryStore, scheduler: jobScheduler))
        await toolRegistry.register(UnpublishTool(store: libraryStore))
        await toolRegistry.register(DeleteEpisodeTool(store: libraryStore))
        await toolRegistry.register(CreateShowTool(store: libraryStore))
        await toolRegistry.register(UpdateShowMetadataTool(store: libraryStore))
        await toolRegistry.register(DeleteShowTool(store: libraryStore))
        await toolRegistry.register(GenerateMetadataTool(store: libraryStore, scheduler: jobScheduler))
        await toolRegistry.register(GenerateBlurbTool(store: libraryStore, renderer: .bluesky(llmService: llmService)))
        await toolRegistry.register(TestBindingTool(store: libraryStore, hostService: hostService))
        await toolRegistry.register(RemoveBindingTool(store: libraryStore))
        await toolRegistry.register(SocialPostTool(socialService: socialPostingService))
        await toolRegistry.register(ListJobsTool(store: libraryStore))

        jobScheduler.start()
    }

    /// Stops the job scheduler. Call on app termination.
    public func shutdown() {
        jobScheduler.stop()
    }
}

// MARK: - Placeholder Implementations

private struct PlaceholderJobHandler: JobHandler {
    let handledKind: JobKind
    func execute(jobID: UUID, container: ModelContainer) async throws {}
}

private struct PlaceholderAudioPipeline: AudioPipeline {
    func sha256(of url: URL) async throws -> String { String(repeating: "0", count: 64) }
    func probe(url: URL) async throws -> AudioProbeResult { AudioProbeResult(duration: 0, bitrate: 0, channels: 0, sampleRate: 0) }
    func waveform(url: URL, sampleCount: Int) async throws -> [Float] { [] }
    func readID3(url: URL) async throws -> ID3Metadata { ID3Metadata() }
    func writeID3(to url: URL, metadata: ID3Metadata) async throws {}
}

private struct PlaceholderAnalyticsProvider: AnalyticsProvider {
    var providerName: String { "placeholder" }
    func register(feedURL: URL, podcastGUID: UUID) async throws -> String { "" }
    func prefixURL(for enclosureURL: URL) -> URL { enclosureURL }
    func fetchSnapshot(externalShowID: String, window: DateInterval) async throws -> AnalyticsFetchResult {
        AnalyticsFetchResult(downloads: 0, uniqueListeners: 0)
    }
}

private struct DisabledLLMProvider: LLMProvider {
    var capabilities: LLMProviderCapabilities {
        LLMProviderCapabilities(supportsNativeToolUse: false, supportsStreaming: false, maxContextTokens: 0, modelID: "none", providerID: "disabled")
    }
    func complete(prompt: String, systemPrompt: String?, maxTokens: Int) async throws -> LLMResponse {
        throw PodedgeError.llmFailed(reason: "No AI provider configured. Complete onboarding or visit Settings → LLM Providers.")
    }
    func stream(prompt: String, systemPrompt: String?, maxTokens: Int) -> AsyncThrowingStream<LLMStreamChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: PodedgeError.llmFailed(reason: "No AI provider configured.")) }
    }
    func complete(prompt: String, systemPrompt: String?, maxTokens: Int, schema: String) async throws -> LLMResponse {
        throw PodedgeError.llmFailed(reason: "No AI provider configured. Complete onboarding or visit Settings → LLM Providers.")
    }
    func complete(_ prompt: String, systemPrompt: String?, maxTokens: Int, tools: [any ToolDefinition]?) async throws -> LLMResponse {
        throw PodedgeError.llmFailed(reason: "No AI provider configured.")
    }
    func stream(_ prompt: String, systemPrompt: String?, maxTokens: Int, tools: [any ToolDefinition]?) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: PodedgeError.llmFailed(reason: "No AI provider configured.")) }
    }
}

// MARK: - Environment Key

private struct AppServicesKey: EnvironmentKey {
    static let defaultValue: AppServices? = nil
}

extension EnvironmentValues {
    var appServices: AppServices? {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
