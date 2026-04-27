# Podedge macOS App - Detailed Implementation Task List

Ordered for v1. Each phase is shippable-ish — you could stop and have something
useful. Tasks inside a phase can often parallelize; cross-phase dependencies
are noted.

## Phase 1: Project Setup & Foundation

### Task 1.1: Create Xcode Project Structure
**Files to create:**
- `Podedge.xcodeproj`
- `Podedge/PodedgeApp.swift`
- `Podedge/Info.plist`
- `Podedge/Podedge.entitlements`

**Implementation:**
```swift
// PodedgeApp.swift
import SwiftUI
import SwiftData

@main
struct PodedgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup { MainWindowView() }
            .modelContainer(for: [Show.self, Episode.self, Asset.self,
                                  HostBinding.self, AnalyticsBinding.self,
                                  DistributionRecord.self, Job.self,
                                  AnalyticsSnapshot.self])
        MenuBarExtra("Podedge", systemImage: "dot.radiowaves.left.and.right") {
            MenuBarContentView()
        }
    }
}
```
**Dependencies:** None
**Key config:** macOS 15.0 deployment target, Apple Silicon only.

### Task 1.2: Configure Entitlements
**Files to modify:** `Podedge.entitlements`, `Info.plist`
**Entitlements:**
- `com.apple.security.app-sandbox`
- `com.apple.security.network.client`
- `com.apple.security.files.user-selected.read-write`
**Dependencies:** Task 1.1

### Task 1.3: Add Swift Package Dependencies
**Dependencies to add:**
- AWS SDK for Swift (`aws-sdk-swift`) — S3
- WhisperKit or vendored wispr transcription package
- MLX-Swift + `mlx-swift-examples` (for LLM)
- (optional) `swift-markdown` for description HTML rendering
**Dependencies:** Task 1.1

### Task 1.4: Set Up Folder Structure
```
Podedge/
  Models/        (SwiftData @Model types + value types)
  Services/      (business logic, one service per file)
  Extensions/    (protocol definitions + default implementations)
  Hosts/         (PodcastHost implementations)
  Distribution/  (DistributionTarget implementations)
  LLM/           (LLMProvider implementations + prompts)
  Analytics/     (AnalyticsProvider implementations)
  UI/
    Main/
    Episode/
    Settings/
    Onboarding/
    Components/
  Resources/
    Prompts/
  Utilities/
```
**Dependencies:** Task 1.1

## Phase 1.5: PodedgeCore Package Split

Pulled forward from deferred work because it unlocks CLI and MCP server later with zero refactor. Cost is ~1 day now; retrofit later is a week of churn.

### Task 1.5.1: Create PodedgeCore Swift Package
**Files to create:**
- `PodedgeCore/Package.swift`
- `PodedgeCore/Sources/PodedgeCore/` — destination for all non-UI code
**Structure:**
```
PodedgeCore/
  Sources/PodedgeCore/
    Models/
    Services/
    Extensions/      (protocols)
    Hosts/
    Distribution/
    LLM/
    Analytics/
    Utilities/
  Tests/PodedgeCoreTests/
```
**Dependencies:** Task 1.1

### Task 1.5.2: Convert Xcode Project to Workspace
Move the existing Xcode project into `Podedge.xcworkspace` alongside `PodedgeCore`. App target depends on `PodedgeCore` via local SwiftPM reference.
**Dependencies:** Task 1.5.1

### Task 1.5.3: Rule: No AppKit/SwiftUI in PodedgeCore
Establish (and enforce via a simple `grep` CI check) that PodedgeCore imports only Foundation, SwiftData, AVFoundation, Combine, and third-party non-UI packages. No `import SwiftUI` / `import AppKit`. Keeps the CLI and MCP server usable.
**Dependencies:** Task 1.5.1

### Task 1.5.4: Move Services as They're Built
Subsequent phases create services inside `PodedgeCore/Sources/PodedgeCore/Services/` rather than the app target. UI layer stays in the app target. Update Phase 2–12 file paths accordingly (implicit; doc-level reminder).
**Dependencies:** Task 1.5.1–1.5.3

## Phase 2: Domain Model

### Task 2.1: Define SwiftData Models
**Files to create:** `Models/Show.swift`, `Models/Episode.swift`, `Models/Asset.swift`, `Models/HostBinding.swift`, `Models/AnalyticsBinding.swift`, `Models/DistributionRecord.swift`, `Models/Job.swift`, `Models/AnalyticsSnapshot.swift`
**Reference:** section 4 of the technical design.
**Dependencies:** Task 1.1

