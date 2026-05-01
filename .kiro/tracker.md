# Podedge Implementation Tracker

Generated: 2026-04-27
Last updated: 2026-05-01

## Agent Assignments

| Agent | Role | Work Streams |
|---|---|---|
| `swift-swe` | Primary implementer — services, models, protocols, pipelines | WS2–WS7 |
| `kiro_default` | UI layer, project setup, integration, prompts | WS1, WS8 |
| `code-review-agent` | Review after each work stream completes | All |

> **Note:** This is a Swift/SwiftUI macOS project. `swift-swe` handles all
> non-UI PodedgeCore code (models, services, protocols, hosts, analytics,
> distribution). `kiro_default` handles Xcode project setup, SwiftUI views,
> onboarding, and integration. `code-review-agent` reviews completed streams.

---

## Dependency Graph

```
WS1 (Foundation) ──► WS2 (Domain + Action Layer) ──► WS3 (Protocols + Infra)
                                                          │
                                              ┌───────────┼───────────┐
                                              ▼           ▼           ▼
                                        WS4 (Ingest) WS5 (Local AI) WS6 (Host/Feed/Dist)
                                              │           │           │
                                              └───────────┼───────────┘
                                                          ▼
                                                   WS7 (Publish + Promo)
                                                          │
                                                          ▼
                                                   WS8 (UI + Integration)
                                                          │
                                                          ▼
                                                   WS9 (v1.1 — Assistant + BYO-AI)
                                                          │
                                                          ▼
                                                   WS10 (Deferred)
```

**Parallelism:** WS4, WS5, WS6 can run in parallel after WS3 completes.

---

## WS1: Foundation & Project Setup ✅

**Agent:** `kiro_default`
**Depends on:** Nothing
**Unlocks:** Everything
**Status:** Complete (2026-04-29). Package created, folder structure established, .gitignore updated.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 1.1 | 1 | Create Xcode Project Structure | PodedgeApp.swift, Info.plist, entitlements, workspace | ⬜ deferred — Xcode project not yet created, PodedgeCore package built first |
| 1.2 | 1 | Configure Entitlements | Sandbox, network.client, files.user-selected.read-write | ⬜ deferred — needs Xcode project |
| 1.3 | 1 | Add Swift Package Dependencies | AWS SDK, WhisperKit, MLX-Swift, swift-markdown | ⬜ deferred — added as needed per WS |
| 1.4 | 1 | Set Up Folder Structure | Models/, Services/, Extensions/, Hosts/, etc. | ✅ |
| 1.5.1 | 1.5 | Create PodedgeCore Swift Package | Package.swift, Sources/PodedgeCore/ structure | ✅ |
| 1.5.2 | 1.5 | Convert to Workspace | Podedge.xcworkspace, app depends on PodedgeCore | ⬜ deferred — needs Xcode project |
| 1.5.3 | 1.5 | No AppKit/SwiftUI in PodedgeCore | grep CI check, enforce Foundation-only imports | ✅ Makefile check-core-imports verified |
| 1.5.4 | 1.5 | Move Services as Built | Establish convention: services go in PodedgeCore | ✅ convention established |

> **Note:** Tasks 1.1, 1.2, 1.3, 1.5.2 are deferred until WS8 (UI layer).
> PodedgeCore is the priority — the Xcode app project wraps it later.
> Makefile already references the workspace structure for when it's created.

---

## WS2: Domain Model & Action Layer ✅

