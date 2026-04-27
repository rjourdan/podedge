# Podedge - Technical Design Document

## 1. System Architecture Diagram (Text-Based)

```
┌──────────────────────────────────────────────────────────────────┐
│                         Podedge Application                      │
├──────────────────────────────────────────────────────────────────┤
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │   UI Layer     │  │  Service Layer  │  │  System Layer    │   │
│  │                │  │                 │  │                  │   │
│  │ • MainWindow   │  │ • LibraryStore  │  │ • MenuBarCtrl    │   │
│  │ • ShowList     │◄─┤ • IngestService │  │ • Keychain       │   │
│  │ • EpisodeEditor│  │ • JobScheduler  │  │ • Notifications  │   │
│  │ • FeedPreview  │  │ • FeedBuilder   │  │ • URLSession     │   │
│  │ • Analytics    │  │ • PublishService│  │ • BGTaskSched.   │   │
│  │ • Onboarding   │  │ • LLMService    │  │                  │   │
│  │ • Settings     │  │ • Transcription │  │                  │   │
│  └────────────────┘  └─────────────────┘  └──────────────────┘   │
│           │                   │                    │             │
│           └───────────────────┼────────────────────┘             │
│                               │                                  │
├───────────────────────────────┼──────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                Pluggable Extension Points                  │  │
│  │ AudioPipeline │ PodcastHost │ TranscriptionEngine │        │  │
│  │ LLMProvider   │ Distribution│ PromotionRenderer   │        │  │
│  │ AnalyticsProvider                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                     SwiftData Models                       │  │
│  │ Show • Episode • Asset • HostBinding • FeedConfig • Job    │  │
│  │ PromotionArtifact • AnalyticsSnapshot • Distribution       │  │
│  └────────────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌────────────────┐  ┌────────────────────┐   │
│  │ Local AI      │  │  macOS APIs    │  │   External (HTTPS) │   │
│  │ • whisper.cpp │  │ • AVFoundation │  │ • S3               │   │
│  │ • MLX (LLM)   │  │ • Keychain     │  │ • OP3              │   │
│  │ • WhisperKit  │  │ • SwiftUI      │  │ • Podcast Index    │   │
│  │ • Parakeet    │  │ • SwiftData    │  │ • Podping          │   │
│  └───────────────┘  └────────────────┘  └────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

Mac target: Apple Silicon, macOS 15+. Single-user. Main window + menu bar
accessory. Everything except host uploads, OP3 reads, directory submissions,
and Podping notifications stays on-device.

## 2. Component Breakdown with Responsibilities

### UI Layer

**MainWindow** — Three-pane NavigationSplitView: Shows sidebar → Episodes list → Episode editor. Standard macOS window lifecycle.

**ShowListView / ShowDetailView** — CRUD for shows, cover art drop zone, per-show settings: host binding, OP3 toggle (locked after first publish), distribution statuses.

**EpisodeEditor** — Tabs: Metadata, Transcript/Chapters, Promotion, Publish. Drag-and-drop MP3. Waveform preview. Status pill.

**FeedPreviewView** — Renders the generated RSS XML with syntax highlighting, validation warnings panel, diff-against-last-published view.

**AnalyticsView** — SwiftCharts over cached OP3 snapshots. Show-level and per-episode.

**OnboardingView** — Stepper: welcome → create first show → configure S3 → optional OP3 → download local models → done.

**SettingsView** — Global preferences, credentials management (Keychain-backed), model management, log export, about.

**MenuBarController** — Small menu bar accessory showing current job progress and quick actions (new episode, open main window).

### Service Layer

**LibraryStore** — SwiftData container, CRUD facade over all persistent models. Single source of truth.

**IngestService** — Orchestrates the ingest pipeline for a newly-dropped MP3. Produces an `Episode` in `.processing` state and enqueues the job chain.

**JobScheduler** — Durable job queue (SwiftData-backed). Supports dependencies, retries with backoff, cancellation, resume-across-restarts. Based on wispr's StateManager pattern.

**FeedBuilder** — Value-in / XML-out feed generation. Takes `Show` + published `Episode`s, emits an `RSSFeed` value, serializes to XML via `XMLDocument`, validates locally, returns bytes + sha256.

**PublishService** — Orchestrates the publish pipeline for an episode: upload asset → regenerate feed → upload feed → notify distributions → update analytics subscription.

**TranscriptionService** — Wraps `TranscriptionEngine` protocol; reuses wispr's whisper/Parakeet implementations (vendored as a local Swift package).

**LLMService** — Wraps `LLMProvider` protocol. Templated prompts for: episode metadata, chapter detection, social copy. JSON-schema constrained outputs where possible (MLX supports grammar-constrained decoding).

**AnalyticsService** — Polls OP3, caches `AnalyticsSnapshot`s locally, exposes reactive streams to UI.

**HostService** — Wraps `PodcastHost` protocol. Handles upload retries, multipart, idempotency via sha256-keyed HEAD-before-PUT.

**DistributionService** — Wraps `DistributionTarget` collection. Per-target submit/check/status.

**KeychainService** — Typed accessors for each credential: `s3(bindingID:)`, `op3ApiKey()`, `podcastIndex()`.

### System Layer

**BGTaskCoordinator** — Background task registration for periodic OP3 polling and scheduled publish fire-time (v1.1).

**NotificationService** — UserNotifications wrapper for publish success/failure and background job alerts.

**Logger** — Structured logger with automatic redaction of URLs containing signatures, credentials, and API keys. Mirrors wispr's Logger.

## 3. Extension Points (Protocols)

These are the seams that let v1.1+ features land without rewriting core flows.

### 3.1 AudioPipeline

```swift
protocol AudioPipeline {
    func process(_ input: AudioAsset) async throws -> AudioAsset
}
```

v1 ships exactly one implementation: `PassthroughPipeline`. It computes sha256,
duration, bitrate, channel count, waveform peaks, reads ID3 tags, optionally
writes a tag-rewritten copy for hosting. It does not manipulate samples. Later
implementations (`NormalizePipeline`, `DenoisePipeline`, `FillerRemovalPipeline`)
chain via `ChainedPipeline`.

### 3.2 PodcastHost

```swift
protocol PodcastHost {
    var id: HostBinding.ID { get }
    func put(_ asset: LocalAsset, at remotePath: String, contentType: String,
             progress: @escaping (Double) -> Void) async throws -> URL
    func delete(_ remotePath: String) async throws
    func publicURL(for remotePath: String) -> URL
    func head(_ remotePath: String) async throws -> RemoteMeta?
}
```

v1 ships `S3Host` using AWS SDK for Swift (or URLSession + SigV4 if we want to avoid the SDK size). Supports multipart upload and CDN alias.

### 3.3 TranscriptionEngine

Reused verbatim from wispr: `TranscriptionEngine` protocol, with `WhisperCppEngine`, `ParakeetEngine`, and `CompositeTranscriptionEngine` (automatic fallback). Vendored as a local Swift package so both apps can evolve it together.

### 3.4 LLMProvider

```swift
protocol LLMProvider {
    func complete(_ prompt: Prompt, schema: JSONSchema?) async throws -> LLMResponse
    func stream(_ prompt: Prompt) -> AsyncThrowingStream<String, Error>
}
```

v1 ships one implementation. Candidate: MLX-Swift with a 7–8B instruct model (Llama 3.1 8B Instruct, or Qwen2.5 7B Instruct). Decision at implementation time; wrapping behind the protocol means it's one-file to swap.

### 3.5 DistributionTarget

```swift
protocol DistributionTarget {
    var id: String { get }
    var displayName: String { get }
    var mode: DistributionMode { get } // .api or .guided
    func submit(feedURL: URL, show: Show) async throws -> DistributionSubmission
    func refreshStatus(_ submission: DistributionSubmission) async throws -> DistributionStatus
}
```

v1 implementations:
- `PodcastIndexTarget` (mode `.api`)
- `PodpingTarget` (mode `.api`, technically not a directory but fits the shape)
- `ApplePodcastsTarget` (mode `.guided` — opens Podcasts Connect submission URL, user pastes back the Apple show ID)
- `SpotifyTarget` (mode `.guided`)
- `AmazonMusicTarget` (mode `.guided`)

### 3.6 PromotionRenderer

```swift
protocol PromotionRenderer {
    associatedtype Output
    func render(_ input: PromotionInput) async throws -> Output
}
```

v1 ships `SocialBlurbRenderer` (LLM-driven text, per platform). `AudiogramRenderer` and `QuoteCardRenderer` are spec'd, deferred.

### 3.7 AnalyticsProvider

```swift
protocol AnalyticsProvider {
    func register(show: Show) async throws -> AnalyticsBinding
    func prefix(enclosureURL: URL, for show: Show) -> URL
    func fetchSnapshot(show: Show, since: Date) async throws -> AnalyticsSnapshot
}
```

v1 ships `OP3AnalyticsProvider`. The `prefix` function is called by `FeedBuilder` — that's the only coupling; the feed doesn't know about OP3 specifically.

### 3.8 AgentInterface

Enables external agents (MCP clients, A2A peers) to drive Podedge programmatically. Not used in v1; seam defined now so the `PodedgeCore` package shape is right and services don't leak app-only assumptions.

```swift
protocol AgentInterface {
    var id: String { get }
    var tools: [AgentTool] { get }
    var resources: [AgentResource] { get }
    func invoke(_ toolName: String, arguments: JSONValue,
                session: AgentSession) async throws -> AgentToolResult
    func readResource(_ uri: String, session: AgentSession) async throws -> AgentResourceContent
}
```

v1 ships no implementations. v1.1+ ships `MCPServerInterface` (Anthropic's Model Context Protocol, stdio + HTTP+SSE transports). A2A arrives when its spec stabilizes. All invocations go through the same capability-bounded `AgentSession` so authorization, audit logging, and confirmation tokens are uniform regardless of protocol. See `agent-access.md` for the full design.

## 4. Domain Model (SwiftData)

```swift
@Model final class Show {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var showDescription: String
    var language: String        // RFC 5646, e.g. "en-US"
    var category: String        // iTunes category
    var subcategory: String?
    var explicit: Bool
    var copyright: String?
    var ownerEmail: String
    var ownerName: String
    var coverArtAssetID: UUID?
    var podcastGUID: UUID       // Podcasting 2.0 <podcast:guid>, locked forever
    var podcastLocked: Bool     // <podcast:locked>
    var hostBindingID: UUID
    var feedRemotePath: String  // e.g. "shows/my-show/feed.xml"
    var analyticsBindingID: UUID?  // nil if OP3 disabled
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var episodes: [Episode]
    @Relationship(deleteRule: .cascade) var distributions: [DistributionRecord]
}