### Task 2.2: Define Enums & Value Types
**Files to create:** `Models/EpisodeStatus.swift`, `Models/EpisodeType.swift`, `Models/JobKind.swift`, `Models/JobState.swift`, `Models/HostKind.swift`, `Models/DistributionStatus.swift`, `Models/AssetKind.swift`, `Models/PodedgeError.swift`
**Dependencies:** Task 2.1

### Task 2.3: LibraryStore Facade
**File:** `Services/LibraryStore.swift`
**Responsibilities:** typed CRUD wrappers around `ModelContext`, observable collections.
**Dependencies:** Task 2.1, 2.2

### Task 2.4: LibraryStore Tests
**File:** `PodedgeTests/LibraryStoreTests.swift`
**Dependencies:** Task 2.3

## Phase 2.5: Action Layer (Tool Broker)

The Action Layer makes every capability invocable identically from UI and the future Assistant. Worth building in v1 because adding it later means retrofitting every button.

### Task 2.5.1: Define Tool & ToolBroker
**Files:** `Extensions/Tool.swift`, `Services/ToolBroker.swift`
`Tool<Input, Output>` struct, `ToolScope` enum, `CapabilityTier` enum, `ToolCaller` enum, broker with `execute(toolID:input:caller:)` and `list(scope:)`. See technical design §16.
**Dependencies:** Task 2.3

### Task 2.5.2: AuditLog Service
**File:** `Services/AuditLog.swift`
New `@Model AgentAuditEntry` (per technical design; shared with agent-access v1.2+). Redaction of sensitive arguments. Persistent retention (default 90 days).
**Dependencies:** Task 2.5.1

### Task 2.5.3: Destructive-Action Confirmation Sheet
**File:** `UI/Components/ConfirmationSheetView.swift` + `Services/ConfirmationCoordinator.swift`
Shared UI surface for destructive tool confirmations — used by both UI buttons and future Assistant invocations. Shows human-language summary + specific changes + Confirm/Cancel.
**Dependencies:** Task 2.5.1

### Task 2.5.4: Tool Registry
**File:** `Services/ToolRegistry.swift`
Central registration point for tools. Each later phase registers its own tools here as it builds them. Broker reads from the registry.
**Dependencies:** Task 2.5.1

### Task 2.5.5: ToolButton SwiftUI Helper
**File:** `UI/Components/ToolButton.swift`
Wraps a tool invocation, pulls display metadata from the tool definition, manages loading/error states. Replaces ad-hoc buttons everywhere — the UI calls tools, not services, for anything that's an action.
**Dependencies:** Task 2.5.1, 2.5.3

### Task 2.5.6: Tool & Broker Tests
**File:** `PodedgeTests/ToolBrokerTests.swift`
Scope enforcement, destructive confirmation flow, audit entries, rate limits (stubbed).
**Dependencies:** Task 2.5.1–2.5.5

**Note for all subsequent phases:** services built in Phases 5–12 register their capabilities as tools in `ToolRegistry` as part of their task. UI views consume those tools via `ToolButton`. No extra phase for "wire up tools" — it happens inline.

## Phase 3: Extension Points (Protocols)

### Task 3.1: Define AudioPipeline Protocol + PassthroughPipeline
**Files:** `Extensions/AudioPipeline.swift`, `Extensions/PassthroughPipeline.swift`
**PassthroughPipeline does:** sha256, probe (AVFoundation `AVAsset` + frame scan), waveform peaks, ID3 read, optional ID3 rewrite with cover + chapters.
**Dependencies:** Task 2.1

### Task 3.2: Define PodcastHost Protocol
**File:** `Extensions/PodcastHost.swift`
**Dependencies:** Task 2.1

### Task 3.3: Define TranscriptionEngine Protocol
Vendor or adapt from wispr. Same interface.
**Files:** `Extensions/TranscriptionEngine.swift` + the vendored engine implementations.
**Dependencies:** Task 1.3

### Task 3.4: Define LLMProvider Protocol
**File:** `Extensions/LLMProvider.swift`
**Dependencies:** None

### Task 3.5: Define DistributionTarget Protocol
**File:** `Extensions/DistributionTarget.swift`
**Dependencies:** Task 2.1

### Task 3.6: Define PromotionRenderer Protocol
**File:** `Extensions/PromotionRenderer.swift`
**Dependencies:** None

### Task 3.7: Define AnalyticsProvider Protocol
**File:** `Extensions/AnalyticsProvider.swift`
**Dependencies:** Task 2.1

## Phase 4: Infrastructure Services

### Task 4.1: Logger with Redaction
**File:** `Utilities/Logger.swift`
Pattern-match and redact query params and auth headers.
**Dependencies:** None

### Task 4.2: KeychainService
**File:** `Services/KeychainService.swift`
Typed accessors: `s3(bindingID:)`, `op3ApiKey()`, `podcastIndex()`.
**Dependencies:** None
**Tests:** `PodedgeTests/KeychainServiceTests.swift`