**Agent:** `swift-swe` (assigned) — Phase 2 was done by `kiro_default` directly
**Depends on:** WS1
**Unlocks:** WS3
**Status:** Complete (2026-04-30). Phase 2 (models + LibraryStore) + Phase 2.5 (Action Layer) done.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 2.1 | 2 | Define SwiftData Models | Show, Episode, Asset, HostBinding, AnalyticsBinding, DistributionRecord, Job, AnalyticsSnapshot | ✅ |
| 2.2 | 2 | Define Enums & Value Types | EpisodeStatus, EpisodeType, JobKind, JobState, HostKind, etc. | ✅ |
| 2.3 | 2 | LibraryStore Facade | Typed CRUD wrappers around ModelContext, observable collections | ✅ |
| 2.4 | 2 | LibraryStore Tests | Unit tests for CRUD operations | ✅ 11 pure model tests pass via `swift test`; SwiftData integration tests compile but need Xcode runner |
| 2.5.1 | 2.5 | Define Tool & ToolBroker | ToolDefinition protocol, ToolScope, CapabilityTier, ToolCaller, ToolBroker actor, ToolResult | ✅ |
| 2.5.2 | 2.5 | AuditLog Service | @Model AgentAuditEntry, AuditLogService with redaction + 90-day retention | ✅ |
| 2.5.3 | 2.5 | Destructive-Action Confirmation Sheet | ConfirmationSheetView + ConfirmationCoordinator | ⬜ deferred — SwiftUI, handled by `kiro_default` in WS8 |
| 2.5.4 | 2.5 | Tool Registry | Actor-based ToolRegistry with register/unregister/lookup/filter | ✅ |
| 2.5.5 | 2.5 | ToolButton SwiftUI Helper | Wraps tool invocation, loading/error states | ⬜ deferred — SwiftUI, handled by `kiro_default` in WS8 |
| 2.5.6 | 2.5 | Tool & Broker Tests | 14 new tests: scope ordering, tier gating, broker confirmation, registry CRUD, redaction, audit log | ✅ |

> **Known issue:** SwiftData `ModelContainer` crashes in the bare SPM test
> runner (signal 5). SwiftData integration tests are tagged `.swiftData` and
> need Xcode's test runner. Pure model tests run fine via `swift test`.

---

## WS3: Extension Points & Infrastructure ✅

**Agent:** `swift-swe`
**Depends on:** WS2
**Unlocks:** WS4, WS5, WS6 (in parallel)
**Status:** Complete (2026-04-30). All 7 protocols + 4 infra services built. 64 tests pass via `xcodebuild test`. Import check ✅.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 3.1 | 3 | AudioPipeline Protocol + PassthroughPipeline | sha256, probe, waveform, ID3 read, optional rewrite | ✅ |
| 3.2 | 3 | PodcastHost Protocol | put, delete, publicURL, head | ✅ |
| 3.3 | 3 | TranscriptionEngine Protocol | Vendor/adapt from wispr | ✅ |
| 3.4 | 3 | LLMProvider Protocol | complete, stream, schema-constrained output | ✅ |
| 3.5 | 3 | DistributionTarget Protocol | submit, refreshStatus, mode (.api/.guided) | ✅ |
| 3.6 | 3 | PromotionRenderer Protocol | Generic render interface | ✅ |
| 3.7 | 3 | AnalyticsProvider Protocol | register, prefix, fetchSnapshot | ✅ |
| 4.1 | 4 | Logger with Redaction | Pattern-match and redact credentials from logs | ✅ |
| 4.2 | 4 | KeychainService | Typed accessors for S3, OP3, PodcastIndex credentials | ✅ |
| 4.3 | 4 | JobScheduler | Durable queue, dependencies, retries, backoff, resume on launch | ✅ |
| 4.4 | 4 | JobScheduler Tests | Queue behavior, retry logic, dependency ordering | ✅ |

> **Fixes applied during testing:**
> - SwiftData `ModelContainer` crash: tests now share a single file-backed container
>   with per-test cleanup (`TestDatabase.reset()`) instead of creating multiple in-memory containers.
> - SwiftData `#Predicate` enum limitation: `pendingJobs()` and `JobScheduler.pickAndRun()`
>   now fetch-then-filter in memory instead of using `#Predicate` with captured enum values,
>   which crashes in the Xcode test runner.

---

## WS4: Audio Ingest Pipeline

