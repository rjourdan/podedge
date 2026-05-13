# Implementation Plan: Metadata Generation

## Overview

This plan implements the metadata generation feature end-to-end: a new `EpisodeSuggestions` SwiftData model for persisting LLM-generated suggestions, a `GenerateMetadataJobHandler` that bridges the job system to the existing `MetadataGenerationService`, UI updates to display and apply suggestions across the Metadata, Chapters, and Promotion tabs, and registration in the app's composition root.

## Tasks

- [ ] 1. Create EpisodeSuggestions model and register in schema
  - [ ] 1.1 Create `EpisodeSuggestions` SwiftData model
    - Create `PodedgeCore/Sources/PodedgeCore/Models/EpisodeSuggestions.swift`
    - Define `@Model public final class EpisodeSuggestions` with all fields from design: `id`, `episodeID`, `generatedAt`, `suggestedTitle`, `suggestedSubtitle`, `suggestedDescriptionHTML`, `keywordsJSON`, `chaptersJSON`, `blurbTwitter`, `blurbLinkedIn`, `blurbMastodon`, `blurbBluesky`, `blurbThreads`
    - Mark `id` with `@Attribute(.unique)`
    - Implement `public init(episodeID: UUID, metadata: GeneratedMetadata)` that maps `GeneratedMetadata` fields to stored properties, encoding chapters and keywords as JSON strings
    - Populate `blurbBluesky` and `blurbThreads` from `metadata.blurbs.mastodon` as noted in design
    - Add computed properties for decoding `keywordsJSON` → `[String]` and `chaptersJSON` → `[GeneratedChapter]`
    - _Requirements: EpisodeSuggestions Model_

  - [ ] 1.2 Register `EpisodeSuggestions` in `PodedgeSchema`
    - Modify `PodedgeCore/Sources/PodedgeCore/Models/ModelContainerSetup.swift`
    - Add `EpisodeSuggestions.self` to the `modelTypes` array
    - _Requirements: EpisodeSuggestions Model_

- [ ] 2. Implement GenerateMetadataJobHandler
  - [ ] 2.1 Create `GenerateMetadataJobHandler`
    - Create `PodedgeCore/Sources/PodedgeCore/Services/GenerateMetadataJobHandler.swift`
    - Implement `JobHandler` and `Sendable` conformance with `handledKind: .generateMetadata`
    - Accept `MetadataGenerationService` via init
    - In `execute(jobID:container:)`: create `ModelContext`, fetch `Job` → `Episode` → transcript `Asset`, read `.txt` file (derive URL by replacing `.vtt` extension with `.txt` on `asset.localURL`), call `metadataService.generate(transcript:showTitle:episodeNumber:)`, delete any existing `EpisodeSuggestions` for the episode, insert new `EpisodeSuggestions`, save context
    - Follow the same fetch pattern used by `TranscribeJobHandler` (predicate + fetchLimit)
    - Throw `PodedgeError.notFound(entity: "TranscriptAsset")` if transcript asset is missing
    - _Requirements: GenerateMetadataJobHandler_

  - [ ] 2.2 Write property test: at most one EpisodeSuggestions per episode
    - **Property: Invariant 3 — At most one EpisodeSuggestions per episode**
    - **Validates: Requirements — EpisodeSuggestions Model (replace semantics)**
    - Create test in `PodedgeCore/Tests/PodedgeCoreTests/GenerateMetadataJobHandlerTests.swift`
    - Use Swift Testing `@Test(arguments:)` to run the handler N times for the same episode and assert `suggestionCount == 1`

  - [ ] 2.3 Write property test: chapter times are ordered
    - **Property: Invariant 5 — Every GeneratedChapter has startTime < endTime**
    - **Validates: Requirements — Invariants (chapter time ordering)**
    - Use Swift Testing `@Test(arguments:)` with varying chapter counts to verify `startTime < endTime` for all chapters decoded from `chaptersJSON`

  - [ ] 2.4 Write unit tests for GenerateMetadataJobHandler
    - Test handler creates `EpisodeSuggestions` record after successful generation (mock LLM)
    - Test handler replaces previous suggestions on re-run
    - Test handler throws and marks job failed when transcript asset is missing
    - _Requirements: GenerateMetadataJobHandler_

- [ ] 3. Register handler in AppServices
  - [ ] 3.1 Register `GenerateMetadataJobHandler` in `AppServices.bootstrap()`
    - Modify `Podedge/Podedge/AppServices.swift`
    - In `bootstrap()`, register `GenerateMetadataJobHandler(metadataService: metadataGenerationService)` alongside `TranscribeJobHandler`
    - Remove `.generateMetadata` from the placeholder handler loop (update the `where` clause)
    - _Requirements: GenerateMetadataJobHandler_

- [ ] 4. Checkpoint — Model and job handler complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. UI — Metadata tab suggestions
  - [ ] 5.1 Add suggestions display to MetadataTab
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `MetadataTab`
    - Add `@Query` for `EpisodeSuggestions` filtered by `episodeID`
    - When suggestions exist, show each suggested field (title, subtitle, description, keywords) alongside the current episode value with an "Apply" button per field
    - "Apply" copies the suggestion into the episode's `@Bindable` field
    - Add a "Regenerate" button that enqueues a new `.generateMetadata` job via `ToolBroker` (or directly via the environment's `appServices.jobScheduler`)
    - _Requirements: UI — Metadata Tab_

  - [ ] 5.2 Add suggested chapters to TranscriptTab
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `TranscriptTab`
    - Query `EpisodeSuggestions` and if `chaptersJSON` is non-empty, display suggested chapters with timestamps below the existing chapters section
    - Add an "Apply All" button that copies the suggested chapters JSON into `episode.chaptersJSON`
    - _Requirements: UI — Metadata Tab (Transcript/Chapters sub-requirement)_

- [ ] 6. UI — Promotion tab suggestions
  - [ ] 6.1 Update PromotionTabView to display generated blurbs
    - Modify `Podedge/Podedge/Views/Components/PromotionTabView.swift`
    - Accept or query `EpisodeSuggestions` to read platform blurbs (`blurbTwitter`, `blurbLinkedIn`, `blurbMastodon`, `blurbBluesky`, `blurbThreads`)
    - When suggestions exist, pre-populate `generatedText` with the blurb for the selected platform
    - Keep per-platform "Copy" button behavior
    - Wire "Generate Blurb" button to enqueue a `.generateMetadata` job (replacing the placeholder text)
    - _Requirements: UI — Promotion Tab_

  - [ ] 6.2 Write unit tests for suggestion apply logic
    - Test that tapping "Apply" on title copies `suggestedTitle` to `episode.title`
    - Test that "Apply All" chapters copies `chaptersJSON` to episode
    - Test that "Copy" places the correct platform blurb on pasteboard
    - _Requirements: UI — Metadata Tab, UI — Promotion Tab_

- [ ] 7. Final checkpoint — Full integration
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties (Invariants 3 and 5)
- Unit tests validate specific examples and edge cases
- The design specifies `blurbBluesky`/`blurbThreads` are derived from `mastodon` blurb in v1; this is handled in the `EpisodeSuggestions.init`
- `TranscribeJobHandler` pattern (fetch via predicate + fetchLimit, `ModelContext` from container) is the established convention for job handlers

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1"] },
    { "id": 2, "tasks": ["2.2", "2.3", "2.4", "3.1"] },
    { "id": 3, "tasks": ["5.1", "5.2", "6.1"] },
    { "id": 4, "tasks": ["6.2"] }
  ]
}
```