### Task 4.3: JobScheduler
**File:** `Services/JobScheduler.swift`
Durable queue backed by `Job` rows. Supports dependencies, retries with exponential backoff, cancellation, resume on launch. Heavy inspiration from wispr's `StateManager`.
**Dependencies:** Task 2.1, 4.1

### Task 4.4: JobScheduler Tests
**File:** `PodedgeTests/JobSchedulerTests.swift`
**Dependencies:** Task 4.3

## Phase 5: Ingest Pipeline

### Task 5.1: MP3 Validator
**File:** `Services/MP3Validator.swift`
MPEG frame sanity, MIME sniff, reject non-MP3.
**Dependencies:** Task 2.2

### Task 5.2: Audio Prober
**File:** `Services/AudioProber.swift`
AVFoundation-based: duration (frame scan, not header), bitrate, channels, sample rate, LUFS estimate.
**Dependencies:** Task 5.1

### Task 5.3: Waveform Generator
**File:** `Services/WaveformGenerator.swift`
1000-sample peak array, stored as `.wfm` binary file.
**Dependencies:** Task 5.2

### Task 5.4: ID3 Tag Reader/Writer
**File:** `Services/ID3TagService.swift`
Options: use `ID3TagEditor` Swift package or hand-roll. Read/write title, artist, album, cover (APIC), chapters (CHAP/CTOC).
**Dependencies:** Task 5.1

### Task 5.5: IngestService
**File:** `Services/IngestService.swift`
Orchestrates: copy to sandbox → validate → hash → probe → waveform → ID3 read → enqueue transcription + metadata generation jobs.
**Dependencies:** Task 3.1, 4.3, 5.1–5.4

### Task 5.6: IngestService Tests
**File:** `PodedgeTests/IngestServiceTests.swift`
Fixture MP3s: short/long, mono/stereo, tagged/untagged, corrupted.
**Dependencies:** Task 5.5

## Phase 6: Local AI

### Task 6.1: TranscriptionService
**File:** `Services/TranscriptionService.swift`
Wraps `TranscriptionEngine`. Produces transcript with word-level timestamps, saves as VTT and plain text.
**Dependencies:** Task 3.3

### Task 6.2: Model Management (reuse from wispr)
**Files:** `Services/ModelManager.swift`, `UI/ModelManagementView.swift`
Download progress, storage management, integrity checks.
**Dependencies:** Task 6.1

### Task 6.3: LLMProvider Implementation (MLX)
**File:** `LLM/MLXLLMProvider.swift`
**Dependencies:** Task 3.4, 1.3

### Task 6.4: Prompt Library
**Files:** `Resources/Prompts/episode-metadata.md`, `chapters.md`, `social-blurbs.md`
Variables: `{{transcript}}`, `{{show_title}}`, `{{episode_number}}`.
**Dependencies:** None

### Task 6.5: LLMService
**File:** `Services/LLMService.swift`
Loads prompt templates, renders variables, calls provider with JSON schema for structured output.
**Dependencies:** Task 6.3, 6.4

### Task 6.6: Metadata Generation Job
**File:** `Services/MetadataGenerationService.swift`
Given a transcribed episode → produce title/subtitle/description/chapters/keywords/social-blurbs. Stores suggestions on the Episode as editable drafts.
**Dependencies:** Task 6.1, 6.5

### Task 6.7: Transcription + Metadata Tests
**Files:** `PodedgeTests/TranscriptionServiceTests.swift`, `MetadataGenerationServiceTests.swift`
Mock engine + provider for determinism.
**Dependencies:** Task 6.1, 6.6

## Phase 7: S3 Host

### Task 7.1: S3Host Implementation
**File:** `Hosts/S3Host.swift`
AWS SDK for Swift. Multipart upload (8MB parts), HEAD-before-PUT idempotency, progress callback.
**Dependencies:** Task 3.2, 4.2

### Task 7.2: HostService
**File:** `Services/HostService.swift`
Resolves `HostBinding` → concrete `PodcastHost`, handles retries, logging.
**Dependencies:** Task 7.1

### Task 7.3: S3 Credentials UI
**File:** `UI/Settings/HostBindingEditorView.swift`
Form: name, bucket, region, prefix, public base URL, access key, secret. Test-connection button before save.
**Dependencies:** Task 7.2

### Task 7.4: S3 Tests
**File:** `PodedgeTests/S3HostTests.swift`
Use a URLProtocol stub or LocalStack in a GitHub Action.
**Dependencies:** Task 7.1

## Phase 8: Feed Generation