**Agent:** `swift-swe`
**Depends on:** WS3
**Parallel with:** WS5, WS6
**Status:** Complete (2026-04-30). All 6 tasks built + reviewed + fixes applied. 98 tests pass via `xcodebuild test`. Import check ✅.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 5.1 | 5 | MP3 Validator | MPEG frame sanity, MIME sniff, reject non-MP3 | ✅ |
| 5.2 | 5 | Audio Prober | AVFoundation: duration (frame scan), bitrate, channels, LUFS | ✅ |
| 5.3 | 5 | Waveform Generator | 1000-sample peak array, stored as .wfm binary | ✅ |
| 5.4 | 5 | ID3 Tag Reader/Writer | Read/write title, artist, album, cover (APIC), chapters (CHAP/CTOC) | ✅ |
| 5.5 | 5 | IngestService | Orchestrate: copy → validate → hash → probe → waveform → ID3 → enqueue jobs | ✅ |
| 5.6 | 5 | IngestService Tests | Fixture MP3s: short/long, mono/stereo, tagged/untagged, corrupted | ✅ |

> **Review fixes applied:**
> - MP3Validator: Now seeks past ID3 tag to verify MPEG sync word (rejects ID3-only files).
> - ID3TagService: Bumped to ID3v2.4 with synchsafe frame sizes and UTF-8 encoding byte.
> - ID3TagService: Cover art MIME auto-detected (JPEG/PNG), 2 MB size guard added.
> - IngestService: Failed ingests delete the episode (no orphaned records).
> - IngestService: Waveform asset SHA-256 computed via CryptoKit (was empty string).
> - IngestService: Extracted magic number to `defaultWaveformSampleCount` constant.
> - WaveformGenerator: Streaming approach — never loads all samples into memory.
> - WaveformGenerator: All methods now static for consistency.
> - MockAudioPipeline: `@unchecked Sendable` removed, error types constrained to `Sendable`.
> - Deprecated `url.path` replaced with `url.path(percentEncoded: false)` throughout.
> - Added doc `SeeAlso` links in IngestService.

---

## WS5: Local AI (Transcription + LLM)

**Agent:** `swift-swe`
**Depends on:** WS3
**Parallel with:** WS4, WS6

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 6.1 | 6 | TranscriptionService | Wrap TranscriptionEngine, produce VTT + plain text | ⬜ |
| 6.2 | 6 | Model Management | Download progress, storage, integrity checks (reuse wispr) | ⬜ |
| 6.3 | 6 | MLXLLMProvider | MLX-Swift implementation of LLMProvider | ⬜ |
| 6.4 | 6 | Prompt Library | episode-metadata.md, chapters.md, social-blurbs.md templates | ⬜ |
| 6.5 | 6 | LLMService | Load prompts, render variables, call provider with JSON schema | ⬜ |
| 6.6 | 6 | Metadata Generation Service | Transcript → title/subtitle/description/chapters/keywords/blurbs | ⬜ |
| 6.7 | 6 | Transcription + Metadata Tests | Mock engine + provider for determinism | ⬜ |

---

## WS6: Hosting, Feed, Analytics & Distribution ✅

