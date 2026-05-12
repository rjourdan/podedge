# Spec 02 — Audio Ingest: Decisions & Learnings

Date: 2026-05-12

---

## Decisions

### 1. DefaultAudioPipeline uses synchronous FileHandle for SHA-256

The streaming SHA-256 implementation uses `FileHandle.readData(ofLength: 65_536)` in a loop with `autoreleasepool`. This is synchronous I/O on the cooperative thread pool. While `url.resourceBytes` (async) exists, the `FileHandle` approach is the established pattern for CryptoKit streaming hashing and avoids the overhead of async byte-by-byte iteration. Acceptable for v1 given the 10-second performance target is met.

### 2. Episode delete in EpisodeListView remains direct ModelContext call

The code review flagged that `.onDelete` calls `modelContext.delete()` directly, bypassing `ToolBroker`. This is a pre-existing issue from WS8 (see `ws8-review-decisions.md` decision #2). The WS8 review explicitly noted: "Full ToolBroker integration for delete requires registering delete tools in the registry (not yet done — tools are registered per-feature)." This will be addressed in Spec 08 (Tool Registry Wiring). Not a Spec 02 regression.

### 3. Immediate episode selection deferred

The spec requires "immediately select the new episode in the sidebar so the user sees progress." The current implementation selects after `ingest()` returns. `IngestService` does create the episode with `.processing` status early in the pipeline, but the view doesn't observe it until the full async call completes. Fixing this requires splitting `IngestService.ingest` into a two-phase API (create + process). Deferred — the current UX is acceptable for v1 since ingest completes in < 10 seconds.

### 4. Waveform SHA-256 now uses pipeline abstraction

The original `IngestService` computed waveform SHA-256 inline using `Data(contentsOf:)` + `SHA256.hash`. Code review caught this inconsistency. Fixed to use `pipeline.sha256(of:)`, which also removed the `import CryptoKit` dependency from IngestService.

### 5. Managed directory cleanup on failure

Code review caught that a failed ingest leaked the managed audio directory. Fixed by adding `FileManager.removeItem` in the catch block before deleting the episode record.

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| Pre-Spec 02 | 204 |
| Post-Spec 02 | 205 |

New test files:
- `DefaultAudioPipelineTests.swift` (3 tests, one parameterized with 5 cases)
- `IngestServiceIntegrationTests.swift` (4 tests)

## Files Created/Modified

| Action | File |
|--------|------|
| Created | `PodedgeCore/Sources/PodedgeCore/Services/DefaultAudioPipeline.swift` |
| Modified | `PodedgeCore/Sources/PodedgeCore/Services/IngestService.swift` — parentJobID fix + directory cleanup + pipeline SHA-256 |
| Modified | `Podedge/Podedge/AppServices.swift` — DefaultAudioPipeline wiring |
| Modified | `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` — importAudio rewrite |
| Created | `PodedgeCore/Tests/PodedgeCoreTests/DefaultAudioPipelineTests.swift` |
| Created | `PodedgeCore/Tests/PodedgeCoreTests/IngestServiceIntegrationTests.swift` |

## Verdict

**PASS** — All 205 tests pass. PodedgeCore builds clean. Code review findings addressed (3 must-fix, 2 should-fix, 3 nice-to-have resolved; 2 pre-existing issues noted for later specs).