### Task 8.1: RSSFeed Value Types
**Files:** `Models/RSSFeed.swift`, `RSSChannel.swift`, `RSSItem.swift`
Pure Swift value types mapping 1:1 to the XML model.
**Dependencies:** Task 2.1

### Task 8.2: FeedBuilder
**File:** `Services/FeedBuilder.swift`
`Show` + `[Episode]` → `RSSFeed`. Calls `AnalyticsProvider.prefix(enclosureURL:)` if show has analytics binding.
**Dependencies:** Task 8.1, 3.7

### Task 8.3: RSS XML Serializer
**File:** `Services/FeedXMLSerializer.swift`
`RSSFeed` → `Data` via `XMLDocument`.
**Dependencies:** Task 8.1

### Task 8.4: Feed Validator
**File:** `Services/FeedValidator.swift`
Required fields, GUID uniqueness, enclosure URL reachability (HEAD), artwork dimensions, pubDate RFC 822, size cap.
**Dependencies:** Task 8.3

### Task 8.5: FeedBuilder Tests (Golden-File)
**File:** `PodedgeTests/FeedBuilderTests.swift`
Fixture shows → compare produced XML against committed golden files.
**Dependencies:** Task 8.2, 8.3

## Phase 9: OP3 Analytics

### Task 9.1: OP3AnalyticsProvider
**File:** `Analytics/OP3AnalyticsProvider.swift`
`register(show:)`, `prefix(enclosureURL:)`, `fetchSnapshot(show:since:)`.
**Dependencies:** Task 3.7, 4.2

### Task 9.2: AnalyticsService
**File:** `Services/AnalyticsService.swift`
Periodic (6h) polling, snapshot persistence, observable streams for UI.
**Dependencies:** Task 9.1

### Task 9.3: OP3 Tests
**File:** `PodedgeTests/OP3AnalyticsProviderTests.swift`
URLProtocol stubs for OP3 API.
**Dependencies:** Task 9.1

## Phase 10: Distribution

### Task 10.1: PodcastIndexTarget
**File:** `Distribution/PodcastIndexTarget.swift`
API submission with auth-hash auth scheme.
**Dependencies:** Task 3.5

### Task 10.2: PodpingTarget
**File:** `Distribution/PodpingTarget.swift`
Notify on publish. Uses hivemind/Podping.cloud webhook or Hive-native posting depending on choice at implementation time.
**Dependencies:** Task 3.5

### Task 10.3: Guided Targets (Apple, Spotify, Amazon)
**Files:** `Distribution/ApplePodcastsTarget.swift`, `SpotifyTarget.swift`, `AmazonMusicTarget.swift`
`submit` opens the appropriate submission URL; UI captures paste-back IDs.
**Dependencies:** Task 3.5

### Task 10.4: DistributionService
**File:** `Services/DistributionService.swift`
Registry of targets, fan-out on publish for `.api` mode, status refresh.
**Dependencies:** Task 10.1–10.3

### Task 10.5: Distribution Tests
**File:** `PodedgeTests/DistributionServiceTests.swift`
**Dependencies:** Task 10.4

## Phase 11: Publish Pipeline

### Task 11.1: PublishArtifactBuilder
**File:** `Services/PublishArtifactBuilder.swift`
Decides original vs tag-rewritten copy. If rewrite enabled: copy → embed cover + chapters → write to `published.mp3`.
**Dependencies:** Task 3.1, 5.4

### Task 11.2: PublishService
**File:** `Services/PublishService.swift`
Full pipeline per section 6 of the design doc. Resumable via JobScheduler.
**Dependencies:** Task 7.2, 8.2, 9.2, 10.4, 11.1

### Task 11.3: Publish Dry-Run
**File:** `Services/PublishDryRun.swift`
Emits a plan without side-effects: list of uploads, feed diff, distribution notifications.
**Dependencies:** Task 11.2

### Task 11.4: Publish Tests
**File:** `PodedgeTests/PublishServiceTests.swift`
Mock host + mock distribution + mock analytics. Verify order, idempotency, resume.
**Dependencies:** Task 11.2

## Phase 12: Promotion

### Task 12.1: SocialBlurbRenderer
**File:** `PromotionRenderers/SocialBlurbRenderer.swift`
Per-platform variants: X (280 chars), Bluesky (300), Mastodon (500), LinkedIn, Threads. Uses LLMService.
**Dependencies:** Task 3.6, 6.5

### Task 12.2: Promotion UI Tab
**File:** `UI/Episode/PromotionTabView.swift`
Show generated blurbs with copy buttons. Regenerate action.
**Dependencies:** Task 12.1

## Phase 12.5: Assistant (v1.1)