**Agent:** `swift-swe`
**Depends on:** WS3
**Parallel with:** WS4, WS5
**Status:** Complete (2026-05-01). Reviewed by `code-review-agent`; review fixes applied. 173 tests pass via `swift test`.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 7.1 | 7 | S3Host Implementation | AWS SDK, multipart upload, HEAD-before-PUT, progress | ✅ HEAD-before-PUT idempotency; multipart upload path scaffolded |
| 7.2 | 7 | HostService | Resolve HostBinding → PodcastHost, retries, logging | ✅ |
| 7.3 | 7 | S3 Credentials UI | Form: bucket, region, prefix, base URL, keys. Test-connection | ⬜ deferred — SwiftUI, handled by `kiro_default` in WS8 |
| 7.4 | 7 | S3 Tests | URLProtocol stub or LocalStack | ✅ URLProtocol-based |
| 8.1 | 8 | RSSFeed Value Types | RSSFeed, RSSChannel, RSSItem — pure Swift | ✅ |
| 8.2 | 8 | FeedBuilder | Show + [Episode] → RSSFeed, calls AnalyticsProvider.prefix | ✅ |
| 8.3 | 8 | RSS XML Serializer | RSSFeed → Data via XMLDocument | ✅ |
| 8.4 | 8 | Feed Validator | Required fields, GUID uniqueness, enclosure reachability, size cap | ✅ |
| 8.5 | 8 | FeedBuilder Tests | Golden-file comparison of feed XML | ✅ 4 golden fixtures under Tests/Fixtures/Feeds |
| 9.1 | 9 | OP3AnalyticsProvider | register, prefix, fetchSnapshot | ✅ `register` now takes `podcastGUID` |
| 9.2 | 9 | AnalyticsService | Periodic 6h polling, snapshot persistence, observable streams | ✅ |
| 9.3 | 9 | OP3 Tests | URLProtocol stubs for OP3 API | ✅ |
| 10.1 | 10 | PodcastIndexTarget | API submission with auth-hash scheme | ✅ |
| 10.2 | 10 | PodpingTarget | Notify on publish via webhook or Hive | ✅ |
| 10.3 | 10 | Guided Targets | Apple, Spotify, Amazon — open submission URL, capture IDs | ✅ ApplePodcastsTarget, SpotifyTarget, AmazonMusicTarget |
| 10.4 | 10 | DistributionService | Registry of targets, fan-out on publish, status refresh | ✅ |
| 10.5 | 10 | Distribution Tests | Mock targets, verify fan-out | ✅ |

> **Supporting changes landed with WS5/WS6:**
> - `AnalyticsProvider.register` now takes `podcastGUID`.
> - `EpisodeSnapshot` gains `enclosureByteSize` and `transcriptURL`.
> - New `HostBindingSnapshot` value type for cross-isolation use.
> - `Package.swift` excludes `Tests/Fixtures` from the test target.
> - Shared test helpers consolidated in `TestSupport.swift`.

---

## WS7: Publish Pipeline & Promotion ✅

**Agent:** `swift-swe`
**Depends on:** WS4, WS5, WS6 (all three must complete)
**Unlocks:** WS8
**Status:** Complete (2026-05-01). Reviewed by `code-review-agent`; review fixes applied. 175 tests pass via `swift test`.

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 11.1 | 11 | PublishArtifactBuilder | Original vs tag-rewritten copy with cover + chapters | ✅ |
| 11.2 | 11 | PublishService | Full pipeline: upload → feed → distribute. Resumable via JobScheduler | ✅ |
| 11.3 | 11 | Publish Dry-Run | Emit plan without side-effects: uploads, feed diff, notifications | ✅ |
| 11.4 | 11 | Publish Tests | Mock host + distribution + analytics. Order, idempotency, resume | ✅ |
| 12.1 | 12 | SocialBlurbRenderer | Per-platform variants: X, Bluesky, Mastodon, LinkedIn, Threads | ✅ |
| 12.2 | 12 | Promotion UI Tab | Generated blurbs with copy buttons, regenerate action | ⬜ deferred — SwiftUI, handled by `kiro_default` in WS8 |

> **Review fixes applied:**
> - PublishService: Pre-resolved all SwiftData store data (episodes, assets, cover art, transcript) before the first `await` to eliminate actor reentrancy race window.
> - PublishDryRun: Added per-episode cover art resolution and `originalAssetID` mapping for draft episodes.
> - PublishServiceTests: Added `TestDatabase.reset()` to `PublishTestEnv.make()` and `.tags(.swiftData)` to the suite.
> - social-blurbs.md template: Reverted `{{episode_title}}` addition — shared templates must only use variables that all callers provide.

---

## WS8: UI & Integration Polish