@Model final class Episode {
    @Attribute(.unique) var id: UUID
    var show: Show
    var title: String
    var subtitle: String?
    var episodeDescription: String
    var descriptionHTML: String?
    var season: Int?
    var number: Int?
    var type: EpisodeType          // .full, .trailer, .bonus
    var explicit: Bool?
    var guid: String               // locked at creation
    var originalAssetID: UUID
    var publishedAssetID: UUID?    // tag-rewritten copy, if any
    var coverArtAssetID: UUID?     // per-episode override
    var status: EpisodeStatus      // .draft, .processing, .ready, .scheduled, .published, .failed
    var pubDate: Date?
    var scheduledFor: Date?
    var chaptersJSON: String?      // Podcasting 2.0 chapters format
    var transcriptAssetID: UUID?   // hosted transcript file
    var createdAt: Date
    var updatedAt: Date
}

@Model final class Asset {
    @Attribute(.unique) var id: UUID
    var kind: AssetKind             // .audioOriginal, .audioPublished, .coverArt, .transcript, .waveform
    var localURL: URL               // app-sandbox path
    var remotePath: String?         // set after upload
    var remoteURL: URL?             // full public URL after upload
    var sha256: String
    var byteSize: Int64
    var contentType: String
    var durationSeconds: Double?    // audio only
    var createdAt: Date
}