The in-app Assistant: dockable pane + ⌘K, router, specialist agents, all driving the Action Layer from Phase 2.5. See `agentic-assistant.md` for full design.

**Note:** This phase is v1.1, not v1. Listed here (not in Phase 15) because it's the anchor feature of the "AI-native" story; when v1.1 work begins, this is where it slots.

### Task 12.5.1: Extend LLMProvider with Tool-Use
**Files:** `Extensions/LLMProvider.swift` (modify), `Models/LLMProviderCapabilities.swift`, `Models/LLMStreamEvent.swift`, `Models/ToolDefinition.swift`
Per technical design §10.5. Each existing provider (MLX, Ollama, Anthropic, OpenAI, OpenAI-compatible) must declare its tool-use capabilities and translate `ToolDefinition`s to its native format; prompt-emulated fallback when native is absent.
**Dependencies:** Task 3.4, 15.F.1–15.F.4

### Task 12.5.2: CapabilityTier Service
**File:** `Services/CapabilityTierService.swift`
Maps `LLMBinding` → `CapabilityTier` using a bundled known-models table. Unknowns default to T3. Surfaces warnings when an agent's minimum tier exceeds the configured binding.
**Dependencies:** Task 2.5.1, 15.F.5

### Task 12.5.3: Router
**File:** `Agents/Router.swift`
Rule-based keyword pass first (`/promote`, `/analyze`, `/debug`, etc.). LLM classifier fallback (one call, constrained output to agent-ID). Confidence threshold for clarifying-question flow.
**Dependencies:** Task 12.5.1

### Task 12.5.4: AssistantController
**File:** `Services/AssistantController.swift`
Conversation orchestrator: user utterance → router → specialist → tool calls via `ToolBroker` → response streaming. Fresh conversation per ⌘K invocation.
**Dependencies:** Task 12.5.3, 2.5.1

### Task 12.5.5: PromoterAgent
**Files:** `Agents/PromoterAgent.swift`, `Resources/Agents/promoter.md`
Tool whitelist: library read, LLM generate, social read/compose/post (destructive). Min tier T3, T2 recommended. Max iterations 8. Reads per-show `promotion-guide.md`.
**Dependencies:** Task 12.5.4, 12.1

### Task 12.5.6: AnalystAgent
**Files:** `Agents/AnalystAgent.swift`, `Resources/Agents/analyst.md`
Read-only analytics tools + chart rendering. Max iterations 12. Reads `analytics-queries.md`.
**Dependencies:** Task 12.5.4, 9.2

### Task 12.5.7: QueryResolverAgent
**Files:** `Agents/QueryResolverAgent.swift`, `Resources/Agents/query-resolver.md`
Library read-only, shallow (max iterations 4). "What is / where is / list" queries.
**Dependencies:** Task 12.5.4

### Task 12.5.8: FeedDebuggerAgent
**Files:** `Agents/FeedDebuggerAgent.swift`, `Resources/Agents/feed-debugger.md`
Read-only feed + validator + distribution status. Propose-only. Max iterations 6.
**Dependencies:** Task 12.5.4, 8.4

### Task 12.5.9: PublishAssistantAgent
**Files:** `Agents/PublishAssistantAgent.swift`, `Resources/Agents/publish-assistant.md`
Guided publish flow with explicit UI confirmation at each step. Max iterations 6. Destructive `publish.execute` tool goes through the standard confirmation sheet.
**Dependencies:** Task 12.5.4, 11.2

### Task 12.5.10: Shared Agent Resources
**Files:** `Resources/Agents/_safety.md`, `Resources/Agents/_escape-hatch.md`, `Resources/Agents/router.md`
Untrusted-content handling, no-instruction-following, failure-response template, router system prompt + few-shot examples.
**Dependencies:** Task 12.5.3

### Task 12.5.11: Config-as-Memory Loader
**Files:** `Services/PerShowGuidesService.swift`, Tool `podedge.content.read_guide`
Loads `voice-guide.md`, `promotion-guide.md`, `analytics-queries.md` from `~/Library/Application Support/Podedge/Shows/<show-id>/`. Exposed as a tool so agent invocations show up in audit log.
**Dependencies:** Task 2.5.1

### Task 12.5.12: AssistantPaneView
**Files:** `UI/Assistant/AssistantPaneView.swift`, `UI/Assistant/AssistantMessageView.swift`, `UI/Assistant/ToolCallRowView.swift`
Conversation rendering, input field, provider+model labels, expandable tool-call rows.
**Dependencies:** Task 12.5.4

### Task 12.5.13: Suggestion Rail
**File:** `UI/Assistant/SuggestionRailView.swift`
Context-sensitive "Try asking…" suggestions. Templated from tool catalog + current selection + recent activity. No LLM call.
**Dependencies:** Task 12.5.12, 2.5.1