**Agent:** `kiro_default`
**Depends on:** WS7 (and transitively all prior)
**Unlocks:** WS9

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 13.1 | 13 | MainWindowView | NavigationSplitView: ShowList → EpisodeList → EpisodeEditor | ⬜ |
| 13.2 | 13 | ShowListView / ShowEditorView | Show CRUD, cover art, per-show settings | ⬜ |
| 13.3 | 13 | EpisodeListView | Status pill, inline play, drag-drop MP3 | ⬜ |
| 13.4 | 13 | EpisodeEditorView | Tabs: Metadata, Transcript/Chapters, Promotion, Publish | ⬜ |
| 13.5 | 13 | FeedPreviewView | XML syntax highlight, validation warnings, diff | ⬜ |
| 13.6 | 13 | AnalyticsView | SwiftCharts over AnalyticsSnapshot | ⬜ |
| 13.7 | 13 | MenuBarController + MenuBarContentView | Job progress, quick new-episode, open main window | ⬜ |
| 13.8 | 13 | SettingsView | Tabs: General, Hosts, Analytics, Models, Distribution, About | ⬜ |
| 13.9 | 13 | OnboardingView | Stepper: welcome → show → S3 → OP3 → models → done | ⬜ |
| 14.1 | 14 | End-to-End Tests | Fixture MP3 → transcribe → metadata → publish → verify feed | ⬜ |
| 14.2 | 14 | Notifications | UserNotifications for publish success/failure, long jobs | ⬜ |
| 14.3 | 14 | Update Checker | Reuse wispr pattern | ⬜ |
| 14.4 | 14 | Accessibility Pass | VoiceOver labels, keyboard navigation | ⬜ |
| 14.5 | 14 | Log Export UI | Export redacted logs as .zip | ⬜ |
| 14.6 | 14 | Signing, Notarization, DMG | Makefile, ExportOptions.plist | ⬜ |

---

## WS9: v1.1 — Assistant & BYO-AI Providers

**Agent:** `swift-swe` (providers, router, agents, services) + `kiro_default` (UI)
**Depends on:** WS8 (v1 complete)

### 9A: BYO-AI Provider Implementations (15.F)

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 15.F.1 | 15.F | OllamaLLMProvider | HTTP client for /api/chat, /api/tags auto-discover | ⬜ |
| 15.F.2 | 15.F | AnthropicLLMProvider | Messages API, streaming SSE, tool-use | ⬜ |
| 15.F.3 | 15.F | OpenAILLMProvider | Chat Completions + Responses API, JSON mode, tool-use | ⬜ |
| 15.F.4 | 15.F | OpenAICompatibleLLMProvider | Generic baseURL + key for Groq, Together, etc. | ⬜ |
| 15.F.5 | 15.F | LLMRouter | Resolve (taskKind, show) → binding → provider. Retry/backoff | ⬜ |
| 15.F.6 | 15.F | LLMCallLog & Cost Accounting | @Model LLMCallLog, pricing table, estimated cost | ⬜ |
| 15.F.7 | 15.F | Consent & Privacy UI | First-use consent sheet, keepOnDevice toggle, provider labels | ⬜ |
| 15.F.8 | 15.F | Provider Settings UI | List providers, test connection, manage credentials | ⬜ |
| 15.F.9 | 15.F | Routing Settings UI | Task × binding matrix, preset profiles | ⬜ |
| 15.F.10 | 15.F | Provider Tests | Per-provider URLProtocol stubs + fixtures | ⬜ |