@Model final class HostBinding {
    @Attribute(.unique) var id: UUID
    var kind: HostKind              // .s3 (v1); .r2, .b2, .sftp later
    var displayName: String
    var bucket: String
    var region: String
    var prefix: String
    var publicBaseURL: URL          // e.g. CloudFront alias or bucket URL
    var keychainRef: String         // opaque handle, value lives in Keychain
    var createdAt: Date
}

@Model final class AnalyticsBinding {
    @Attribute(.unique) var id: UUID
    var provider: String            // "op3"
    var externalShowID: String?     // OP3 show UUID
    var prefixBaseURL: URL          // e.g. https://op3.dev/e
    var keychainRef: String?
    var createdAt: Date
}

@Model final class DistributionRecord {
    @Attribute(.unique) var id: UUID
    var show: Show
    var targetID: String            // "apple", "spotify", "podcast-index", etc.
    var status: DistributionStatus
    var externalShowID: String?     // Apple/Spotify show ID after paste-back
    var submittedAt: Date?
    var lastCheckedAt: Date?
    var note: String?
}

@Model final class Job {
    @Attribute(.unique) var id: UUID
    var kind: JobKind               // .ingest, .transcribe, .generateMetadata, .upload, .publish, .op3Poll
    var targetID: UUID              // episode or show id
    var state: JobState             // .pending, .running, .done, .failed, .cancelled
    var attempts: Int
    var createdAt: Date
    var startedAt: Date?
    var finishedAt: Date?
    var parentJobID: UUID?
    var payloadJSON: String?        // kind-specific
    var errorMessage: String?
}

