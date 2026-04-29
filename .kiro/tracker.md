# Podedge Implementation Tracker

Generated: 2026-04-27

## Agent Assignments

| Agent | Role | Work Streams |
|---|---|---|
| `swift-swe` | Primary implementer — services, models, protocols, pipelines | WS1–WS6 |
| `kiro_default` | UI layer, project setup, integration, prompts | WS1, WS7, WS8 |
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

## WS1: Foundation & Project Setup

**Agent:** `kiro_default`
**Depends on:** Nothing
**Unlocks:** Everything

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 1.1 | 1 | Create Xcode Project Structure | PodedgeApp.swift, Info.plist, entitlements, workspace | ⬜ |
| 1.2 | 1 | Configure Entitlements | Sandbox, network.client, files.user-selected.read-write | ⬜ |
| 1.3 | 1 | Add Swift Package Dependencies | AWS SDK, WhisperKit, MLX-Swift, swift-markdown | ⬜ |
| 1.4 | 1 | Set Up Folder Structure | Models/, Services/, Extensions/, Hosts/, etc. | ⬜ |
| 1.5.1 | 1.5 | Create PodedgeCore Swift Package | Package.swift, Sources/PodedgeCore/ structure | ⬜ |
| 1.5.2 | 1.5 | Convert to Workspace | Podedge.xcworkspace, app depends on PodedgeCore | ⬜ |
| 1.5.3 | 1.5 | No AppKit/SwiftUI in PodedgeCore | grep CI check, enforce Foundation-only imports | ⬜ |
| 1.5.4 | 1.5 | Move Services as Built | Establish convention: services go in PodedgeCore | ⬜ |

---

## WS2: Domain Model & Action Layer

**Agent:** `swift-swe`
**Depends on:** WS1
**Unlocks:** WS3

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 2.1 | 2 | Define SwiftData Models | Show, Episode, Asset, HostBinding, AnalyticsBinding, DistributionRecord, Job, AnalyticsSnapshot | ⬜ |
| 2.2 | 2 | Define Enums & Value Types | EpisodeStatus, EpisodeType, JobKind, JobState, HostKind, etc. | ⬜ |
| 2.3 | 2 | LibraryStore Facade | Typed CRUD wrappers around ModelContext, observable collections | ⬜ |
| 2.4 | 2 | LibraryStore Tests | Unit tests for CRUD operations | ⬜ |
| 2.5.1 | 2.5 | Define Tool & ToolBroker | Tool<Input,Output>, ToolScope, CapabilityTier, ToolCaller, broker | ⬜ |
| 2.5.2 | 2.5 | AuditLog Service | @Model AgentAuditEntry, redaction, 90-day retention | ⬜ |
| 2.5.3 | 2.5 | Destructive-Action Confirmation Sheet | ConfirmationSheetView + ConfirmationCoordinator | ⬜ |
| 2.5.4 | 2.5 | Tool Registry | Central registration point, broker reads from registry | ⬜ |
| 2.5.5 | 2.5 | ToolButton SwiftUI Helper | Wraps tool invocation, loading/error states | ⬜ |
| 2.5.6 | 2.5 | Tool & Broker Tests | Scope enforcement, confirmation flow, audit entries | ⬜ |

---

## WS3: Extension Points & Infrastructure

**Agent:** `swift-swe`
**Depends on:** WS2
**Unlocks:** WS4, WS5, WS6 (in parallel)

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 3.1 | 3 | AudioPipeline Protocol + PassthroughPipeline | sha256, probe, waveform, ID3 read, optional rewrite | ⬜ |
| 3.2 | 3 | PodcastHost Protocol | put, delete, publicURL, head | ⬜ |
| 3.3 | 3 | TranscriptionEngine Protocol | Vendor/adapt from wispr | ⬜ |
| 3.4 | 3 | LLMProvider Protocol | complete, stream, schema-constrained output | ⬜ |
| 3.5 | 3 | DistributionTarget Protocol | submit, refreshStatus, mode (.api/.guided) | ⬜ |
| 3.6 | 3 | PromotionRenderer Protocol | Generic render interface | ⬜ |
| 3.7 | 3 | AnalyticsProvider Protocol | register, prefix, fetchSnapshot | ⬜ |
| 4.1 | 4 | Logger with Redaction | Pattern-match and redact credentials from logs | ⬜ |
| 4.2 | 4 | KeychainService | Typed accessors for S3, OP3, PodcastIndex credentials | ⬜ |
| 4.3 | 4 | JobScheduler | Durable queue, dependencies, retries, backoff, resume on launch | ⬜ |
| 4.4 | 4 | JobScheduler Tests | Queue behavior, retry logic, dependency ordering | ⬜ |