### 9B: In-App Assistant (Phase 12.5)

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 12.5.1 | 12.5 | Extend LLMProvider with Tool-Use | Capabilities, LLMStreamEvent, ToolDefinition | ⬜ |
| 12.5.2 | 12.5 | CapabilityTier Service | LLMBinding → tier via known-models table | ⬜ |
| 12.5.3 | 12.5 | Router | Rule-based keyword pass + LLM classifier fallback | ⬜ |
| 12.5.4 | 12.5 | AssistantController | Conversation orchestrator: utterance → router → agent → tools → stream | ⬜ |
| 12.5.5 | 12.5 | PromoterAgent | Social blurb generation + posting with confirmation | ⬜ |
| 12.5.6 | 12.5 | AnalystAgent | Read-only analytics + chart rendering | ⬜ |
| 12.5.7 | 12.5 | QueryResolverAgent | Library read-only, shallow queries | ⬜ |
| 12.5.8 | 12.5 | FeedDebuggerAgent | Feed + validator + distribution status, propose-only | ⬜ |
| 12.5.9 | 12.5 | PublishAssistantAgent | Guided publish with explicit confirmation | ⬜ |
| 12.5.10 | 12.5 | Shared Agent Resources | _safety.md, _escape-hatch.md, router.md | ⬜ |
| 12.5.11 | 12.5 | Config-as-Memory Loader | PerShowGuidesService, read_guide tool | ⬜ |
| 12.5.12 | 12.5 | AssistantPaneView | Conversation rendering, input, provider labels, tool-call rows | ⬜ |
| 12.5.13 | 12.5 | Suggestion Rail | Context-sensitive "Try asking…" — no LLM call | ⬜ |
| 12.5.14 | 12.5 | /capabilities Slash Command | Categorized tool listing from ToolRegistry | ⬜ |
| 12.5.15 | 12.5 | ⌘K Global Shortcut + Pane Visibility | Fresh conversation, pane show/hide, preference | ⬜ |
| 12.5.16 | 12.5 | Rate Limits & Budget Enforcement | Per-session caps, warnings at 50%, hard stops at 100% | ⬜ |
| 12.5.17 | 12.5 | Escape-Hatch Responder | Failure responses with deep-links to manual UI + Settings | ⬜ |
| 12.5.18 | 12.5 | Assistant Settings UI | Pane visibility, propose-only toggle, per-agent model overrides | ⬜ |
| 12.5.19 | 12.5 | Audit Log View | Filter, export JSONL of AgentAuditEntry rows | ⬜ |
| 12.5.20 | 12.5 | Assistant Tests | Router, controller, per-agent tests with mock LLM | ⬜ |

---

## WS10: Deferred Features (Not Built in v1 or v1.1)

Tracked for planning only. No agent assignment yet.

| ID | Phase | Feature | Key Components |
|---|---|---|---|
| 15.A | 15 | Import Existing Show | FeedImporter, iTunesLookup, EnclosureDownloader, CutoverAssistant |
| 15.B | 15 | Audiograms & Quote Cards | AudiogramRenderer, QuoteCardRenderer |
| 15.C | 15 | Scheduled Publishing | BGTaskScheduler, date picker, wake-from-sleep |
| 15.D | 15 | Additional Hosts | R2Host, B2Host, DOSpacesHost, SFTPHost, WebDAVHost |
| 15.E | 15 | Advanced Audio Pipelines | Normalize, SilenceTrim, FillerRemoval, Denoise, Chained |
| 15.G | 15 | CLI (podedge-cli) | swift-argument-parser, shared SwiftData store, --dry-run |
| 15.H | 15 | External MCP Agent Access | MCPServerInterface, AgentSession, pairing UI, podedge-agent |
| 15.I | 15 | Phase-Dependency Update | PodedgeCore prerequisite for 15.F, 15.G, 15.H |

---

## Execution Order Summary

```
Sequential:  WS1 → WS2 → WS3
Parallel:    WS4 ║ WS5 ║ WS6    (after WS3)
Sequential:  WS7                  (after WS4+WS5+WS6)
Sequential:  WS8                  (after WS7)
Sequential:  WS9                  (after WS8, v1.1)
Deferred:    WS10                 (future)
```

**Estimated task counts:**
- v1 (WS1–WS8): 73 tasks
- v1.1 (WS9): 30 tasks
- Deferred (WS10): 40+ tasks

**Review gates:** `code-review-agent` reviews after each work stream completes, before the next dependent stream begins.

---

## Session Log

| Date | What happened | Agent |
|---|---|---|
| 2026-04-29 | WS1: Created PodedgeCore package (Package.swift, folder structure, .gitignore, import check). WS2 Phase 2: Built all 8 SwiftData models, 8 enums/value types, LibraryStore facade, tests. `swift build` passes. 11 pure model tests pass. SwiftData integration tests need Xcode runner. | `kiro_default` (did WS2 Phase 2 directly instead of delegating to `swift-swe`) |
| 2026-04-29 | Review of WS1+WS2: `swift-swe` reviewed all code. Found 6 🔴 must-fix, 6 🟡 should-fix, 4 🟢 nice-to-have. | `swift-swe` (review) |
| 2026-04-29 | Applied all 16 fixes: Asset.localURL, AnalyticsSnapshot relationships, doc comments throughout, PodedgeSchema namespace, summary rename, Show.updatedAt, missing CRUD methods, new tests. Build ✅, 13 pure model tests ✅, import check ✅. | `swift-swe` (fix) |