### Task 12.5.14: /capabilities Slash Command
**File:** `UI/Assistant/CapabilitiesMenuView.swift`
Categorized human-readable tool listing sourced from `ToolRegistry`.
**Dependencies:** Task 12.5.12

### Task 12.5.15: ⌘K Global Shortcut + Pane Visibility
**Files:** `UI/Assistant/AssistantShortcut.swift`, integrate into `MainWindowView`
Fresh conversation on each ⌘K. Pane hide/show, remember preference. First-launch default visible. Open main window as side-effect if closed.
**Dependencies:** Task 12.5.12, 13.1

### Task 12.5.16: Rate Limits & Budget Enforcement
**File:** `Services/AssistantBudgetService.swift`
Per-session caps: tool calls/min, tool calls/hour, destructive/hour, LLM-token budget for metered providers, estimated-cost cap. Warnings at 50%, hard stops at 100%.
**Dependencies:** Task 2.5.1, 15.F.6

### Task 12.5.17: Escape-Hatch Responder
**File:** `Services/AssistantEscapeHatch.swift`
Composes failure responses with deep-links to the manual UI path and to Settings → LLM Providers. Invoked by AssistantController when an agent exhausts retries or capability tier is insufficient.
**Dependencies:** Task 12.5.4

### Task 12.5.18: Assistant Settings UI
**File:** `UI/Settings/AssistantSettingsView.swift`
Pane visibility default, "always propose never execute" toggle, per-agent model overrides, rate-limit tuning, custom-prompts toggle.
**Dependencies:** Task 12.5.4, 15.F.8

### Task 12.5.19: Audit Log View
**File:** `UI/Settings/AuditLogView.swift`
Lists `AgentAuditEntry` rows (caller UI/agent, tool, arguments redacted, outcome, duration, provider+model). Filter, export JSONL.
**Dependencies:** Task 2.5.2

### Task 12.5.20: Assistant Tests
**Files:** `PodedgeTests/RouterTests.swift`, `PodedgeTests/AssistantControllerTests.swift`, per-agent tests.
Mock LLM providers with scripted tool calls. Verify scope enforcement, confirmation flow, rate limits, escape-hatch responses.
**Dependencies:** All above

## Phase 13: UI

### Task 13.1: MainWindowView (NavigationSplitView)
**File:** `UI/Main/MainWindowView.swift`
Three panes: ShowList → EpisodeList → EpisodeEditor.
**Dependencies:** Task 2.3

### Task 13.2: ShowListView / ShowEditorView
**Files:** `UI/Main/ShowListView.swift`, `UI/Main/ShowEditorView.swift`
**Dependencies:** Task 13.1

### Task 13.3: EpisodeListView
**File:** `UI/Episode/EpisodeListView.swift`
Status pill, inline play, drag-drop MP3 to create.
**Dependencies:** Task 13.1, 5.5

### Task 13.4: EpisodeEditorView
**File:** `UI/Episode/EpisodeEditorView.swift`
Tabs: Metadata, Transcript/Chapters, Promotion, Publish.
**Dependencies:** Task 13.3, 12.2

### Task 13.5: FeedPreviewView
**File:** `UI/Main/FeedPreviewView.swift`
XML syntax highlight, validation warnings, diff-against-last-published.
**Dependencies:** Task 8.2, 8.4

### Task 13.6: AnalyticsView
**File:** `UI/Main/AnalyticsView.swift`
SwiftCharts over AnalyticsSnapshot.
**Dependencies:** Task 9.2

### Task 13.7: MenuBarController + MenuBarContentView
**File:** `UI/MenuBarController.swift`, `UI/MenuBarContentView.swift`
Job progress, quick new-episode, open main window, quit.
**Dependencies:** Task 4.3

### Task 13.8: SettingsView
**File:** `UI/Settings/SettingsView.swift`
Tabs: General, Hosts, Analytics, Models, Distribution, About.
**Dependencies:** Task 7.3, 9.1, 6.2

### Task 13.9: OnboardingView
**File:** `UI/Onboarding/OnboardingView.swift`
Stepper: welcome → create first show → S3 creds → OP3 key (optional) → model download → done.
**Dependencies:** Task 13.2, 7.3, 9.1, 6.2

## Phase 14: Integration & Polish

### Task 14.1: End-to-End Tests
**File:** `PodedgeTests/EndToEndIntegrationTests.swift`
Drop fixture MP3 → transcribe (mock) → generate metadata (mock) → publish to mock host → verify feed on "host" → verify distributions called.
**Dependencies:** Task 11.2

### Task 14.2: Notifications
**File:** `Services/NotificationService.swift`
UserNotifications for publish success/failure, long-running jobs.
**Dependencies:** Task 4.3

