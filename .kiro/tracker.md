# Podedge v1 Implementation Tracker — Spec-organized

Last updated: 2026-05-05

## Pre-v1 (Historic)

Work streams WS1–WS8 produced a compilable app shell with fully unit-tested PodedgeCore services. The gap: **the app target never instantiates any service**. No pipeline is wired end-to-end.

| Work Stream | What Was Built | Gap |
|-------------|---------------|-----|
| WS1–WS3 | Xcode project, PodedgeCore package, all 7 extension-point protocols, SwiftData models, LibraryStore, JobScheduler, KeychainService, Logger, ToolRegistry, ToolBroker, AuditLogService | No concrete AudioPipeline; no TranscriptionEngine; ToolRegistry empty at runtime |
| WS4–WS6 | MP3Validator, AudioProber, WaveformGenerator, ID3TagService, IngestService, TranscriptionService (protocol only), MLXLLMProvider (stub), LLMService, MetadataGenerationService, S3Host, HostService, FeedBuilder, FeedXMLSerializer, FeedValidator, OP3AnalyticsProvider, AnalyticsService, DistributionService, all distribution targets | MLXLLMProvider throws on every call; no WhisperKitTranscriptionEngine; DefaultAudioPipeline not composed; no JobHandlers |
| WS7–WS8 | PublishService, PublishDryRun, PublishArtifactBuilder, SocialBlurbRenderer, all SwiftUI views (MainWindowView, EpisodeEditorView, SettingsView, OnboardingView, etc.), ConfirmationCoordinator, ToolButton, NotificationService, UpdateChecker | Publish button not wired; EpisodeListView.importAudio bypasses IngestService; no AppServices composition root; no Assistant |

**Summary gap:** App shell compiles but no pipeline wiring; MLXLLMProvider stub; no TranscriptionEngine; no real AudioPipeline; empty ToolRegistry at runtime.

---

## v1 Specs


### Spec 01 — Composition Root

[requirements.md](.kiro/specs/01-composition-root/requirements.md) · [design.md](.kiro/specs/01-composition-root/design.md)

**Status:** ⬜ Not started  
**Dependencies:** None (prerequisite for all other specs)

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 01.1 | Audit and set `public` on all PodedgeCore types used by the app | Multiple `PodedgeCore/Sources/PodedgeCore/Services/*.swift` | ⬜ |
| 01.2 | Create `AppServices` class with all service properties | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 01.3 | Implement `AppServices.bootstrap()` (handler + tool registration, scheduler start) | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 01.4 | Add `AppServicesKey` environment key and `EnvironmentValues` extension | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 01.5 | Rewrite `PodedgeApp` to construct `AppServices` and inject via environment | `Podedge/Podedge/PodedgeApp.swift` | ⬜ |
| 01.6 | Add `handler(for:)` method to `JobScheduler` | `PodedgeCore/Sources/PodedgeCore/Services/JobScheduler.swift` | ⬜ |
| 01.7 | Write `AppServicesTests` (all job kinds have handlers, bootstrap idempotent) | `PodedgeTests/AppServicesTests.swift` | ⬜ |

---

### Spec 02 — Audio Ingest