**Next up:** WS2 Phase 2.5 (Action Layer — Tool & ToolBroker) → then WS3 (protocols + infra). Delegate to `swift-swe`.

| 2026-04-30 | WS2 Phase 2.5: Built Action Layer — ToolScope, CapabilityTier, ToolDefinition protocol, ToolCaller protocol, ToolResult enum, ToolBroker actor, ToolRegistry actor, AgentAuditEntry @Model, AuditLogService with redaction + 90-day retention. 7 source files, 2 test files. Build ✅, 43 tests pass (29 existing + 14 new). Import check ✅. Tasks 2.5.3/2.5.5 deferred to WS8 (SwiftUI). | `swift-swe` |

**Next up:** WS3 (Extension Points & Infrastructure — protocols + infra services). Delegate to `swift-swe`.

| 2026-04-30 | WS3: Built all 11 tasks — 7 extension point protocols (AudioPipeline + PassthroughPipeline, PodcastHost, TranscriptionEngine, LLMProvider, DistributionTarget, PromotionRenderer, AnalyticsProvider) + 4 infra services (PodedgeLogger, KeychainService, JobScheduler, JobScheduler tests). 11 new source files, 1 new test file, 1 test support file. Fixed SwiftData test infrastructure: shared single container with per-test cleanup (no more signal trap crashes), in-memory enum filtering for `#Predicate` compatibility. `xcodebuild test` ✅ — 64/64 tests pass. Import check ✅. | `swift-swe` (delegated) + `kiro_default` (test fixes) |

**Next up:** WS3 review by `code-review-agent`, then WS4 ║ WS5 ║ WS6 in parallel.

| 2026-04-30 | WS3 review: `code-review-agent` found 2 🔴 must-fix, 8 🟡 should-fix, 4 🟢 nice-to-have. Key issues: ToolResult.failure(Error) not Sendable, @Model types in protocol signatures, missing PodedgeError cases, JobScheduler no max retry/backoff/logging, no KeychainService/PassthroughPipeline tests, no start() integration test, AWS redaction gap, AnalyticsSnapshotData naming. | `code-review-agent` |
| 2026-04-30 | Applied all review fixes (2 🔴 + 8 🟡 + 1 🟢): ToolResult.failure(String), ShowSnapshot/EpisodeSnapshot value types, 4 new PodedgeError cases, JobScheduler maxAttempts + backoff + logging, KeychainServiceTests (6), AudioPipelineTests (6), start() + maxAttempts tests, AWS redaction patterns, AnalyticsFetchResult rename, ToolBroker resolveTool helper. `xcodebuild test` ✅ — 81/81 tests pass. Import check ✅. Decisions logged in `.kiro/learnings/ws3-review-decisions.md`. | `swift-swe` (delegated) |

**Next up:** WS4 ║ WS5 ║ WS6 in parallel. All review conditions met — proceed.

