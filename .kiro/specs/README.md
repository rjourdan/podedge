# Podedge v1 Specs

> Index and methodology for the 10 v1 implementation specs.
> **Audience:** developers writing or reviewing specs and their implementations.

## Methodology

Each spec consists of `requirements.md` (EARS-style acceptance criteria: "When
X, the system shall Y") and `design.md` (types, files, sequences). Invariants
are stated explicitly and tested as property-based tests using Swift Testing's
`@Test(arguments:)` macro where the input space can be enumerated. Unit tests
use the Swift Testing framework (`@Test`, `#expect`, `#require`); no new test
dependencies are introduced.

## Spec index

| # | Directory | What it specifies |
|---|-----------|-------------------|
| 01 | [`01-composition-root/`](01-composition-root/) | `AppServices` wires all services together; `JobScheduler` has handlers for every `JobKind` at launch. |
| 02 | [`02-audio-ingest/`](02-audio-ingest/) | `DefaultAudioPipeline` + `IngestService`; drag-drop MP3 creates an `Episode` and enqueues the job chain. |
| 03 | [`03-transcription/`](03-transcription/) | `WhisperKitTranscriptionEngine` + `TranscribeJobHandler`; produces VTT stored as an `Asset`. |
| 04 | [`04-local-llm-mlx/`](04-local-llm-mlx/) | MLX and Ollama local LLM providers; onboarding model picker with guidance strings. |
| 05 | [`05-metadata-generation/`](05-metadata-generation/) | `GenerateMetadataJobHandler` produces `EpisodeSuggestions`; UI shows Apply/Regenerate. |
| 06 | [`06-publish-pipeline/`](06-publish-pipeline/) | `PublishJobHandler`, `UploadJobHandler`, `OP3PollJobHandler`; full publish pipeline wired end-to-end. |
| 07 | [`07-social-posting/`](07-social-posting/) | `SocialPostingService`, `BlueskyTarget`, `MastodonTarget`, `CopyPasteTarget`; Promotion tab Post/Copy buttons. |
| 08 | [`08-tool-registry-wiring/`](08-tool-registry-wiring/) | All 23 v1 tools registered; `ToolBroker` writes audit entries; UI uses `ToolButton` for every write. |
| 09 | [`09-assistant-core/`](09-assistant-core/) | `AssistantController`, `Router`, extended `LLMProvider` with tool-use; `AssistantPaneView` + ⌘K shortcut. Local providers (MLX + Ollama) only. |
| 10 | [`10-specialist-agents/`](10-specialist-agents/) | `PromoterAgent`, `PublishAssistantAgent`, `CapabilityTierService`, `PerShowGuidesService`. |

## Cross-cutting architectural rule

**All specs are bound by [ADR 0001](../../docs/decisions/0001-ui-writes-through-toolbroker.md):**

> Reads use SwiftData idioms (`@Query`, `@Bindable`). Writes go through `ToolBroker`.

Concretely:

- A spec may describe views that use `@Query` to display a list or `@Bindable`
  to buffer form edits. This is correct and matches the rule.
- A spec must not describe a view calling `modelContext.insert()`,
  `modelContext.delete()`, or mutating a `@Bindable` property as the final
  commit of a user action. The commit must be a `ToolBroker` invocation.
- Specs 05 and 08 reference `@Query` for reads — this is correct and compliant.
- No spec currently describes a write that bypasses the broker. If you find one,
  it is a spec defect; file a correction before implementing.

## When writing a new spec

- [ ] Every write the spec introduces is invoked through a registered tool in `ToolBroker`.
- [ ] Every read the spec introduces uses `@Query`, `@Bindable`, or `@Environment(\.modelContext)` directly in the view.
- [ ] The spec directory contains both `requirements.md` and `design.md`.
- [ ] Property-based tests use `@Test(arguments:)` from Swift Testing.
- [ ] No new test dependencies are added (use only Swift Testing + Foundation + existing PodedgeCore test helpers).