[requirements.md](.kiro/specs/02-audio-ingest/requirements.md) · [design.md](.kiro/specs/02-audio-ingest/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 01

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 02.1 | Create `DefaultAudioPipeline` composing MP3Validator, AudioProber, WaveformGenerator, ID3TagService, CryptoKit SHA-256 | `PodedgeCore/Sources/PodedgeCore/Services/DefaultAudioPipeline.swift` | ⬜ |
| 02.2 | Wire `DefaultAudioPipeline` into `AppServices` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 02.3 | Replace `EpisodeListView.importAudio` with `appServices.ingestService.ingest(fileURL:show:)` | `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` | ⬜ |
| 02.4 | Add ingest error alert to `EpisodeListView` | `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` | ⬜ |
| 02.5 | Write `DefaultAudioPipelineTests` (sha256 property test, probe, waveform) | `PodedgeCoreTests/DefaultAudioPipelineTests.swift` | ⬜ |
| 02.6 | Write `IngestServiceIntegrationTests` (creates episode+assets, enqueues jobs, failure cleanup) | `PodedgeCoreTests/IngestServiceIntegrationTests.swift` | ⬜ |

---

### Spec 03 — Transcription

[requirements.md](.kiro/specs/03-transcription/requirements.md) · [design.md](.kiro/specs/03-transcription/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 01, Spec 02

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 03.1 | Add WhisperKit to `Package.swift` | `PodedgeCore/Package.swift` | ⬜ |
| 03.2 | Create `WhisperKitTranscriptionEngine` actor | `PodedgeCore/Sources/PodedgeCore/Services/WhisperKitTranscriptionEngine.swift` | ⬜ |
| 03.3 | Create `TranscribeJobHandler` | `PodedgeCore/Sources/PodedgeCore/Services/TranscribeJobHandler.swift` | ⬜ |
| 03.4 | Register `TranscribeJobHandler` in `AppServices.bootstrap()` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 03.5 | Update `OnboardingView` step 4 with model download list and progress | `Podedge/Podedge/Views/Onboarding/OnboardingView.swift` | ⬜ |
| 03.6 | Update `EpisodeEditorView` transcript tab to show VTT content or progress | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` | ⬜ |
| 03.7 | Write `WhisperKitTranscriptionEngineTests` and `TranscribeJobHandlerTests` | `PodedgeCoreTests/WhisperKitTranscriptionEngineTests.swift`, `TranscribeJobHandlerTests.swift` | ⬜ |

---

### Spec 04 — Local LLM Providers (MLX + Ollama)

[requirements.md](.kiro/specs/04-local-llm-mlx/requirements.md) · [design.md](.kiro/specs/04-local-llm-mlx/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 01

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 04.1 | Add `mlx-swift-examples` to `Package.swift` | `PodedgeCore/Package.swift` | ⬜ |
| 04.2 | Replace stub `MLXLLMProvider` with real MLX inference using `mlx-swift-examples` and support for the 3 bundled MLX model IDs (Gemma 4 E4B, Qwen 3 8B DWQ, Mistral Small 24B) | `PodedgeCore/Sources/PodedgeCore/LLM/MLXLLMProvider.swift` | ⬜ |
| 04.3 | Create `LLMModelInfo` struct | `PodedgeCore/Sources/PodedgeCore/Models/LLMModelInfo.swift` | ⬜ |
| 04.4 | Add `availableLLMModels()` and `downloadLLMModel(named:onProgress:)` to `ModelManager` | `PodedgeCore/Sources/PodedgeCore/Services/ModelManager.swift` | ⬜ |
| 04.5 | Wire active provider (MLX or Ollama based on user selection from UserDefaults) into `AppServices` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 04.6 | ~~Update `OnboardingView` to show LLM model in download list~~ — replaced by 04.13 | — | ~~⬜~~ |
| 04.7 | Write `MLXLLMProviderTests` (token counts, schema-constrained output, not-loaded throws) | `PodedgeCoreTests/MLXLLMProviderTests.swift` | ⬜ |
| 04.8 | Create `OllamaLLMProvider` | `PodedgeCore/Sources/PodedgeCore/LLM/OllamaLLMProvider.swift` | ⬜ |
| 04.9 | Create `OllamaModelInfo` type | `PodedgeCore/Sources/PodedgeCore/Models/OllamaModelInfo.swift` | ⬜ |
| 04.10 | Extend `ModelManager` with `availableOllamaModels(baseURL:)` | `PodedgeCore/Sources/PodedgeCore/Services/ModelManager.swift` | ⬜ |
| 04.11 | Add `ollamaUnreachable` case to `PodedgeError` | `PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift` | ⬜ |
| 04.12 | Create `AIProviderPickerView` with 4 options + guidance strings | `Podedge/Podedge/Views/Onboarding/AIProviderPickerView.swift` | ⬜ |
| 04.13 | Rewrite `OnboardingView` step 4 to use `AIProviderPickerView` | `Podedge/Podedge/Views/Onboarding/OnboardingView.swift` | ⬜ |
| 04.14 | Add LLM Providers tab to `SettingsView` | `Podedge/Podedge/Views/Settings/SettingsView.swift` | ⬜ |
| 04.15 | Write `OllamaLLMProviderTests` (URLProtocol stubs, `/api/tags`, `/api/chat`, tool-use) | `PodedgeCoreTests/OllamaLLMProviderTests.swift` | ⬜ |


### Spec 05 — Metadata Generation

[requirements.md](.kiro/specs/05-metadata-generation/requirements.md) · [design.md](.kiro/specs/05-metadata-generation/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 03, Spec 04

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 05.1 | Create `EpisodeSuggestions` SwiftData model | `PodedgeCore/Sources/PodedgeCore/Models/EpisodeSuggestions.swift` | ⬜ |
| 05.2 | Add `EpisodeSuggestions` to `PodedgeSchema` | `PodedgeCore/Sources/PodedgeCore/Models/ModelContainerSetup.swift` | ⬜ |
| 05.3 | Create `GenerateMetadataJobHandler` | `PodedgeCore/Sources/PodedgeCore/Services/GenerateMetadataJobHandler.swift` | ⬜ |
| 05.4 | Register `GenerateMetadataJobHandler` in `AppServices.bootstrap()` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 05.5 | Update `EpisodeEditorView` Metadata tab with suggestions + Apply/Regenerate | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` | ⬜ |
| 05.6 | Update `EpisodeEditorView` Chapters tab with suggested chapters + Apply All | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` | ⬜ |
| 05.7 | Update `PromotionTabView` to show blurbs from `EpisodeSuggestions` | `Podedge/Podedge/Views/Components/PromotionTabView.swift` | ⬜ |
| 05.8 | Write `GenerateMetadataJobHandlerTests` | `PodedgeCoreTests/GenerateMetadataJobHandlerTests.swift` | ⬜ |

---

### Spec 06 — Publish Pipeline

[requirements.md](.kiro/specs/06-publish-pipeline/requirements.md) · [design.md](.kiro/specs/06-publish-pipeline/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 01, Spec 02

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 06.1 | Create `PublishJobHandler` | `PodedgeCore/Sources/PodedgeCore/Services/PublishJobHandler.swift` | ⬜ |
| 06.2 | Create `UploadJobHandler` | `PodedgeCore/Sources/PodedgeCore/Services/UploadJobHandler.swift` | ⬜ |
| 06.3 | Create `OP3PollJobHandler` | `PodedgeCore/Sources/PodedgeCore/Services/OP3PollJobHandler.swift` | ⬜ |
| 06.4 | Create `NotificationServiceProtocol` | `PodedgeCore/Sources/PodedgeCore/Services/NotificationServiceProtocol.swift` | ⬜ |
| 06.5 | Create `BGTaskCoordinator` and register `dev.podedge.scheduled-publish` | `Podedge/Podedge/Services/BGTaskCoordinator.swift` | ⬜ |
| 06.6 | Add `BGTaskSchedulerPermittedIdentifiers` to `Info.plist` | `Podedge/Podedge/Info.plist` | ⬜ |
| 06.7 | Register all three job handlers in `AppServices.bootstrap()` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 06.8 | Wire Publish tab: Preview Publish sheet, ToolButton for publish/unpublish, scheduledFor DatePicker | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` | ⬜ |
| 06.9 | Write `PublishJobHandlerTests` and `OP3PollJobHandlerTests` | `PodedgeCoreTests/PublishJobHandlerTests.swift`, `OP3PollJobHandlerTests.swift` | ⬜ |

---

### Spec 07 — Social Posting

[requirements.md](.kiro/specs/07-social-posting/requirements.md) · [design.md](.kiro/specs/07-social-posting/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 05, Spec 06

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 07.1 | Create `SocialPostingTarget` protocol and supporting types | `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingTarget.swift` | ⬜ |
| 07.2 | Create `BlueskyTarget` (AT Protocol) | `PodedgeCore/Sources/PodedgeCore/Social/BlueskyTarget.swift` | ⬜ |
| 07.3 | Create `MastodonTarget` (/api/v1/statuses) | `PodedgeCore/Sources/PodedgeCore/Social/MastodonTarget.swift` | ⬜ |
| 07.4 | Create `CopyPasteTarget` for X, LinkedIn, Threads | `PodedgeCore/Sources/PodedgeCore/Social/CopyPasteTarget.swift` | ⬜ |
| 07.5 | Create `SocialPostingService` actor | `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingService.swift` | ⬜ |
| 07.6 | Add `socialPostFailed` to `PodedgeError` | `PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift` | ⬜ |
| 07.7 | Add Bluesky and Mastodon Keychain accessors | `PodedgeCore/Sources/PodedgeCore/Services/KeychainService.swift` | ⬜ |
| 07.8 | Wire `PromotionTabView` Post/Copy buttons | `Podedge/Podedge/Views/Components/PromotionTabView.swift` | ⬜ |
| 07.9 | Add Social accounts tab to `SettingsView` | `Podedge/Podedge/Views/Settings/SettingsView.swift` | ⬜ |
| 07.10 | Write `BlueskyTargetTests` and `MastodonTargetTests` (URLProtocol stubs) | `PodedgeCoreTests/BlueskyTargetTests.swift`, `MastodonTargetTests.swift` | ⬜ |

---

### Spec 08 — Tool Registry Wiring

[requirements.md](.kiro/specs/08-tool-registry-wiring/requirements.md) · [design.md](.kiro/specs/08-tool-registry-wiring/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 01, Spec 06, Spec 07

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 08.1 | Create `ToolPayloads.swift` with all input/output types | `PodedgeCore/Sources/PodedgeCore/Services/ToolPayloads.swift` | ⬜ |
| 08.2 | Create tool implementation files (LibraryTools, FeedTools, EpisodeTools, etc.) | `PodedgeCore/Sources/PodedgeCore/Tools/*.swift` | ⬜ |
| 08.3 | Add `AuditLogService` dependency to `ToolBroker`; write audit entries on every invocation | `PodedgeCore/Sources/PodedgeCore/Services/ToolBroker.swift` | ⬜ |
| 08.4 | Register all 23 tools in `AppServices.bootstrap()` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 08.5 | Replace direct service calls with `ToolButton` in `EpisodeEditorView`, `ShowListView`, `EpisodeListView`, `PromotionTabView` | Multiple view files | ⬜ |
| 08.6 | Create `AuditLogView` and add to `SettingsView` | `Podedge/Podedge/Views/Settings/AuditLogView.swift` | ⬜ |
| 08.7 | Write `ToolRegistryWiringTests` (all tools registered, destructive audit, duplicate replacement) | `PodedgeCoreTests/ToolRegistryWiringTests.swift` | ⬜ |


### Spec 09 — Assistant Core

[requirements.md](.kiro/specs/09-assistant-core/requirements.md) · [design.md](.kiro/specs/09-assistant-core/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 08

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 09.1 | Extend `LLMProvider` protocol with `capabilities`, `complete(tools:)`, `stream(tools:)`, `LLMStreamEvent` | `PodedgeCore/Sources/PodedgeCore/Services/LLMProvider.swift` | ⬜ |
| 09.2 | Update `MLXLLMProvider` to implement extended protocol (prompt-emulated tool use) | `PodedgeCore/Sources/PodedgeCore/LLM/MLXLLMProvider.swift` | ⬜ |
| 09.3 | Update `OllamaLLMProvider` to implement extended protocol (native tool-use + prompt-emulated fallback) | `PodedgeCore/Sources/PodedgeCore/LLM/OllamaLLMProvider.swift` | ⬜ |
| 09.4 | Create `AssistantController` (`@MainActor @Observable`) with rate-limit enforcement | `PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift` | ⬜ |
| 09.5 | Create `AssistantMessage` and `ToolCallRecord` value types | `PodedgeCore/Sources/PodedgeCore/Services/AssistantMessage.swift` | ⬜ |
| 09.6 | Create `Router` (keyword rules + LLM classifier fallback) | `PodedgeCore/Sources/PodedgeCore/Services/Router.swift` | ⬜ |
| 09.7 | Create `EscapeHatchResponder` | `PodedgeCore/Sources/PodedgeCore/Services/EscapeHatchResponder.swift` | ⬜ |
| 09.8 | Create `AssistantPaneView` with conversation list, input, tool-call rows, provider label | `Podedge/Podedge/Views/Assistant/AssistantPaneView.swift` | ⬜ |
| 09.9 | Add ⌘K shortcut and pane visibility preference to `MainWindowView` | `Podedge/Podedge/Views/MainWindowView.swift` | ⬜ |
| 09.10 | Add Assistant-specific settings to LLM Providers tab (per-session rate limits UI) | `Podedge/Podedge/Views/Settings/SettingsView.swift` | ⬜ |
| 09.11 | Wire `AssistantController` and `Router` into `AppServices` | `Podedge/Podedge/AppServices.swift` | ⬜ |
| 09.12 | Write `RouterTests` and `AssistantControllerTests` | `PodedgeCoreTests/RouterTests.swift`, `AssistantControllerTests.swift` | ⬜ |

---

### Spec 10 — Specialist Agents

[requirements.md](.kiro/specs/10-specialist-agents/requirements.md) · [design.md](.kiro/specs/10-specialist-agents/design.md)

**Status:** ⬜ Not started  
**Dependencies:** Spec 09

| ID | Task | File(s) | Status |
|----|------|---------|--------|
| 10.1 | Create `SpecialistAgent` protocol and `AgentContext`, `AgentResponse` types | `PodedgeCore/Sources/PodedgeCore/Services/SpecialistAgent.swift` | ⬜ |
| 10.2 | Create `PromoterAgent` with tool whitelist and system prompt | `PodedgeCore/Sources/PodedgeCore/Agents/PromoterAgent.swift` | ⬜ |
| 10.3 | Create `PublishAssistantAgent` with tool whitelist and system prompt | `PodedgeCore/Sources/PodedgeCore/Agents/PublishAssistantAgent.swift` | ⬜ |
| 10.4 | Create `CapabilityTierService` with known-models lookup table | `PodedgeCore/Sources/PodedgeCore/Services/CapabilityTierService.swift` | ⬜ |
| 10.5 | Create `PerShowGuidesService` (reads per-show markdown files) | `PodedgeCore/Sources/PodedgeCore/Services/PerShowGuidesService.swift` | ⬜ |
| 10.6 | Write agent prompt resources (`_safety.md`, `_escape-hatch.md`, `promoter.md`, `publish-assistant.md`) | `PodedgeCore/Sources/PodedgeCore/Resources/Agents/` | ⬜ |
| 10.7 | Add agent registry to `AssistantController`; register both agents | `PodedgeCore/Sources/PodedgeCore/Services/AssistantController.swift`, `Podedge/Podedge/AppServices.swift` | ⬜ |
| 10.8 | Add `allowedTools` to `ToolCaller` for per-agent whitelist enforcement in `ToolBroker` | `PodedgeCore/Sources/PodedgeCore/Services/ToolDefinition.swift`, `ToolBroker.swift` | ⬜ |
| 10.9 | Write `PromoterAgentTests`, `PublishAssistantAgentTests`, `CapabilityTierServiceTests`, `PerShowGuidesServiceTests` | `PodedgeCoreTests/` | ⬜ |


---

## Dependency Graph

```
01 (Composition Root)
├── 02 (Audio Ingest)
│   └── 03 (Transcription)
│       └── 05 (Metadata Generation) ←── 04 (Local LLM)
│           └── 07 (Social Posting)
│               └── 08 (Tool Registry Wiring)
│                   └── 09 (Assistant Core)
│                       └── 10 (Specialist Agents)
├── 04 (Local LLM) [parallel with 02/03]
└── 06 (Publish Pipeline) [parallel with 03/04/05]
    └── 07 (Social Posting)
        └── 08 (Tool Registry Wiring)
```

Simplified: `01 → {02, 04, 06} → 05 → 07 → 08 → 09 → 10`

- Specs 02, 04, and 06 can start in parallel once Spec 01 is done.
- Spec 03 requires Spec 02 (needs ingest to produce audio assets).
- Spec 05 requires both Spec 03 (transcript) and Spec 04 (LLM).
- Spec 06 requires Spec 01 and Spec 02 (needs ingest pipeline and AppServices).
- Spec 07 requires Spec 05 (blurbs) and Spec 06 (publish context).
- Spec 08 requires Spec 01, 06, and 07 (all tools must exist before wiring).
- Spec 09 requires Spec 08 (tools must be registered before the Assistant can invoke them).
- Spec 10 requires Spec 09 (agents run inside AssistantController).

---

## Execution Order

### Wave 1 (sequential prerequisite)
- **Spec 01** — Composition Root. Must complete before anything else.

### Wave 2 (parallel)
- **Spec 02** — Audio Ingest
- **Spec 04** — Local LLM (MLX)
- **Spec 06** — Publish Pipeline (depends on 01 + 02; start after 02 is done)

### Wave 3 (parallel, after Wave 2)
- **Spec 03** — Transcription (after 02)
- **Spec 05** — Metadata Generation (after 03 + 04)

### Wave 4 (sequential)
- **Spec 07** — Social Posting (after 05 + 06)

### Wave 5 (sequential)
- **Spec 08** — Tool Registry Wiring (after 01 + 06 + 07)

### Wave 6 (sequential)
- **Spec 09** — Assistant Core (after 08)

### Wave 7 (sequential)
- **Spec 10** — Specialist Agents (after 09)

**Minimum critical path:** 01 → 02 → 03 → 05 → 07 → 08 → 09 → 10 (7 sequential steps)  
**With parallelism:** 01 → {02 ‖ 04} → {03 ‖ 06} → 05 → 07 → 08 → 09 → 10

---

## v1.1 Deferred

The following features are specified but not built in v1:

| Feature | Notes |
|---------|-------|
| AnalystAgent | Reads OP3 cached data, renders charts via conversation |
| FeedDebuggerAgent | Read-only feed + validator + distribution status |
| QueryResolverAgent | Library read-only, shallow "what is / where is" queries |
| AnthropicLLMProvider | Claude via Messages API with native tool-use; Keychain-stored API key |
| OpenAI LLMProvider | GPT family via official API |
| OpenAI-compatible LLMProvider | Generic base URL + key (Groq, Together, LM Studio, etc.) |
| Large-model (100 GB+) MLX in-process support | Pre-flight RAM gating, resumable 100 GB+ downloads, validated mlx-swift-examples support for DeepSeek V4 / Qwen 3.5 / Gemma 4 31B architectures |
| BYO-AI routing UI | Per-task provider assignment matrix |
| LLM cost accounting | `LLMCallLog` model, pricing table, estimated USD per call |
| Command-line interface (`podedge-cli`) | `swift-argument-parser`, shares SwiftData store |
| External MCP agent access | `MCPServerInterface`, `podedge-agent` executable |
| Audiograms & quote cards | `AudiogramRenderer`, `QuoteCardRenderer` |
| Additional hosts | R2, B2, DigitalOcean Spaces, SFTP, WebDAV |
| Advanced audio pipelines | Normalize, denoise, silence trim, filler removal |
| Show import from feed | `FeedImporter`, `CutoverAssistant`, managed-externally mode |
| Suggestion rail | Context-sensitive "Try asking…" in Assistant pane |
| `/capabilities` slash command | Categorized tool listing in Assistant |
| Cross-session conversation persistence | Each ⌘K starts fresh in v1.1 too; persistence is v1.2 |

---

## Archive — Pre-v1 Work

*(Preserved from the original tracker for historical reference)*

Work streams WS1–WS8 were completed between 2026-04-29 and 2026-05-04. They established the PodedgeCore package structure, all SwiftData models, all extension-point protocols, and all service implementations in isolation. The app target was built as a shell with placeholder wiring. 81 unit tests pass as of WS3 review (2026-04-30). The WS3 review decisions document is at `.kiro/learnings/ws3-review-decisions.md`.

Key decisions made during pre-v1 work:
- `ToolResult.failure` stores `String` (not `Error`) for `Sendable` compliance.
- `ShowSnapshot` / `EpisodeSnapshot` value types used at protocol boundaries.
- `JobScheduler` is `@MainActor`-isolated; handlers manage their own `ModelContext`.
- `AnalyticsSnapshotData` renamed to `AnalyticsFetchResult`.
- SwiftData test pattern: single shared `TestDatabase` with per-test `reset()`.