### Task 14.3: Update Checker (reuse wispr)
**File:** `Services/UpdateChecker.swift`
**Dependencies:** None

### Task 14.4: Accessibility Pass
VoiceOver labels, keyboard navigation across all views.
**Dependencies:** Task 13.*

### Task 14.5: Log Export UI
**File:** `UI/Settings/DiagnosticsView.swift`
Export redacted logs as .zip.
**Dependencies:** Task 4.1

### Task 14.6: Signing, Notarization, DMG
**Files:** `Makefile`, `ExportOptions.plist`
Copy wispr's patterns.
**Dependencies:** All prior

## Phase 15: Deferred (Specified, Not Built in v1)

These have their own design docs. Expanded task lists below so we know what's coming.

### 15.A Import Existing Show
See `import-existing-show.md`. Key tasks: `FeedImporter`, `iTunesLookupClient`, `EnclosureDownloader`, `OP3Detector`, `FeedDiffer`, `CutoverAssistant`, plus `ImportSession` model + `managementMode` field on Show.

### 15.B Audiograms & Quote Cards
- `AudiogramRenderer` — AVFoundation composition (cover + waveform + transcript karaoke). Output MP4, 9:16 / 1:1 / 16:9.
- `QuoteCardRenderer` — SwiftUI → PNG, templated. LLM surfaces quote candidates; user picks.
- Promotion tab UI additions.

### 15.C Scheduled Publishing
- `BGTaskScheduler` wiring for publish-at-time.
- Scheduled-publish UI (date picker, queue view).
- Handle wake-from-sleep + user-notification-on-publish.

### 15.D Additional Hosts
- `R2Host`, `B2Host`, `DOSpacesHost` — all S3-compatible, thin wrappers over a shared `S3CompatibleHost`.
- `SFTPHost` — libssh2 or `mft` Swift package.
- `WebDAVHost` — URLSession + WebDAV verbs.
- Host-binding UI per kind.

### 15.E Advanced Audio Pipelines
- `NormalizePipeline` — LUFS normalize, true-peak limit.
- `SilenceTrimPipeline` — head/tail auto-trim.
- `FillerRemovalPipeline` — uses Whisper word timestamps + crossfades.
- `DenoisePipeline` — Apple Voice Isolation AU / RNNoise / DeepFilterNet options.
- `ChainedPipeline` — compose above in order, via show-level config.
- Preview/compare UI (A/B, waveform diff).

### 15.F Bring Your Own AI — Provider Implementations
Each provider is a new file implementing `LLMProvider`; no changes to call sites.

- **Task 15.F.1: OllamaLLMProvider** — `LLM/OllamaLLMProvider.swift`. HTTP client against `/api/chat` (streaming) and `/api/generate`. Auto-discover running models via `/api/tags`. No credentials.
- **Task 15.F.2: AnthropicLLMProvider** — `LLM/AnthropicLLMProvider.swift`. Messages API with streaming (SSE). Tool-use for schema-constrained outputs. Keychain-stored `anthropic.apiKey`.
- **Task 15.F.3: OpenAILLMProvider** — `LLM/OpenAILLMProvider.swift`. Chat Completions + Responses API. JSON mode + tool-use. Keychain-stored `openai.apiKey`.
- **Task 15.F.4: OpenAICompatibleLLMProvider** — `LLM/OpenAICompatibleLLMProvider.swift`. Generic `baseURL + apiKey`. Used for Groq, Together, Fireworks, LM Studio, LiteLLM, vLLM. Stored per-instance `HostedProviderBinding`.
- **Task 15.F.5: LLMRouter** — `Services/LLMRouter.swift`. Resolves `(taskKind, show) → LLMBinding → provider`. Applies `keepOnDevice`. Retry/backoff. Offline fallback per user preference.
- **Task 15.F.6: LLMCallLog & Cost Accounting** — new `@Model LLMCallLog` (timestamp, provider, model, taskKind, inputTokens, outputTokens, estimatedCostUSD, latencyMs). Pricing table bundled in `Resources/LLMPricing.json`.
- **Task 15.F.7: Consent & Privacy UI** — sheet on first cloud-provider use per provider. Per-show `keepOnDevice` toggle. Global "disable cloud providers" in Settings. Provider+model label shown next to every AI suggestion. Wire at `LLMRouter` entry point.
- **Task 15.F.8: Provider Settings UI** — `UI/Settings/LLMProvidersView.swift`. List providers, test connection, manage credentials, pick default model per provider.
- **Task 15.F.9: Routing Settings UI** — `UI/Settings/LLMRoutingView.swift`. Matrix of `taskKind × binding`. Preset profiles (all-local, mixed, all-Claude, etc.).
- **Task 15.F.10: Provider Tests** — one test file per provider with URLProtocol stubs + fixture responses.