@Model final class AnalyticsSnapshot {
    @Attribute(.unique) var id: UUID
    var show: Show
    var episode: Episode?
    var capturedAt: Date
    var windowStart: Date
    var windowEnd: Date
    var downloads: Int
    var uniqueListeners: Int
    var appsJSON: String            // { "Apple Podcasts": 420, ... }
    var geosJSON: String            // { "US": 600, ... }
}
```

## 5. Ingest Pipeline (Stages)

When a user drops an MP3:

1. **Validate** — MIME sniff, MPEG frame sanity check, reject non-MP3 with clear error.
2. **Copy to library** — move into app sandbox (`~/Library/Containers/.../Audio/<episode-id>/original.mp3`).
3. **Hash** — SHA256 of file bytes.
4. **Probe** — duration (frame scan, not just header), bitrate, channels, sample rate, LUFS (display only).
5. **Waveform** — 1000-sample peak array, stored as a small binary `.wfm` file.
6. **Read ID3** — existing tags surfaced in the editor for user review.
7. **Transcribe** — background, whisper/Parakeet via `TranscriptionEngine`.
8. **Generate metadata** — LLM produces title/subtitle/description/chapters/SEO suggestions.
9. **Ready** — episode status transitions to `.ready`.

Each stage is a `Job` row. Users can pause/resume. Crash-safe: on launch, scheduler resumes `.running` jobs that didn't complete.

## 6. Publish Pipeline (Stages)

1. **Prepare publish artifact** — if show has "rewrite tags" enabled, produce tag-rewritten copy with cover + chapters embedded; otherwise use original.
2. **Upload audio** — via `PodcastHost.put` to `shows/<slug>/<episode-id>.mp3`. Idempotent: `head` first, skip if sha256 matches.
3. **Upload transcript** — if transcript exists, upload as VTT and/or SRT to `shows/<slug>/transcripts/<episode-id>.vtt`.
4. **Upload chapters** — if chapters exist, upload as Podcasting 2.0 chapters JSON.
5. **Regenerate feed** — `FeedBuilder.build(show:)` over all `.published` episodes plus this one.
6. **Upload feed** — `PodcastHost.put` to `feedRemotePath` with `Content-Type: application/rss+xml`, `Cache-Control: public, max-age=300`.
7. **Distribution notify** — fan-out to all `DistributionTarget` in `.api` mode (Podcast Index, Podping). `.guided` targets are unaffected on each publish.
8. **Update state** — episode → `.published`, pubDate = now (or `scheduledFor`).
9. **Enqueue OP3 poll** — first AnalyticsService fetch 24h out (configurable).

## 7. RSS Feed Generation

`FeedBuilder` produces an immutable `RSSFeed` value type, then serializes via Foundation's `XMLDocument`. No string concatenation — too risky with user-supplied content.

Feed structure:

```
<rss version="2.0"
     xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
     xmlns:podcast="https://podcastindex.org/namespace/1.0"
     xmlns:atom="http://www.w3.org/2005/Atom"
     xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>, <link>, <description>, <language>, <copyright>
    <atom:link rel="self" href="..."/>
    <itunes:author>, <itunes:owner>, <itunes:image>, <itunes:category>, <itunes:explicit>
    <itunes:type> (episodic | serial)
    <podcast:guid> (locked UUID from Show.podcastGUID)
    <podcast:locked>  (yes/no, with owner email)
    <item> × N
      <title>, <description>, <pubDate>, <guid isPermaLink="false">
      <enclosure url="{OP3-prefix}{public-base}/{remote-path}" length="..." type="audio/mpeg"/>
      <itunes:duration>, <itunes:episodeType>, <itunes:season>, <itunes:episode>, <itunes:explicit>
      <itunes:image> (if per-episode override)
      <podcast:transcript url="..." type="text/vtt"/>
      <podcast:chapters url="..." type="application/json+chapters"/>
      <podcast:person role="host" href="...">...</podcast:person>
      <content:encoded><![CDATA[ <html description> ]]></content:encoded>
  </channel>
