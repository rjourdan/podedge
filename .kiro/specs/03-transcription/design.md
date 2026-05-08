# Spec 03 — Transcription: Design

## Architecture Overview

`MLXTranscriptionEngine` wraps `mlx-audio-swift`'s `MLXAudioSTT` module behind the existing `TranscriptionEngine` protocol. It is constructed in `AppServices.init()` and passed to both `TranscriptionService` and `ModelManager`. `TranscribeJobHandler` is a `JobHandler` registered on `JobScheduler` during `bootstrap()`; it bridges the job system to `TranscriptionService`.

This shares the MLX Metal compute stack with Spec 04's `MLXLLMProvider`, eliminating the dual-runtime memory overhead that WhisperKit (CoreML/ANE) + MLX would have imposed.

The onboarding model download step calls `ModelManager.downloadModel(named:onProgress:)` directly. No new service is needed — `ModelManager` already handles progress tracking.

## Types

### New: `MLXTranscriptionEngine`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/MLXTranscriptionEngine.swift
import MLXAudioSTT
import MLXAudioCore

public actor MLXTranscriptionEngine: TranscriptionEngine {
    private let modelID: String
    private let modelsDirectory: URL
    private var loadedModel: (any STTModel)?

    public init(modelID: String, modelsDirectory: URL)

    public func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult
    public func availableModels() async throws -> [TranscriptionModelInfo]
    public func downloadModel(named name: String, progress: @Sendable (Double) -> Void) async throws
}
```

The actor isolation ensures the MLX model (which holds GPU state) is accessed from a single isolation domain.

`transcribe` loads audio via `MLXAudioCore.loadAudioArray(from:)`, calls `model.generate(audio:)`, converts the output segments into `TranscriptionSegment` values, and builds the VTT string in-process (no file I/O — `TranscriptionService` handles file writing).

`availableModels()` returns the hardcoded catalog; `isDownloaded` is determined by checking the filesystem for the model directory.

`downloadModel` uses `MLXAudioSTT`'s `fromPretrained` with a custom download directory, bridging progress via the callback.

### New: `TranscribeJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/TranscribeJobHandler.swift
public struct TranscribeJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .transcribe
    private let transcriptionService: TranscriptionService

    public init(transcriptionService: TranscriptionService)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

`execute` creates its own `ModelContext` from `container`, fetches the `Episode`, resolves the audio asset URL, calls `transcriptionService.transcribe(audioURL:language:outputDirectory:)`, creates the transcript `Asset`, updates `episode.transcriptAssetID`, and saves.

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
public let transcriptionEngine: MLXTranscriptionEngine
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
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/MLXTranscriptionEngine.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/TranscribeJobHandler.swift` |
| **Modify** | `PodedgeCore/Package.swift` — add mlx-audio-swift dependency (`MLXAudioSTT`, `MLXAudioCore`) |
| **Modify** | `Podedge/Podedge/AppServices.swift` — construct engine, register handler |
| **Modify** | `Podedge/Podedge/Views/Onboarding/OnboardingView.swift` — model download step |
| **Modify** | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — transcript tab |

## Data Flow

1. `JobScheduler` picks up `.transcribe` job → calls `TranscribeJobHandler.execute(jobID:container:)`.
2. Handler creates `ModelContext`, fetches `Episode` by `job.targetID`.
3. Resolves `episode.originalAssetID` → `Asset.localURL`.
4. Calls `transcriptionService.transcribe(audioURL:language:outputDirectory:)`.
5. `TranscriptionService` → `MLXTranscriptionEngine.transcribe(audioURL:language:)`.
6. Engine loads audio via `loadAudioArray`, runs STT model on Metal GPU → returns text/segments.
7. `TranscriptionService` writes `.vtt` and `.txt` to `outputDirectory`.
8. Handler creates `Asset(kind: .transcript, localURL: vttURL, sha256: ..., contentType: "text/vtt")`.
9. Sets `episode.transcriptAssetID`, saves via `ModelContext`.
10. Job marked `.done` by `JobScheduler`.
11. SwiftUI observes `episode.transcriptAssetID` change → transcript tab updates.

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.transcriptionFailed(reason:)` | MLX STT model throws | Job marked `.failed`; episode status unchanged (stays `.ready`) |
| `PodedgeError.notFound(entity: "Episode")` | Episode deleted before job runs | Job marked `.failed`; no-op |
| `PodedgeError.notFound(entity: "Asset")` | Audio asset missing | Job marked `.failed` |

## Concurrency Model

- `MLXTranscriptionEngine` is an `actor` — MLX model GPU state is not `Sendable`, so actor isolation is required.
- `TranscribeJobHandler` is a `Sendable` struct; it holds a reference to `TranscriptionService` (also an actor).
- `TranscribeJobHandler.execute` creates its own `ModelContext` (not `Sendable`) within the function scope.
- MLX inference is synchronous within the actor; no callback bridging needed (unlike WhisperKit).

## Dependency Alignment with Spec 04

Both this spec and Spec 04 depend on the MLX Swift stack:
- Spec 03: `mlx-audio-swift` → depends on `mlx-swift`
- Spec 04: `mlx-swift-examples` → depends on `mlx-swift`

They share the same underlying `MLX` and `MLXRandom` packages. At runtime, only one model (STT or LLM) should be loaded at a time to stay within GPU memory on 8 GB machines. `ModelManager` coordinates this: unload the STT model before loading the LLM, and vice versa.

## Test Strategy

**Unit tests** (`MLXTranscriptionEngineTests.swift`):
- `testAvailableModelsReturnsKnownModels` — catalog contains at least 3 entries.
- `testTranscribeShortFixture` — 5-second fixture → non-empty `plainText`, valid VTT header.

**Job handler tests** (`TranscribeJobHandlerTests.swift`):
- `testHandlerSetsTranscriptAssetID` — mock engine → episode gets `transcriptAssetID`.
- `testHandlerMarksJobDone` — job state is `.done` after successful execution.
- `testHandlerMarksJobFailedOnEngineError` — mock engine throws → job `.failed`.

**Property tests:**
- `testTranscriptAssetHasValidSHA256` (see requirements).
- `testTranscriptAssetIDSetAfterJob` (see requirements).

## Open Questions / Risks

1. **mlx-audio-swift maturity:** v0.1.2 as of May 2026. Pin to exact version and test against it. The API may change — isolate behind the `TranscriptionEngine` protocol so swapping is cheap.
2. **Model loading time:** Loading a 600 MB Parakeet model into GPU takes a few seconds. Lazy-load on first transcription request, not at app launch.
3. **Memory coordination with LLM:** On 8 GB Macs, the STT model (~600 MB GPU) and LLM model (~2.5 GB GPU) cannot coexist. `ModelManager` must unload one before loading the other. Confirm `mlx-audio-swift` exposes a way to release model memory.
4. **Audio format support:** Confirm `loadAudioArray` handles MP3 directly or whether we need to convert to WAV first via AVFoundation.
5. **Segment timestamps:** Verify that Parakeet's output includes word/segment-level timestamps suitable for VTT cue generation. GLM-ASR-Nano may not provide timestamps — document which models support timed output.
