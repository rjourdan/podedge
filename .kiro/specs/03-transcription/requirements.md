# Spec 03 — Transcription

On-device transcription converts episode audio into a timestamped transcript without sending audio to any external service. The transcript feeds the metadata generation pipeline (Spec 05) and is published alongside the episode as a `<podcast:transcript>` element. Currently no concrete `TranscriptionEngine` exists — `TranscriptionService` is wired to a protocol with no implementation, and `ModelManager` has no model catalog to offer. This spec adds `MLXTranscriptionEngine` (backed by mlx-audio-swift's STT module), wires it into the job pipeline, and connects the UI.

## User Stories

- As a user, I want on-device transcription of each episode so that I get a transcript without sending audio to any cloud. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want Podedge to download required local AI models during onboarding with clear progress so that I know when I'm ready to go. *(podedge-spec-user-stories.md — Onboarding)*
- As a user, I want transcription to run in the background without freezing the UI so that I can keep working. *(podedge-spec-user-stories.md — Performance)*
- As a user, I want all transcription to happen on-device so that my unreleased content stays local. *(podedge-spec-user-stories.md — Privacy)*

## Functional Requirements

### mlx-audio-swift Dependency

WHEN `Package.swift` is updated, THE SYSTEM SHALL add `mlx-audio-swift` as a dependency:
```
.package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", from: "0.1.2")
```
and add `"MLXAudioSTT"` and `"MLXAudioCore"` to the `PodedgeCore` target's dependencies.

### MLXTranscriptionEngine

WHEN `MLXTranscriptionEngine` is initialized with a model identifier, THE SYSTEM SHALL prepare to load the corresponding mlx-audio-swift STT model from the models directory.

WHEN `transcribe(audioURL:language:)` is called, THE SYSTEM SHALL use the loaded STT model to transcribe the audio and return a `TranscriptionResult` with `plainText`, `vttContent`, and `segments`.

WHEN `availableModels()` is called, THE SYSTEM SHALL return a catalog of supported STT models with their approximate sizes:
- `mlx-community/parakeet-tdt-0.6b-v3` (~600 MB) — default first-run model
- `mlx-community/GLM-ASR-Nano-2512-4bit` (~1 GB)
- `mlx-community/Qwen3-ASR-1.7B-bf16` (~3.4 GB)

WHEN `downloadModel(named:progress:)` is called, THE SYSTEM SHALL download the model from HuggingFace Hub to the local models directory and report progress via the callback.

### TranscribeJobHandler

WHEN `JobScheduler` picks up a job of kind `.transcribe`, THE SYSTEM SHALL execute `TranscribeJobHandler`:
1. Fetch the `Episode` by `job.targetID`.
2. Resolve the original audio asset URL.
3. Call `transcriptionService.transcribe(audioURL:language:outputDirectory:)`.
4. Create an `Asset` (kind `.transcript`) for the VTT file with its sha256 and byteSize.
5. Set `episode.transcriptAssetID` to the new asset's ID.
6. Set `episode.status = .ready` (if not already).
7. Save via `LibraryStore`.

IF the transcription engine throws, THE SYSTEM SHALL mark the job `.failed` with the error message and set `episode.status = .failed`.

### Model Download in Onboarding

WHEN the user reaches onboarding step 4 (model download), THE SYSTEM SHALL display a list of available transcription models with sizes and a "Download" button for each.

WHEN the user taps "Download" for a model, THE SYSTEM SHALL call `modelManager.downloadModel(named:onProgress:)` and show a progress bar.

WHEN the default model (`mlx-community/parakeet-tdt-0.6b-v3`) is not yet downloaded, THE SYSTEM SHALL pre-select it and recommend it as the first-run default.

WHEN at least one transcription model is downloaded, THE SYSTEM SHALL allow the user to advance past the model download step.

### UI Progress

WHILE a transcription job is running, THE SYSTEM SHALL show a progress indicator in the episode row (status dot animating) and in the menu bar accessory.

WHEN transcription completes, THE SYSTEM SHALL update the Transcript tab in `EpisodeEditorView` to show the VTT content.

## Invariants

1. Every `Asset` of kind `.transcript` has a non-empty `sha256`.
2. Every `Asset` of kind `.transcript` has `contentType == "text/vtt"`.
3. `episode.transcriptAssetID` is non-nil after a successful transcribe job.
4. The VTT file at `asset.localURL` exists on disk after a successful transcribe job.
5. No audio data is transmitted to any external network endpoint during transcription.

## Property-Based Testing Targets

```swift
// Invariant 1: transcript asset sha256 is 64 hex chars
@Test(arguments: ["short", "medium"])  // fixture names
func transcriptAssetHasValidSHA256(fixtureName: String) async throws {
    let env = try await TranscriptionTestEnv.make()
    let result = try await env.service.transcribe(
        audioURL: Fixtures.audio(named: fixtureName),
        language: nil,
        outputDirectory: env.outputDir
    )
    let sha = try SHA256.hash(data: Data(contentsOf: result.vttFileURL))
        .map { String(format: "%02x", $0) }.joined()
    #expect(sha.count == 64)
}

// Invariant 3: transcriptAssetID set after job
@Test
func transcriptAssetIDSetAfterJob() async throws {
    let env = try await JobTestEnv.make()
    let episode = try await env.ingest(Fixtures.shortMP3)
    try await env.runJob(kind: .transcribe, targetID: episode.id)
    let updated = try env.store.episode(id: episode.id)
    #expect(updated?.transcriptAssetID != nil)
}
```

## Non-Functional Requirements

- **Performance:** Transcription must run at ≤ 0.3× realtime on M2+ with the Parakeet model (a 10-minute episode transcribes in ≤ 3 minutes).
- **Privacy:** Audio files are processed entirely on-device by MLX. No network calls during transcription.
- **Reliability:** If the app is killed during transcription, the job resumes on next launch (`.running` → re-executed by `JobScheduler`).
- **Storage:** Transcript VTT and plain-text files are stored in `~/Library/Application Support/Podedge/transcripts/<episodeID>/`.

## Out of Scope for v1

- Word-level timestamp granularity in the UI (segments are sufficient).
- Speaker diarization (MLXAudioVAD/Sortformer available for v1.1).
- Transcript editing UI (display only in v1).
- Re-transcription with a different model after initial transcription.