</rss>
```

Validation (local, pre-upload): required fields present, enclosure URLs reachable via HEAD, artwork dimensions valid, pubDate RFC 822, GUIDs unique within feed, feed size under Apple's 50MB limit.

## 8. OP3 Integration Flow

On show creation (or import), if OP3 is enabled:

1. User provides OP3 API key → stored in Keychain.
2. `OP3AnalyticsProvider.register(show:)` — calls OP3 to register/claim the show; receives an external show ID; persists an `AnalyticsBinding`.
3. `Show.analyticsBindingID` is set. This decision is **locked** — the UI shows a warning that disabling OP3 later will break continuity of download counts.
4. Every feed build calls `OP3AnalyticsProvider.prefix(enclosureURL:)` which wraps the URL with the OP3 prefix (format: `https://op3.dev/e,pg=<showUUID>/<originalURL>` — exact format per OP3 docs at implementation time).
5. `AnalyticsService` schedules periodic (every 6h) snapshot fetches, stored as `AnalyticsSnapshot` rows for charting.

## 9. Distribution Flow

Per show, for each `DistributionTarget`:

- **`.api` targets (Podcast Index, Podping):** Called automatically on every publish. `submit` is idempotent (re-submit OK). Status tracked in `DistributionRecord`.
- **`.guided` targets (Apple, Spotify, Amazon):** On first publish, UI prompts user to submit. `submit()` opens the submission URL in their browser with `feedURL` pre-filled. UI asks them to paste back the show ID once approved. `DistributionRecord.externalShowID` lets us deep-link later.

## 10. Local AI Stack

**Transcription:** vendored wispr `CompositeTranscriptionEngine` (whisper.cpp primary, Parakeet fallback for speed). Models downloaded during onboarding.

**LLM:** MLX-Swift + a 7–8B instruct model downloaded on first use. Prompts live in `Resources/Prompts/*.md` with `{{variables}}`. Outputs where possible are JSON-schema constrained (title/subtitle/description/chapters/keywords as a single JSON object).

Storage: models live in `~/Library/Application Support/Podedge/Models/` — same pattern as wispr's `ModelPaths`.

### 10.1 Provider Routing (v1.1+)

The `LLMProvider` protocol is the seam that lets users bring their own AI — Ollama for a different local model, or cloud APIs (Anthropic, OpenAI, any OpenAI-compatible endpoint) when they want top-tier quality. v1 ships only `MLXLLMProvider`; v1.1+ adds implementations.

Planned implementations:
- `MLXLLMProvider` — v1, on-device default.
- `OllamaLLMProvider` — HTTP to `http://localhost:11434`. Local but user-controlled model.
- `AnthropicLLMProvider` — Claude via official API.
- `OpenAILLMProvider` — GPT family via official API.
- `OpenAICompatibleLLMProvider` — generic base URL + key. Covers Groq, Together, Fireworks, LM Studio, LiteLLM, vLLM, and any OpenAI chat-completions-speaking server.

Routing model:

```swift
struct LLMRouting {
    var assignments: [LLMTaskKind: LLMBinding]   // per-task provider+model
    var defaultBinding: LLMBinding               // fallback
    var offlineFallback: LLMBinding?             // used when assigned provider unreachable
}

enum LLMTaskKind {
    case episodeMetadata
    case chapterDetection
    case socialBlurbs
    case titleSuggestions
    case summaryLong
    case summaryShort
}

struct LLMBinding {
    var providerID: String                       // "mlx", "ollama", "anthropic", "openai", "openai-compatible:<hostname>"
    var modelID: String                          // "llama-3.1-8b-instruct", "claude-sonnet-4.5", ...
    var temperature: Double?
    var maxTokens: Int?
}
```

Per-task routing matters: a user might use Claude for show notes (quality) but keep MLX for quick title suggestions (latency + cost). Default in v1.1 is still MLX for everything.

Constraints the protocol enforces across providers:
- Streaming is mandatory (`stream(_:)`).
- `schema: JSONSchema?` is a hint; each provider translates to its nearest capability (MLX grammar, Anthropic tool-use, OpenAI JSON mode / tools, Ollama `format=json`). Falls back to prompt-level "respond with JSON matching this schema" + parse-retry when the provider lacks native support.
- Providers report token counts in responses for cost accounting.
- Providers surface rate-limit errors with a `retryAfter` so `LLMRouter` can back off uniformly.

