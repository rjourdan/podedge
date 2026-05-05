# Spec 05 — Metadata Generation: Design

## Architecture Overview

A new `@Model EpisodeSuggestions` persists the LLM output as JSON blobs on a side table, keeping the `Episode` model clean. `GenerateMetadataJobHandler` bridges the job system to `MetadataGenerationService`. The UI reads `EpisodeSuggestions` via a `@Query` and presents each field with Apply/Regenerate affordances.

## Types

### New: `EpisodeSuggestions` (SwiftData model)

```swift
// PodedgeCore/Sources/PodedgeCore/Models/EpisodeSuggestions.swift
@Model public final class EpisodeSuggestions {
    @Attribute(.unique) public var id: UUID
    public var episodeID: UUID
    public var generatedAt: Date
    public var suggestedTitle: String
    public var suggestedSubtitle: String
    public var suggestedDescriptionHTML: String
    public var keywordsJSON: String        // JSON array of strings
    public var chaptersJSON: String        // JSON array of GeneratedChapter
    public var blurbTwitter: String
    public var blurbLinkedIn: String
    public var blurbMastodon: String
    public var blurbBluesky: String
    public var blurbThreads: String

    public init(episodeID: UUID, metadata: GeneratedMetadata)
}
```

`blurbBluesky` and `blurbThreads` are populated from `metadata.blurbs.mastodon` in v1 (same text, different platform label). The `SocialBlurbRenderer` already generates per-platform variants; wire those in.

`EpisodeSuggestions` is added to `PodedgeSchema.allModels` so it is included in the `ModelContainer`.

### New: `GenerateMetadataJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/GenerateMetadataJobHandler.swift
public struct GenerateMetadataJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .generateMetadata
    private let metadataService: MetadataGenerationService

    public init(metadataService: MetadataGenerationService)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

`execute` steps:
1. Create `ModelContext` from `container`.
2. Fetch `Job` by `jobID`, then `Episode` by `job.targetID`.
3. Fetch transcript `Asset` via `episode.transcriptAssetID`; read `.txt` file from `asset.localURL` (replace `.vtt` extension with `.txt`).
4. Call `metadataService.generate(transcript:showTitle:episodeNumber:)`.
5. Delete any existing `EpisodeSuggestions` for this episode.
6. Insert new `EpisodeSuggestions(episodeID: episode.id, metadata: result)`.
7. Save context.

### Modified: `ModelContainerSetup` / `PodedgeSchema`

```swift
// PodedgeCore/Sources/PodedgeCore/Models/ModelContainerSetup.swift
// Add EpisodeSuggestions.self to the schema array
```

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
// bootstrap() registers GenerateMetadataJobHandler(metadataService: metadataGenerationService)
```

### Modified: `EpisodeEditorView`

```swift
// Podedge/Podedge/Views/Content/EpisodeEditorView.swift
// Metadata tab: @Query for EpisodeSuggestions where episodeID == episode.id
// Show suggestion + Apply button per field
// Regenerate button enqueues new .generateMetadata job via ToolBroker

// Transcript/Chapters tab: show chaptersJSON from EpisodeSuggestions
// Apply All button copies chapters to episode.chaptersJSON

// Promotion tab: show blurb fields from EpisodeSuggestions
// Copy button per platform
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Models/EpisodeSuggestions.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/GenerateMetadataJobHandler.swift` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Models/ModelContainerSetup.swift` — add `EpisodeSuggestions` |
| **Modify** | `Podedge/Podedge/AppServices.swift` — register handler |
| **Modify** | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — suggestions UI |

## Data Flow

1. `.generateMetadata` job picked up by `JobScheduler`.
2. `GenerateMetadataJobHandler.execute` → reads transcript `.txt` from disk.
3. `MetadataGenerationService.generate` → 3 concurrent LLM calls (metadata, chapters, blurbs).
4. Results assembled into `GeneratedMetadata`.
5. Old `EpisodeSuggestions` deleted (if any), new one inserted.
6. `ModelContext.save()`.
7. SwiftUI `@Query` observes change → Metadata tab updates.

**Regenerate flow:**
1. User taps "Regenerate" → `ToolBroker.invoke("llm.generate_metadata", input: episodeID)`.
2. Tool enqueues new `.generateMetadata` job.
3. Job runs → replaces `EpisodeSuggestions`.

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.notFound(entity: "Episode")` | Episode deleted before job runs | Job `.failed`, no-op |
| `PodedgeError.notFound(entity: "TranscriptAsset")` | Transcript not yet generated | Job `.failed`; user sees "Transcript required" in UI |
| `PodedgeError.llmFailed(reason:)` | LLM inference error | Job `.failed`; Regenerate button remains available |

## Concurrency Model

- `GenerateMetadataJobHandler` is a `Sendable` struct.
- `execute` creates its own `ModelContext` (not `Sendable`) within the function scope.
- `MetadataGenerationService` is a `Sendable` struct; its three concurrent LLM calls use `async let`.
- `MLXLLMProvider` is an `actor`; concurrent calls are serialized by the actor.

## Test Strategy

**Unit tests** (`GenerateMetadataJobHandlerTests.swift`):
- `testHandlerCreatesSuggestionsRecord` — mock LLM → `EpisodeSuggestions` inserted.
- `testHandlerReplacesPreviousSuggestions` — run twice → only one record.
- `testHandlerFailsWithoutTranscript` — no transcript asset → job `.failed`.

**Property tests:**
- `testAtMostOneSuggestionsPerEpisode` (see requirements).
- `testChapterTimesAreOrdered` (see requirements).

**Integration:** `MetadataGenerationServiceTests.swift` already tests the service with a mock provider. Add an integration test that uses the real `MLXLLMProvider` with the tiny test model.

## Open Questions / Risks

1. **Transcript file path convention:** `TranscribeJobHandler` writes `<baseName>.vtt` and `<baseName>.txt`. `GenerateMetadataJobHandler` needs the `.txt` file. Confirm the naming convention is consistent — the `.txt` URL should be derivable from the VTT asset's `localURL` by replacing the extension.
2. **`blurbBluesky` / `blurbThreads` content:** `SocialBlurbRenderer` generates X, Bluesky, Mastodon, LinkedIn, Threads variants. `MetadataGenerationService` currently only generates twitter/linkedin/mastodon. Either extend `GeneratedBlurbs` to include bluesky/threads, or derive them from mastodon in `EpisodeSuggestions.init`. Decide before implementation.
3. **Large transcripts:** A 3-hour episode transcript may exceed the 3B model's context window (~4K tokens). Consider truncating to the first 3000 words for metadata generation, with a UI note that the summary is based on a partial transcript.
