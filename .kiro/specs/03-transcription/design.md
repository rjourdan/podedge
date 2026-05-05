# Spec 03 — Transcription: Design

## Architecture Overview

`WhisperKitTranscriptionEngine` wraps the WhisperKit Swift package behind the existing `TranscriptionEngine` protocol. It is constructed in `AppServices.init()` and passed to both `TranscriptionService` and `ModelManager`. `TranscribeJobHandler` is a `JobHandler` registered on `JobScheduler` during `bootstrap()`; it bridges the job system to `TranscriptionService`.

The onboarding model download step calls `ModelManager.downloadModel(named:onProgress:)` directly. No new service is needed — `ModelManager` already handles progress tracking.

## Types

### New: `WhisperKitTranscriptionEngine`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/WhisperKitTranscriptionEngine.swift
import WhisperKit

public actor WhisperKitTranscriptionEngine: TranscriptionEngine {
    public init(modelName: String, modelsDirectory: URL)
    public func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult
    public func availableModels() async throws -> [TranscriptionModelInfo]
    public func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws
}
```

The actor isolation ensures the WhisperKit pipeline (which is not `Sendable`) is accessed from a single isolation domain.

`transcribe` converts WhisperKit's `TranscriptionResult` segments into `TranscriptionSegment` values and builds the VTT string in-process (no file I/O — `TranscriptionService` handles file writing).

`availableModels()` returns the hardcoded catalog; `isDownloaded` is determined by checking the filesystem for the model directory.

`downloadModel` calls `WhisperKit.download(variant:downloadBase:useBackgroundSession:)` and bridges progress via the callback.

### New: `TranscribeJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/TranscribeJobHandler.swift
public struct TranscribeJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .transcribe
    private let transcriptionService: TranscriptionService
    private let modelContainer: ModelContainer  // injected at registration

    public init(transcriptionService: TranscriptionService)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

`execute` creates its own `ModelContext` from `container`, fetches the `Episode`, resolves the audio asset URL, calls `transcriptionService.transcribe(audioURL:language:outputDirectory:)`, creates the transcript `Asset`, updates `episode.transcriptAssetID`, and saves.

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
public let transcriptionEngine: WhisperKitTranscriptionEngine
public let transcriptionService: TranscriptionService  // already exists
public let modelManager: ModelManager                  // already exists
```

`bootstrap()` registers `TranscribeJobHandler(transcriptionService: transcriptionService)`.

### Modified: `OnboardingView`

```swift
// Podedge/Podedge/Views/Onboarding/OnboardingView.swift
// Step 4: model download
// Calls appServices.modelManager.availableModels() on appear
// Shows list with download buttons; progress from modelManager.downloadProgress
// "Continue" enabled when modelManager.isModelDownloaded(named: defaultModel)
```

### Modified: `EpisodeEditorView` — Transcript Tab

```swift
// Podedge/Podedge/Views/Content/EpisodeEditorView.swift
// Transcript tab: if episode.transcriptAssetID != nil, load VTT from asset.localURL
// Else: show "Transcription in progress…" with ProgressView if job is running
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/WhisperKitTranscriptionEngine.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/TranscribeJobHandler.swift` |
| **Modify** | `PodedgeCore/Package.swift` — add WhisperKit dependency |
| **Modify** | `Podedge/Podedge/AppServices.swift` — construct engine, register handler |
| **Modify** | `Podedge/Podedge/Views/Onboarding/OnboardingView.swift` — model download step |
| **Modify** | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — transcript tab |

## Data Flow

1. `JobScheduler` picks up `.transcribe` job → calls `TranscribeJobHandler.execute(jobID:container:)`.
2. Handler creates `ModelContext`, fetches `Episode` by `job.targetID`.
3. Resolves `episode.originalAssetID` → `Asset.localURL`.
4. Calls `transcriptionService.transcribe(audioURL:language:outputDirectory:)`.
5. `TranscriptionService` → `WhisperKitTranscriptionEngine.transcribe(audioURL:language:)`.
6. WhisperKit processes audio on-device → returns segments.
7. `TranscriptionService` writes `.vtt` and `.txt` to `outputDirectory`.
8. Handler creates `Asset(kind: .transcript, localURL: vttURL, sha256: ..., contentType: "text/vtt")`.
9. Sets `episode.transcriptAssetID`, saves via `ModelContext`.
10. Job marked `.done` by `JobScheduler`.
11. SwiftUI observes `episode.transcriptAssetID` change → transcript tab updates.

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.transcriptionFailed(reason:)` | WhisperKit throws | Job marked `.failed`; episode status unchanged (stays `.ready`) |
| `PodedgeError.notFound(entity: "Episode")` | Episode deleted before job runs | Job marked `.failed`; no-op |
| `PodedgeError.notFound(entity: "Asset")` | Audio asset missing | Job marked `.failed` |

## Concurrency Model

- `WhisperKitTranscriptionEngine` is an `actor` — WhisperKit's pipeline is not `Sendable`, so actor isolation is required.
- `TranscribeJobHandler` is a `Sendable` struct; it holds a reference to `TranscriptionService` (also an actor).
- `TranscribeJobHandler.execute` creates its own `ModelContext` (not `Sendable`) within the function scope.
- Progress updates from WhisperKit's callback are bridged to the actor via `Task { await engine.updateProgress(...) }`.

## Test Strategy

**Unit tests** (`WhisperKitTranscriptionEngineTests.swift`):
- `testAvailableModelsReturnsKnownModels` — catalog contains at least 4 entries.
- `testTranscribeShortFixture` — 5-second fixture → non-empty `plainText`, valid VTT header.

**Job handler tests** (`TranscribeJobHandlerTests.swift`):
- `testHandlerSetsTranscriptAssetID` — mock engine → episode gets `transcriptAssetID`.
- `testHandlerMarksJobDone` — job state is `.done` after successful execution.
- `testHandlerMarksJobFailedOnEngineError` — mock engine throws → job `.failed`.

**Property tests:**
- `testTranscriptAssetHasValidSHA256` (see requirements).
- `testTranscriptAssetIDSetAfterJob` (see requirements).

## Open Questions / Risks

1. **WhisperKit API stability:** The WhisperKit API changed significantly between 0.8 and 0.9. Pin to `from: "0.9.0"` and test against the exact version. Check whether `WhisperKit.download(variant:)` is the correct API name in 0.9+.
2. **Model directory path:** WhisperKit expects models in a specific directory structure. Confirm whether `ModelManager.storageDirectory` matches WhisperKit's expected path, or whether `WhisperKitTranscriptionEngine` needs to pass a custom `modelFolder` parameter.
3. **Background execution:** WhisperKit transcription can take minutes. Ensure `TranscribeJobHandler.execute` is not cancelled by the OS when the app is backgrounded. Consider registering a `BGProcessingTask` for long transcriptions (Spec 06 covers BGTask infrastructure).
4. **Language detection:** WhisperKit supports auto-detection when `language == nil`. Confirm this works correctly for non-English podcasts.