### 10.2 Privacy Guarantees Around Cloud Providers

Routing a task to a cloud provider sends content (transcripts, show notes, etc.) to that provider. This is a material change from v1's on-device guarantee, so:

- **Explicit first-use consent.** The first time any task is assigned to a cloud provider, a sheet states exactly what will be sent, to whom, under what ToS link. User must confirm. Stored as a per-provider-acceptance flag.
- **Per-show opt-out.** Each `Show` has `keepOnDevice: Bool` (default false). When true, `LLMRouter` refuses cloud providers for that show and forces MLX/Ollama. UI surfaces a small "on-device only" badge on the show.
- **Transparent labeling.** Every AI suggestion in the UI is tagged with the provider+model that generated it (e.g., "suggested by claude-sonnet-4.5"). Builds trust and makes routing mistakes obvious.
- **Hard kill switch.** A global "disable all cloud providers" toggle in Settings.

### 10.3 Cost Accounting

For metered providers:
- Response token counts persisted per call in a new `LLMCallLog` table.
- Aggregated views per-show and per-episode.
- Provider pricing tables bundled with the app (updated via app releases), converted to estimated USD. Not authoritative — users are directed to their provider dashboard for billing truth.

### 10.4 LLMRouter Component

Sits between `LLMService` and `LLMProvider`. Responsibilities:
- Resolve `(taskKind, show)` → `LLMBinding` → concrete provider instance.
- Enforce `keepOnDevice` override.
- Apply rate-limit-aware retry/backoff.
- Handle offline fallback per user preference (fall-back-to-MLX vs fail-loudly).
- Emit `LLMCallLog` entries.

The rest of the app keeps calling `LLMService.generate(.socialBlurbs, inputs: ...)`; routing is invisible to callers.

### 10.5 Tool-Use Support in LLMProvider

The Assistant (see §17) requires providers to support tool-use / function-calling. The `LLMProvider` protocol is extended:

```swift
protocol LLMProvider {
    var capabilities: LLMProviderCapabilities { get }
    func complete(_ prompt: Prompt, schema: JSONSchema?,
                  tools: [ToolDefinition]?) async throws -> LLMResponse
    func stream(_ prompt: Prompt, tools: [ToolDefinition]?)
        -> AsyncThrowingStream<LLMStreamEvent, Error>
}

struct LLMProviderCapabilities {
    let supportsNativeToolUse: Bool       // false → prompt-emulated tools
    let supportsStreaming: Bool
    let supportsJSONSchemaOutput: Bool
    let maxContextTokens: Int
}

enum LLMStreamEvent {
    case textDelta(String)
    case toolCall(id: String, name: String, arguments: JSONValue)
    case done(reason: StopReason)
}
```

Each provider translates `[ToolDefinition]` to its native format:
- MLX: grammar-constrained function-call decoding.
- Anthropic: `tools` array + `tool_use` / `tool_result` content blocks.
- OpenAI: `tools` array with JSON-schema function definitions.
- Ollama: `tools` array (models that support it) or prompt-emulated (older models).
- OpenAI-compatible: native if supported; prompt-emulated fallback.

When `supportsNativeToolUse` is false, the `LLMService` falls back to prompt-emulated tool use (ask the model for JSON, parse it, retry on parse error). This is flagged in the UI so users understand reliability may be lower.

## 11. Security Model

- **Credentials:** S3 access keys, OP3 API key, Podcast Index API key → Keychain only. Each has its own `keychainRef` string on the owning model; actual values never touch SwiftData.
- **Signed URLs:** never logged; `Logger` redacts known credential query params (`X-Amz-Signature`, `Signature`, etc.) and any header starting with `Authorization`.
- **Sandboxing:** hardened runtime, app sandbox on. Entitlements: `com.apple.security.network.client` (outbound HTTPS), `com.apple.security.files.user-selected.read-write` (for importing MP3 via open-panel drag). No microphone, no accessibility, no automation.
- **Audio data:** never leaves the device except via the user-configured host.

## 12. Packaging & Delivery

