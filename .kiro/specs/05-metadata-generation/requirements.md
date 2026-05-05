# Spec 05 — Metadata Generation

After transcription completes, the LLM generates a title, subtitle, description, chapter markers, keywords, and social blurbs. These are suggestions — the user reviews and approves each field before it is committed to the episode. Currently `MetadataGenerationService` produces a `GeneratedMetadata` value type but there is no `@Model` to persist suggestions, no job handler to run the generation, and no UI to display the drafts. This spec adds all three.

## User Stories

- As a user, I want Podedge to suggest a title, subtitle, description, and SEO keywords from the transcript so that writing show notes is faster. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want Podedge to suggest chapter markers with timestamps from the transcript so that I can add chapters without manual scrubbing. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want Podedge to draft social-media copy so that I can promote without starting from a blank page. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want every AI suggestion to be editable and opt-in per-field so that I stay in control of my show's voice. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want suggestions to regenerate on demand so that I can explore alternatives. *(podedge-spec-user-stories.md — Local AI Assistance)*

## Functional Requirements

### EpisodeSuggestions Model

WHEN `GenerateMetadataJobHandler` completes successfully, THE SYSTEM SHALL persist an `EpisodeSuggestions` record linked to the episode.

IF an `EpisodeSuggestions` record already exists for the episode, THE SYSTEM SHALL replace it (delete old, insert new) so that regeneration always reflects the latest transcript.

### GenerateMetadataJobHandler

WHEN `JobScheduler` picks up a job of kind `.generateMetadata`, THE SYSTEM SHALL execute `GenerateMetadataJobHandler`:
1. Fetch the `Episode` by `job.targetID`.
2. Resolve the transcript plain-text asset (via `episode.transcriptAssetID`).
3. Read the plain-text transcript from disk.
4. Call `metadataGenerationService.generate(transcript:showTitle:episodeNumber:)`.
5. Persist the result as an `EpisodeSuggestions` record.
6. Save via `LibraryStore`.

IF the transcript asset is missing, THE SYSTEM SHALL throw `PodedgeError.notFound(entity: "TranscriptAsset")` and mark the job `.failed`.

IF `MetadataGenerationService.generate` throws, THE SYSTEM SHALL mark the job `.failed` with the error message; the episode status is unchanged.

### UI — Metadata Tab

WHEN `EpisodeEditorView` opens the Metadata tab and `EpisodeSuggestions` exists for the episode, THE SYSTEM SHALL show each suggested field (title, subtitle, description, keywords) alongside the current episode field value.

WHEN the user taps "Apply" next to a suggested field, THE SYSTEM SHALL copy the suggestion into the episode's editable field.

WHEN the user taps "Regenerate" in the Metadata tab, THE SYSTEM SHALL enqueue a new `.generateMetadata` job for the episode (replacing any existing pending job).

WHEN `EpisodeEditorView` opens the Transcript/Chapters tab and `EpisodeSuggestions.chapters` is non-empty, THE SYSTEM SHALL display the suggested chapters with timestamps and an "Apply All" button.

### UI — Promotion Tab

WHEN `EpisodeEditorView` opens the Promotion tab and `EpisodeSuggestions` exists, THE SYSTEM SHALL display the generated blurbs for each platform (X/Twitter, LinkedIn, Mastodon, Bluesky, Threads).

WHEN the user taps "Copy" next to a blurb, THE SYSTEM SHALL copy the text to the system clipboard.

## Invariants

1. `EpisodeSuggestions.episodeID` is always equal to the `Episode.id` it belongs to.
2. `EpisodeSuggestions.generatedAt` is always set to the time the job completed.
3. At most one `EpisodeSuggestions` record exists per episode at any time.
4. `EpisodeSuggestions.suggestedTitle` is never an empty string after successful generation.
5. Every `GeneratedChapter` in `EpisodeSuggestions.chaptersJSON` has `startTime < endTime`.

## Property-Based Testing Targets

```swift
// Invariant 3: at most one EpisodeSuggestions per episode
@Test(arguments: 1...5)
func atMostOneSuggestionsPerEpisode(runCount: Int) async throws {
    let env = try await MetadataTestEnv.make()
    for _ in 0..<runCount {
        try await env.runGenerateMetadataJob(episodeID: env.episode.id)
    }
    let count = try env.store.suggestionCount(for: env.episode.id)
    #expect(count == 1)
}

// Invariant 5: chapter startTime < endTime
@Test(arguments: [1, 5, 20, 50])
func chapterTimesAreOrdered(chapterCount: Int) throws {
    let chapters = (0..<chapterCount).map { i in
        GeneratedChapter(title: "Ch \(i)", startTime: Double(i * 60), endTime: Double(i * 60 + 59))
    }
    for chapter in chapters {
        #expect(chapter.startTime < chapter.endTime)
    }
}
```

## Non-Functional Requirements

- **Performance:** Metadata generation (3 concurrent LLM calls) must complete in ≤ 30 s on M2 with the 3B model for a 45-minute transcript.
- **Privacy:** Transcript text is processed entirely on-device; it is never sent to an external endpoint in v1.
- **Reliability:** A failed generation job does not corrupt the episode record. The user can trigger regeneration manually.

## Out of Scope for v1

- Automatic application of suggestions without user review.
- Per-field confidence scores.
- Suggestion history (only the latest generation is kept).
- Cloud LLM providers for metadata generation (v1.1).
