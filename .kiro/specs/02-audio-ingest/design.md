# Spec 02 — Audio Ingest: Design

## Architecture Overview

`DefaultAudioPipeline` is a concrete `AudioPipeline` that composes the four existing utility types (`MP3Validator`, `AudioProber`, `WaveformGenerator`, `ID3TagService`) plus CryptoKit SHA-256 into a single `Sendable` struct. It replaces `PassthroughPipeline` as the production implementation and is constructed inside `AppServices.init()`.

`EpisodeListView.importAudio` is replaced with a call to `appServices.ingestService.ingest(fileURL:show:)`. The view no longer touches `ModelContext` directly for episode creation. `IngestService` already implements the full pipeline; the only missing piece is the real `AudioPipeline` and the UI wiring.

## Types

### New: `DefaultAudioPipeline`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/DefaultAudioPipeline.swift
public struct DefaultAudioPipeline: AudioPipeline, Sendable {
    public init()
    public func sha256(of url: URL) async throws -> String
    public func probe(url: URL) async throws -> AudioProbeResult
    public func waveform(url: URL, sampleCount: Int) async throws -> [Float]
    public func readID3(url: URL) async throws -> ID3Metadata
    public func writeID3(to url: URL, metadata: ID3Metadata) async throws
}
```

Each method delegates to the corresponding utility:
- `sha256` → `CryptoKit.SHA256` streaming over 64 KB chunks.
- `probe` → `AudioProber.probe(url:)`.
- `waveform` → `WaveformGenerator.generate(url:sampleCount:)`.
- `readID3` → `ID3TagService.read(url:)`.
- `writeID3` → `ID3TagService.write(to:metadata:)`.

### Modified: `EpisodeListView`

```swift
// Podedge/Podedge/Views/Sidebar/EpisodeListView.swift
// Replace importAudio(from:) with:
private func importAudio(from tempURL: URL) {
    guard let show = resolvedShow else { return }
    Task { @MainActor in
        do {
            let episode = try await appServices.ingestService.ingest(fileURL: tempURL, show: show)
            selectedEpisodeID = episode.persistentModelID
        } catch {
            ingestError = error
            showingIngestError = true
        }
    }
}
```

Add `@State private var ingestError: Error?` and `@State private var showingIngestError = false` with a corresponding `.alert` modifier.

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
public let audioPipeline: any AudioPipeline  // = DefaultAudioPipeline()
public let ingestService: IngestService       // = IngestService(pipeline: audioPipeline, store: libraryStore, scheduler: jobScheduler)
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/DefaultAudioPipeline.swift` |
| **Modify** | `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` — replace `importAudio` body |
| **Modify** | `Podedge/Podedge/AppServices.swift` — wire `DefaultAudioPipeline` → `IngestService` |

No changes to `IngestService.swift`, `MP3Validator.swift`, `AudioProber.swift`, `WaveformGenerator.swift`, or `ID3TagService.swift` — they are already correct.

## Data Flow

1. User drops MP3 → `EpisodeListView.handleDrop` → copies to temp location.
2. `importAudio(from:)` → `appServices.ingestService.ingest(fileURL:show:)`.
3. `IngestService` copies file to `~/Library/Application Support/Podedge/audio/<id>/<id>.mp3`.
4. `MP3Validator.validate(url:)` — throws `PodedgeError.invalidMP3` on failure.
5. `DefaultAudioPipeline.sha256(of:)` — CryptoKit streaming hash.
6. `DefaultAudioPipeline.probe(url:)` — `AudioProber` via AVFoundation.
7. `DefaultAudioPipeline.waveform(url:sampleCount: 1000)` — streaming PCM peaks.
8. `DefaultAudioPipeline.readID3(url:)` — `ID3TagService`.
9. `LibraryStore.addAsset` + `addEpisode` + `save()`.
10. `JobScheduler.enqueue(transcribeJob)` + `enqueue(metadataJob)`.
11. `IngestService` returns `Episode` → view selects it.

On failure at any step: `LibraryStore.deleteEpisode` + `save()`, error propagated to view.

## Error Model

| Error | Trigger | User-visible |
|-------|---------|--------------|
| `PodedgeError.invalidMP3(reason:)` | `MP3Validator` rejects file | Alert in `EpisodeListView` |
| `PodedgeError.uploadFailed` | Not applicable during ingest | — |
| Any `Error` from pipeline | SHA-256, probe, waveform, ID3 | Alert with `error.localizedDescription` |

## Concurrency Model

- `IngestService` is `@MainActor`-isolated (reads/writes `LibraryStore` and `JobScheduler`).
- `DefaultAudioPipeline` methods are `async` and run on the cooperative thread pool (no actor isolation). They are `Sendable` structs.
- `EpisodeListView.importAudio` dispatches via `Task { @MainActor in }` — already on main actor.
- The `NSItemProvider` callback in `handleDrop` is on an arbitrary thread; the `Task { @MainActor in }` bridge is correct.

## Test Strategy

**Unit tests** (`DefaultAudioPipelineTests.swift`):
- `testSHA256Is64HexChars` — property test over various file sizes (see requirements).
- `testSHA256DeterministicForSameFile` — same file → same hash.
- `testProbeReturnsPositiveDuration` — fixture MP3 → `duration > 0`.
- `testWaveformHasRequestedSampleCount` — `waveform(url:sampleCount: 500).count == 500`.

**Integration tests** (`IngestServiceIntegrationTests.swift`):
- `testIngestCreatesEpisodeAndAssets` — fixture MP3 → episode `.ready`, two assets (audio + waveform).
- `testIngestEnqueuesTranscribeAndMetadataJobs` — jobs enqueued with correct parent relationship.
- `testIngestFailureDeletesEpisode` — corrupted MP3 → no orphaned episode.
- `testMetadataJobParentIsTranscribeJob` — property test (see requirements).

## Open Questions / Risks

1. **`AudioProber` uses AVFoundation `AVAsset`:** `AVAsset` is not `Sendable`. Confirm that `AudioProber` wraps it in a non-isolated context correctly (it currently uses `AVAsset(url:)` synchronously). If Swift 6 strict concurrency flags this, wrap in `withCheckedThrowingContinuation`.
2. **Temp file cleanup:** The `NSItemProvider` callback copies to a temp URL. After `IngestService` copies it to the managed directory, the temp file should be deleted. Add cleanup in `EpisodeListView` after the `ingest` call returns.
3. **Large file UI feedback:** For files > 100 MB, ingest may take several seconds. Consider showing a progress indicator in the episode row while `status == .processing`.