- Xcode workspace containing:
  - `PodedgeCore` Swift package — all services, models, extension-point protocols, default implementations that don't require AppKit. This is the reusable heart.
  - `Podedge` app target — SwiftUI/AppKit UI, menu bar integration, onboarding. Depends on `PodedgeCore`.
  - `podedge-cli` executable target (v1.1) — CLI client, depends on `PodedgeCore`.
  - `podedge-agent` executable target (v1.1) — MCP server entry point, depends on `PodedgeCore`. Can also be embedded in-process in the app for HTTP+SSE transport.
- The package split happens in v1 (Phase 1.5), not deferred. Retrofitting later is painful; doing it upfront is cheap and unlocks CLI + MCP without refactor.
- Signed + notarized distributable DMG. No App Store in v1 (simplifies entitlements around the AWS SDK).
- Auto-update via Sparkle or the wispr-style `UpdateChecker` — copy whichever wispr uses.

## 13. Testing Strategy

Mirror wispr's approach: one test file per service, plus integration tests for end-to-end flows.

- `LibraryStoreTests` — model CRUD.
- `IngestServiceTests` — MP3 validation, probing, waveform on fixture files.
- `FeedBuilderTests` — fixture-driven, golden-file comparison of feed XML.
- `PublishServiceTests` — mock `PodcastHost`, verify upload order, idempotency, feed upload.
- `OP3AnalyticsProviderTests` — URLProtocol stub for OP3 API.
- `DistributionTargetTests` — per-target.
- `EndToEndIntegrationTests` — drop fixture MP3 → publish to mock host → verify feed.
- `KeychainServiceTests` — round-trip credentials.

## 14. Performance Targets

- Ingest (hash + probe + waveform) for 1h MP3: ≤ 10s on M1.
- Transcription: ≤ 0.3× realtime on M2+ with medium Whisper model.
- LLM metadata generation: ≤ 30s for a 45-min episode transcript.
- Feed build: ≤ 500ms for a 200-episode show.
- Upload: network-bound; multipart with 8MB parts.

## 15. Open Questions (to resolve at implementation time)

- AWS SDK for Swift vs hand-rolled SigV4: SDK is larger (~15MB) but saves dev time. Lean toward SDK.
- MLX vs Apple Foundation Models framework (macOS 15.1+): Foundation Models is simpler but limited model selection. Lean MLX for flexibility.
- Exact OP3 prefix URL format and API auth style — confirm against live OP3 docs.
- Whether to vendor wispr's transcription code as a git submodule or fork into a standalone Swift package.
- Feed caching strategy: per-request rebuild vs background-regen-on-change. Likely the latter.

## 16. Action Layer (Tool Broker)

The Action Layer is a v1 addition that unifies how UI buttons and the Assistant invoke capabilities. Every action in Podedge — publish, edit, generate, query, post — is exposed as a typed tool. Both modalities go through the same broker; the LLM is never on the critical path for correctness.

### Tool

```swift
struct Tool<Input: Codable, Output: Codable> {
    let id: String                         // "podedge.episode.publish"
    let displayName: String
    let description: String                 // for LLM + /capabilities help + audit
    let scope: ToolScope                    // .read | .write | .destructive
    let minCapabilityTier: CapabilityTier?  // optional Assistant reliability gate
    let inputSchema: JSONSchema
    let handler: (Input, ToolContext) async throws -> Output
}

enum ToolScope { case read, write, destructive }
enum CapabilityTier { case t1, t2, t3 }     // see agentic-assistant.md
```

Tool handlers call into existing PodedgeCore services. They do not contain business logic themselves; they're thin adapters that validate inputs and delegate. Handlers are pure Swift — no LLM involvement.

### ToolBroker

```swift
final class ToolBroker {
    func execute<I, O>(_ toolID: String, input: I,
                       caller: ToolCaller) async throws -> O
    func list(scope: ToolScope?) -> [ToolSummary]
}

enum ToolCaller {
    case ui(source: String)           // e.g. "EpisodeEditorView.publishButton"
    case agent(id: String, session: AgentSession)
}
```

Responsibilities:
- Resolve `toolID` → registered tool.
- Enforce scope against the caller (an agent with read-only scope cannot invoke `.write` tools).
- Run the confirmation-token + UI-sheet flow for `.destructive` tools regardless of caller. A UI button invoking a destructive tool goes through the exact same confirmation sheet as an agent invocation.
- Apply rate limits (per-session, per-tool, per-hour caps — see §17 and `agentic-assistant.md`).
- Write `AgentAuditEntry` for every invocation (caller, tool ID, redacted args, outcome, duration, provider+model when applicable).

