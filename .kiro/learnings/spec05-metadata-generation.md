# Spec 05 — Metadata Generation: Implementation Decisions

## Decisions

### 1. `@Query` fetches all `EpisodeSuggestions`, filters in computed property

SwiftData's `@Query` macro in struct views cannot accept dynamic predicates (the `episodeID` is not known at compile time). The standard workaround is:

```swift
@Query private var allSuggestions: [EpisodeSuggestions]
private var suggestions: EpisodeSuggestions? {
    allSuggestions.first { $0.episodeID == episode.id }
}
```

This is O(n) in the number of episodes with suggestions. For v1 (dozens of episodes), this is negligible. If performance becomes a concern, refactor to use `ModelContext.fetch` with a runtime predicate inside `.task {}`.

### 2. `blurbBluesky` and `blurbThreads` derived from Mastodon

The `MetadataGenerationService` generates three blurbs (Twitter, LinkedIn, Mastodon). For v1, Bluesky and Threads use the Mastodon blurb text since all three platforms have similar character limits. This is documented in the `EpisodeSuggestions.init` with inline comments.

### 3. Direct Job insertion bypasses ToolBroker (accepted debt)

The "Regenerate" and "Generate Blurb" buttons directly insert a `Job` into `ModelContext` rather than routing through `ToolBroker`. This is because Spec 08 (Tool Registry Wiring) hasn't been implemented yet — the `llm.generate_metadata` tool definition doesn't exist. Both call sites have a `// TODO: Route through ToolBroker once Spec 08 is complete` comment marking the debt.

### 4. `TestDatabase.reset()` updated to include `EpisodeSuggestions`

New SwiftData models must be added to `TestDatabase.reset()` in `TestSupport.swift`. The `EpisodeSuggestions` deletion is placed before `Episode` in the deletion order to respect referential ordering.

### 5. Transcript `.txt` file derived from `.vtt` asset URL

`TranscribeJobHandler` writes both `.vtt` and `.txt` files. `GenerateMetadataJobHandler` needs the `.txt` file. The convention is:
```swift
let txtURL = asset.localURL.deletingPathExtension().appendingPathExtension("txt")
```
This relies on the VTT asset's `localURL` having a `.vtt` extension, which is guaranteed by `TranscribeJobHandler`.

### 6. Empty ToolBroker in PublishTab was pre-existing — fixed during review

The PublishTab originally created `ToolBroker(registry: ToolRegistry())` — an empty registry that would never execute anything. Fixed to use `appServices.toolBroker`.

## Architecture Notes

- `GenerateMetadataJobHandler` follows the exact same pattern as `TranscribeJobHandler`: Sendable struct, creates its own `ModelContext`, fetches via predicate + fetchLimit.
- `EpisodeSuggestions` is a "side table" that keeps the `Episode` model clean. Only one suggestion record exists per episode at any time (invariant enforced by delete-then-insert in the handler).
- The UI uses `@Query` for live observation — when the handler saves new suggestions, the UI updates automatically.

## Open Items for Later Specs

- Spec 08: Wire "Regenerate" and "Generate Blurb" through ToolBroker
- v1.1: Extend `GeneratedBlurbs` to include native Bluesky/Threads variants instead of deriving from Mastodon
- v1.1: Consider truncating large transcripts to avoid exceeding the model's context window