### 15.G Command-Line Interface (`podedge-cli`)
- **Task 15.G.1: CLI Target** — `podedge-cli/` executable, `swift-argument-parser` dependency, links `PodedgeCore`.
- **Task 15.G.2: Library Access Strategy** — SQLite WAL mode on the shared SwiftData store for v1.1; document the concurrent-access constraints. Plan for XPC-based CLI-client in a future version if WAL contention becomes an issue.
- **Task 15.G.3: Command Surface** — subcommands:
  - `show list | create | edit | delete | show | import`
  - `episode list | add | edit | delete | show | transcribe | publish | unpublish`
  - `feed build | validate | preview`
  - `stats pull | show`
  - `host list | add | test | remove`
  - `config get | set` (incl. LLM routing)
  - `job list | cancel | retry`
- **Task 15.G.4: Output Formatting** — detect TTY: human-readable table output when interactive, JSON when piped. `--output json|table|yaml` override.
- **Task 15.G.5: `--dry-run` Flag** — honored on publish/unpublish/delete/import.
- **Task 15.G.6: Man Pages & Shell Completions** — generated via `swift-argument-parser` helpers. Installed by a `podedge cli install` command (mirrors wispr-cli).
- **Task 15.G.7: CLI Integration Tests** — end-to-end tests invoking the binary against a fixture library.

### 15.H Agent Access via External MCP (v1.2+)
See `agent-access.md` for full design. **Re-scoped:** the in-app Assistant (Phase 12.5) is now the v1.1 priority; exposing Podedge to *external* agents via MCP moves to v1.2+. The v1 Action Layer (Phase 2.5) means this phase is now mostly a transport wrapper — tools already exist, audit already exists, confirmation flow already exists.

- **Task 15.H.1: AgentSession Model** — `@Model AgentSession` (clientName, grantedScopes, allowedShowIDs, mode read/write/publish, createdAt, lastSeenAt, revokedAt).
- **Task 15.H.2: External Tool Filter** — filter `ToolRegistry` for tools safe to expose externally (same catalog as in-app Assistant; a handful of internal-only tools excluded).
- **Task 15.H.3: Resource Catalog** — `Agents/PodedgeResources.swift` exposing `podedge://shows/{id}`, `podedge://episodes/{id}/transcript`, `podedge://feed/{showId}`. Read-only.
- **Task 15.H.4: Confirmation Token Flow** — already in the ToolBroker; external callers use it unchanged. Tokens single-use, TTL 5 min.
- **Task 15.H.5: MCPServerInterface** — `Agents/MCPServerInterface.swift`, Swift MCP SDK. Stdio transport for Claude Desktop; HTTP+SSE for networked clients.
- **Task 15.H.6: `podedge-agent` Executable** — separate executable target launching an MCP server in stdio mode. Install via `podedge-cli agent install --client claude-desktop`.
- **Task 15.H.7: Pairing UI** — `UI/Settings/AgentPairingView.swift`. Consent sheet per new client with scopes + allowed shows.
- **Task 15.H.8: External-Agent Audit Filter** — the audit log already captures every tool call; add a view filter for agent-originated entries.
- **Task 15.H.9: Revoke Flow** — one-click revoke per session. In-flight calls cancelled; Keychain entries wiped.
- **Task 15.H.10: A2A Interface** — stub `Agents/A2AInterface.swift` + spec tracker doc. Implement when spec stabilizes.

### 15.I Phase-Dependency Update
`PodedgeCore` (Phase 1.5) is a prerequisite for 15.F, 15.G, 15.H. The rest of Phase 15 depends only on v1.

## Phase Dependency Summary

```
1 → 1.5 → 2 → 2.5 → 3 → 4 → 5 ──┐
                          └── 6 ┤
                          └── 7 ┤
                               ├─ 8 ─┤
                               ├─ 9 ─┤
                               └─ 10 ┤
                                    ├── 11 → 12 → 13 → 14
                                              │
                                              └── 12.5 (v1.1 Assistant)
```

Phases 5, 6, 7 can run in parallel after Phase 4. Phase 11 (publish) joins them.
Phase 1.5 (`PodedgeCore` split) blocks everything else but is small (~1 day) and unlocks 15.F, 15.G, 15.H with zero refactor.
Phase 2.5 (Action Layer) is a v1 prerequisite for the Assistant; every subsequent phase registers its capabilities as tools inline.
Phase 12.5 (Assistant) is v1.1 — the anchor for the AI-native story. Depends on Phase 2.5 plus 15.F (BYO-AI providers for tool-use support).