### UI Integration

UI buttons don't call services directly. They call `ToolBroker.execute`. This ensures:
- Confirmation UX is identical whether triggered by click or chat.
- Audit log is the single source of truth for "what happened in this app."
- Adding a tool once exposes it to both modalities — no duplicated code paths.

A `ToolButton` SwiftUI helper wraps the invocation, manages loading state, shows errors, and pulls display metadata from the tool definition.

### v1 Tool Catalog (minimum set)

Scoped to v1 features; grows with the app.

**Read:**
- `podedge.library.list_shows`, `get_show`, `list_episodes`, `get_episode`, `search`
- `podedge.feed.build_preview`, `validate`, `diff_against_published`, `get_published_xml`
- `podedge.analytics.query_cached`, `render_chart`, `get_summary`
- `podedge.distribution.get_status`
- `podedge.content.read_guide`
- `podedge.jobs.list`, `get_job`

**Write:**
- `podedge.episode.create_draft`, `update_metadata`, `set_cover`, `transcribe`
- `podedge.show.create`, `update_metadata`, `set_cover`
- `podedge.host.add_binding`, `test_binding`
- `podedge.llm.generate_metadata`, `generate_blurb`, `suggest_chapters`

**Destructive:**
- `podedge.episode.publish`, `unpublish`, `delete`
- `podedge.show.delete`
- `podedge.host.remove_binding`
- `podedge.social.post` (v1.1, PromoterAgent)

### Relationship to External MCP

`agent-access.md` describes exposing these tools externally via MCP. That's additive — the same `ToolBroker.list()` feeds both the in-app Assistant's router and the future MCP `tools/list` response. Defining tools once in v1 unlocks both paths.

## 17. Assistant

See `agentic-assistant.md` for the full design. This section captures the architectural anchor points.

### Placement in the UI Layer

A dockable pane in the main window (right side, resizable, collapsible) plus a ⌘K global shortcut. First-launch default: pane visible. Once hidden, stays hidden (persisted preference).

### Components

- **AssistantPaneView** — SwiftUI view; renders conversation, input, "Try asking" rail, tool-call rows, provider+model labels.
- **AssistantController** — orchestrates a single conversation's lifecycle: user utterance → router → specialist agent → tool calls → response streaming.
- **Router** — deterministic keyword rules with a one-shot classifier LLM fallback. Never invokes tools.
- **Specialist agents** — one file per agent in `Agents/`. Each agent: whitelist of tool IDs, max iterations, wall-clock timeout, minimum capability tier, system-prompt resource.
- **SuggestionRail** — templated, state-aware. No LLM call to generate suggestions.
- **CapabilityTierService** — maps `LLMBinding` → tier using a known-models table; unknowns default to T3.

### v1.1 Specialist Agents

PromoterAgent, AnalystAgent, QueryResolverAgent, FeedDebuggerAgent, PublishAssistantAgent. Each declares tool whitelist + min tier. Details in `agentic-assistant.md`.

### Conversation Statefulness

Each ⌘K invocation starts a fresh conversation. Intra-conversation the agent is stateful (multi-turn, clarifying questions allowed within iteration cap). No cross-session persistence in v1.1.

### Failure Escape Hatches

When the assistant cannot complete a request, the response always includes a deep-link to the manual UI path and a link to Settings → LLM Providers. User chooses.

### Security Anchors (also see §11 and `agentic-assistant.md`)

- LLM never sees credentials; all auth lives in the broker + Keychain.
- Every `.destructive` tool triggers a UI confirmation sheet, whether called by UI or by agent.
- Untrusted content (episode descriptions, guest bios, listener comments) is wrapped in `<untrusted_content>` tags in prompts with explicit system-prompt guidance to ignore embedded instructions.
- Per-session rate limits: 60 tool calls/min, 300/hour, 10 destructive/hour, configurable. Budget caps for metered LLM providers.
- Agents have narrow tool whitelists — scope reduction mitigates prompt-injection risk.
- Every tool invocation audited, viewable in Settings → Diagnostics → Audit Log.

### Config-as-Memory

Per-show markdown files (`voice-guide.md`, `promotion-guide.md`, `analytics-queries.md`) in the app's application-support directory. Agents read via `podedge.content.read_guide`. No automatic memory in v1.1.
