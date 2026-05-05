# Spec 02 — Audio Ingest

Audio ingest is the entry point for every episode. When a user drops an MP3 onto the app, the system must validate it, copy it to a managed location, compute its hash, probe its technical metadata, generate a waveform, and read any existing ID3 tags — all before the episode appears as `.ready` in the library. Currently `EpisodeListView.importAudio` bypasses `IngestService` entirely, writing directly to `ModelContext` with an empty SHA-256 and no pipeline processing. This spec wires the real pipeline.

## User Stories

- As a user, I want to create an episode by dropping an MP3 onto the show so that I can start publishing immediately. *(podedge-spec-user-stories.md — Episodes)*
- As a user, I want the app to validate the MP3 on import so that I'm warned about bad files before publishing. *(podedge-spec-user-stories.md — Episodes)*
- As a user, I want Podedge to compute an accurate duration, sha256, size, and bitrate on import so that the feed metadata is correct. *(podedge-spec-user-stories.md — MP3 Ingest Pipeline)*
- As a user, I want Podedge to generate a waveform preview on import so that the UI can show it. *(podedge-spec-user-stories.md — MP3 Ingest Pipeline)*
- As a user, I want Podedge to read existing ID3 tags so that my prior metadata is preserved. *(podedge-spec-user-stories.md — MP3 Ingest Pipeline)*
- As a user, I want ingest to finish in under 10 seconds for a one-hour MP3 on Apple Silicon. *(podedge-spec-user-stories.md — Performance)*

## Functional Requirements

### Drop Handling

WHEN a user drops one or more files onto `EpisodeListView`, THE SYSTEM SHALL filter to audio UTTypes (`.mp3`, `.mpeg4Audio`, `.audio`) and call `appServices.ingestService.ingest(fileURL:show:)` for each accepted file.

WHEN `EpisodeListView` receives a drop, THE SYSTEM SHALL NOT write any `Asset` or `Episode` records directly to `ModelContext`; all persistence is delegated to `IngestService`.

WHEN ingest begins, THE SYSTEM SHALL immediately select the new episode in the sidebar so the user sees progress.

### DefaultAudioPipeline

WHEN `AppServices` is initialized, THE SYSTEM SHALL construct a `DefaultAudioPipeline` that composes `MP3Validator`, `AudioProber`, `WaveformGenerator`, `ID3TagService`, and CryptoKit SHA-256 in that order.

WHEN `DefaultAudioPipeline.sha256(of:)` is called, THE SYSTEM SHALL compute the SHA-256 digest of the file using `CryptoKit.SHA256` and return a lowercase 64-character hex string.

WHEN `DefaultAudioPipeline.probe(url:)` is called, THE SYSTEM SHALL delegate to `AudioProber` and return an `AudioProbeResult`.

WHEN `DefaultAudioPipeline.waveform(url:sampleCount:)` is called, THE SYSTEM SHALL delegate to `WaveformGenerator` using a streaming approach that never loads the entire file into memory.

WHEN `DefaultAudioPipeline.readID3(url:)` is called, THE SYSTEM SHALL delegate to `ID3TagService` and return an `ID3Metadata`.

WHEN `DefaultAudioPipeline.writeID3(to:metadata:)` is called, THE SYSTEM SHALL delegate to `ID3TagService`.

### Ingest Pipeline Steps

WHEN `IngestService.ingest(fileURL:show:)` is called, THE SYSTEM SHALL execute these steps in order:
1. Copy the file to `~/Library/Application Support/Podedge/audio/<episodeID>/<episodeID>.mp3`.
2. Validate the file via `MP3Validator` (MPEG sync word check, not just MIME).
3. Compute SHA-256 via `pipeline.sha256(of:)`.
4. Probe via `pipeline.probe(url:)`.
5. Generate waveform (1000 samples) via `pipeline.waveform(url:sampleCount:)`.
6. Read ID3 tags via `pipeline.readID3(url:)`.
7. Create and persist an `Asset` (kind `.audioOriginal`) with the computed sha256, byteSize, duration.
8. Create and persist an `Episode` (status `.ready`) with title from ID3 or filename.
9. Create and persist a waveform `Asset` (kind `.waveform`) with its own sha256.
10. Enqueue a `Job(kind: .transcribe, targetID: episodeID)`.
11. Enqueue a `Job(kind: .generateMetadata, targetID: episodeID)` with `parentJobID` set to the transcribe job's ID.

IF any step throws, THE SYSTEM SHALL delete the partially-created `Episode` and any associated `Asset` records, then rethrow the error.

IF the file fails MP3 validation, THE SYSTEM SHALL surface a user-visible error alert in `EpisodeListView` with the validation reason.

### Job Dependency

WHEN the transcribe job is enqueued, THE SYSTEM SHALL set the `generateMetadata` job's `parentJobID` to the transcribe job's ID so that metadata generation waits for transcription to complete.

## Invariants

1. Every `Asset` of kind `.audioOriginal` created by ingest has a non-empty 64-character lowercase hex `sha256`.
2. Every `Asset` of kind `.audioOriginal` has `byteSize > 0`.
3. Every `Asset` of kind `.audioOriginal` has `durationSeconds > 0`.
4. Every `Episode` created by ingest has `status == .ready` after successful completion.
5. No `Episode` with `status == .processing` persists after a failed ingest.
6. The `generateMetadata` job always has `parentJobID == transcribeJob.id`.

## Property-Based Testing Targets

```swift
// Invariant 1: sha256 is always 64 lowercase hex chars
@Test(arguments: [1, 100, 1024, 65536, 1_048_576])
func sha256IsAlways64HexChars(byteCount: Int) async throws {
    let url = makeTempFile(bytes: byteCount)
    let pipeline = DefaultAudioPipeline()
    let hash = try await pipeline.sha256(of: url)
    #expect(hash.count == 64)
    #expect(hash.allSatisfy { $0.isHexDigit })
}

// Invariant 6: generateMetadata parentJobID == transcribeJob.id
@Test
func metadataJobParentIsTranscribeJob() async throws {
    let env = try await IngestTestEnv.make()
    let episode = try await env.ingestService.ingest(fileURL: Fixtures.shortMP3, show: env.show)
    let jobs = try env.store.jobs(for: episode.id)
    let transcribe = try #require(jobs.first { $0.kind == .transcribe })
    let metadata = try #require(jobs.first { $0.kind == .generateMetadata })
    #expect(metadata.parentJobID == transcribe.id)
}
```

## Non-Functional Requirements

- **Performance:** Ingest (hash + probe + waveform) for a 1-hour MP3 must complete in ≤ 10 s on M1.
- **Memory:** Waveform generation must not load the entire audio file into memory; use streaming PCM reads.
- **Privacy:** The audio file never leaves the device during ingest; it is only copied to the app sandbox.
- **Reliability:** A crash during ingest must not leave orphaned `Episode` records in `.processing` state. On next launch, `JobScheduler` resumes `.running` jobs; `IngestService` must be idempotent for re-runs.

## Out of Scope for v1

- Audio format conversion (non-MP3 inputs).
- LUFS normalization during ingest.
- Duplicate detection by SHA-256 across shows.
- Batch ingest of multiple files simultaneously.