---

## WS4: Audio Ingest Pipeline

**Agent:** `swift-swe`
**Depends on:** WS3
**Parallel with:** WS5, WS6

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 5.1 | 5 | MP3 Validator | MPEG frame sanity, MIME sniff, reject non-MP3 | ⬜ |
| 5.2 | 5 | Audio Prober | AVFoundation: duration (frame scan), bitrate, channels, LUFS | ⬜ |
| 5.3 | 5 | Waveform Generator | 1000-sample peak array, stored as .wfm binary | ⬜ |
| 5.4 | 5 | ID3 Tag Reader/Writer | Read/write title, artist, album, cover (APIC), chapters (CHAP/CTOC) | ⬜ |
| 5.5 | 5 | IngestService | Orchestrate: copy → validate → hash → probe → waveform → ID3 → enqueue jobs | ⬜ |
| 5.6 | 5 | IngestService Tests | Fixture MP3s: short/long, mono/stereo, tagged/untagged, corrupted | ⬜ |

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

## WS6: Hosting, Feed, Analytics & Distribution

**Agent:** `swift-swe`
**Depends on:** WS3
**Parallel with:** WS4, WS5

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 7.1 | 7 | S3Host Implementation | AWS SDK, multipart upload, HEAD-before-PUT, progress | ⬜ |
| 7.2 | 7 | HostService | Resolve HostBinding → PodcastHost, retries, logging | ⬜ |
| 7.3 | 7 | S3 Credentials UI | Form: bucket, region, prefix, base URL, keys. Test-connection | ⬜ |
| 7.4 | 7 | S3 Tests | URLProtocol stub or LocalStack | ⬜ |
| 8.1 | 8 | RSSFeed Value Types | RSSFeed, RSSChannel, RSSItem — pure Swift | ⬜ |
| 8.2 | 8 | FeedBuilder | Show + [Episode] → RSSFeed, calls AnalyticsProvider.prefix | ⬜ |
| 8.3 | 8 | RSS XML Serializer | RSSFeed → Data via XMLDocument | ⬜ |
| 8.4 | 8 | Feed Validator | Required fields, GUID uniqueness, enclosure reachability, size cap | ⬜ |
| 8.5 | 8 | FeedBuilder Tests | Golden-file comparison of feed XML | ⬜ |
| 9.1 | 9 | OP3AnalyticsProvider | register, prefix, fetchSnapshot | ⬜ |
| 9.2 | 9 | AnalyticsService | Periodic 6h polling, snapshot persistence, observable streams | ⬜ |
| 9.3 | 9 | OP3 Tests | URLProtocol stubs for OP3 API | ⬜ |
| 10.1 | 10 | PodcastIndexTarget | API submission with auth-hash scheme | ⬜ |
| 10.2 | 10 | PodpingTarget | Notify on publish via webhook or Hive | ⬜ |
| 10.3 | 10 | Guided Targets | Apple, Spotify, Amazon — open submission URL, capture IDs | ⬜ |
| 10.4 | 10 | DistributionService | Registry of targets, fan-out on publish, status refresh | ⬜ |
| 10.5 | 10 | Distribution Tests | Mock targets, verify fan-out | ⬜ |

---

## WS7: Publish Pipeline & Promotion

**Agent:** `swift-swe`
**Depends on:** WS4, WS5, WS6 (all three must complete)
**Unlocks:** WS8

| ID | Phase | Task | Description | Status |
|---|---|---|---|---|
| 11.1 | 11 | PublishArtifactBuilder | Original vs tag-rewritten copy with cover + chapters | ⬜ |
| 11.2 | 11 | PublishService | Full pipeline: upload → feed → distribute. Resumable via JobScheduler | ⬜ |
| 11.3 | 11 | Publish Dry-Run | Emit plan without side-effects: uploads, feed diff, notifications | ⬜ |
| 11.4 | 11 | Publish Tests | Mock host + distribution + analytics. Order, idempotency, resume | ⬜ |
| 12.1 | 12 | SocialBlurbRenderer | Per-platform variants: X, Bluesky, Mastodon, LinkedIn, Threads | ⬜ |
| 12.2 | 12 | Promotion UI Tab | Generated blurbs with copy buttons, regenerate action | ⬜ |

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