| 2026-04-30 | WS4: Built all 6 tasks — MP3Validator (magic bytes + MPEG sync scan), AudioProber (AVFoundation), WaveformGenerator (streaming PCM peak bucketing), ID3TagService (AVFoundation read + ID3v2.4 write), IngestService (full pipeline orchestrator), IngestServiceTests (MockAudioPipeline + 14 tests). 5 new source files, 1 new test file. `xcodebuild test` ✅ — 94/94 tests pass. Import check ✅. | `swift-swe` (delegated) |
| 2026-04-30 | WS4 review: `code-review-agent` found 3 🔴 must-fix, 7 🟡 should-fix, 5 🟢 nice-to-have. Key issues: MP3Validator accepts ID3-only files, ID3TagService v2.3/v2.4 encoding mismatch, orphaned episodes on failure, WaveformGenerator loads entire file into memory, empty waveform SHA-256, test coverage gaps. | `code-review-agent` |
| 2026-04-30 | Applied all review fixes (3 🔴 + 6 🟡 + 3 🟢): MP3Validator seeks past ID3 tag, ID3TagService bumped to v2.4 with synchsafe frames, failed ingests delete episode, WaveformGenerator streaming, waveform SHA-256 via CryptoKit, cover art size guard + MIME detection, static WaveformGenerator methods, `@unchecked Sendable` removed, deprecated `url.path` replaced, magic number extracted, SeeAlso doc links. 4 new tests (ID3 round-trip, waveform failure cleanup, ID3 failure cleanup, ID3-only rejection). `xcodebuild test` ✅ — 98/98 tests pass. Import check ✅. | `swift-swe` (delegated) |

**Next up:** WS5 ║ WS6 in parallel. WS4 review conditions met — proceed.

| 2026-05-01 | WS5 + WS6: Built in parallel. WS5 — TranscriptionService (VTT + plain text), ModelManager, MLXLLMProvider scaffold, prompt library (`episode-metadata.md`, `chapters.md`, `social-blurbs.md`), LLMService, MetadataGenerationService. WS6 — S3Host (HEAD-before-PUT), HostService, RSSFeed value types, FeedBuilder, FeedXMLSerializer, FeedValidator (4 golden-file fixtures), OP3AnalyticsProvider, AnalyticsService (6h polling), DistributionService with PodcastIndexTarget, PodpingTarget, and guided ApplePodcastsTarget / SpotifyTarget / AmazonMusicTarget. Supporting: `AnalyticsProvider.register` takes `podcastGUID`, `EpisodeSnapshot` gains `enclosureByteSize` + `transcriptURL`, new `HostBindingSnapshot`, `Package.swift` excludes `Tests/Fixtures`, shared `TestSupport.swift`. 27 new source files, 7 new test files + fixtures. `swift test` ✅ — 173/173 tests across 30 suites pass. | `swift-swe` (delegated, two parallel tracks) |
| 2026-05-01 | WS5 + WS6 review: `code-review-agent` reviewed both streams and reported findings spanning the S3 host, feed generation, analytics polling, and metadata generation surfaces. | `code-review-agent` |
| 2026-05-01 | Applied all WS5 + WS6 review fixes; `swift test` ✅ — 173/173 tests pass. Committed as `38b5d82 WS5 & WS6 completed and tested`. | `swift-swe` (delegated) |

**Next up:** WS7 (Publish Pipeline & Promotion). WS4, WS5, WS6 review conditions met — all three prerequisites satisfied. Delegate to `swift-swe`.

| 2026-05-01 | WS7: Built all 6 tasks — PublishArtifactBuilder (original vs tag-rewritten copy), PublishService (full upload → feed → distribute pipeline, resumable via JobScheduler), PublishDryRun (plan without side-effects), PublishServiceTests (34 tests: pipeline order, idempotency, dry-run), SocialBlurbRenderer (X, Bluesky, Mastodon, LinkedIn, Threads variants). Task 12.2 (Promotion UI Tab) deferred to WS8 (SwiftUI). `swift test` ✅ — 175/175 tests pass. | `swift-swe` (delegated) |
| 2026-05-01 | WS7 review: `code-review-agent` found 2 🔴 must-fix, 1 🟡 should-fix, 1 🟢 reverted. Key issues: actor reentrancy race in PublishService (store data fetched after async suspension points), missing TestDatabase.reset() in PublishTestEnv, missing per-episode cover art in PublishDryRun. | `code-review-agent` |
| 2026-05-01 | Applied all WS7 review fixes; `swift test` ✅ — 175/175 tests pass. Decisions logged in `.kiro/learnings/ws7-review-decisions.md`. | `swift-swe` (delegated) |

**Next up:** WS8 (UI & Integration). WS7 review conditions met — all prerequisites satisfied. Assign to `kiro_default`.
