# WS3 Code Review — Decisions & Learnings

Date: 2026-04-30
Review gate: WS3 → WS4/WS5/WS6

---

## Decision Log

### 1. ToolResult.failure stores String, not Error

**Problem:** `ToolResult` is `Sendable` but `Error` is not. Swift 6 strict concurrency doesn't fully enforce this yet, but future toolchains will.

**Options considered:**
- `any Error & Sendable` — edge cases with existential types, not all errors conform
- `String` error description — simple, always Sendable, sufficient for UI display
- Custom `ToolError` struct — over-engineered for the use case

**Decision:** Use `case failure(String)`. Call sites pass `error.localizedDescription`. This is the simplest correct approach and matches how errors are displayed to users.

**Impact:** ToolBroker.swift, ToolBrokerTests.swift updated. Tests now assert on string content (`contains("not found")`) instead of pattern-matching `Error`.

---

### 2. Snapshot value types for protocol boundaries

**Problem:** `PromotionRenderer` and `DistributionTarget` accepted `@Model` classes (`Show`, `Episode`) in their protocol methods. These are not `Sendable` and can't safely cross isolation boundaries.

**Options considered:**
- Pass IDs + `ModelContainer` (like `JobHandler`) — forces implementations to manage their own ModelContext
- Pass value-type snapshots — clean separation, implementations get the data they need without SwiftData coupling
- Keep `@Model` types and require `@MainActor` on protocol methods — constrains all implementations to main thread

**Decision:** Created `ShowSnapshot` and `EpisodeSnapshot` structs in `Models/Snapshots.swift`. Added `.snapshot` computed properties on `Show` and `Episode` for easy conversion. Protocols now accept snapshot types.

**Rationale:** Snapshot types are the cleanest boundary. Protocol implementations (which may call network APIs) shouldn't need to know about SwiftData. The `.snapshot` property makes conversion trivial at the call site.

**Impact:** New file `Snapshots.swift`. `PromotionRenderer.render()` and `DistributionTarget.submit()` signatures changed. No existing implementations to update (protocols are abstract at this stage).

---

### 3. PodedgeError expanded for WS4-6

**Added cases:**
- `transcriptionFailed(reason:)` — for WhisperKit/transcription engine failures (WS5)
- `llmFailed(reason:)` — for LLM provider failures (WS5)
- `distributionFailed(target:reason:)` — includes target name for multi-directory context (WS6)
- `analyticsUnavailable(reason:)` — for OP3 API failures (WS6)

**Decision:** Add all four now so parallel WS4/5/6 implementers have the error types they need without modifying the shared error enum.

---

### 4. JobScheduler: maxAttempts + backoff enforcement

**Problem:** No retry cap. `backoffDelay()` was calculated but never enforced. Silent `try?` swallowed errors.

**Changes:**
- Added `maxAttempts` parameter (default 5). Jobs exceeding this are marked `.failed` with "Max attempts exceeded".
- Backoff enforcement: `pickAndRun` skips jobs whose `finishedAt + backoffDelay(attempt:)` is in the future.
- All `try?` replaced with `do/catch` blocks that log via `PodedgeLogger.scheduler`.

**Decision:** Keep the scheduler `@MainActor` for v1. The poll loop is lightweight (1-second sleep + fetch), and actual work is dispatched to handlers. Revisit if profiling shows main thread contention.

---

### 5. ToolBroker: extracted resolveTool helper

**Problem:** `invoke` and `invokeConfirmed` had identical tool-lookup + tier-check code.

**Decision:** Extracted `resolveTool(named:caller:)` private method. Uses a `resolveFailure` actor-isolated property to communicate the error without returning a tuple. This is a pragmatic pattern for actor methods that need to return both a value and an error path.

---

### 6. AnalyticsSnapshotData → AnalyticsFetchResult

**Problem:** `AnalyticsSnapshotData` was confusing alongside `AnalyticsSnapshot` (the `@Model` class).

**Decision:** Renamed to `AnalyticsFetchResult`. The "Fetch" prefix clarifies this is data returned from an API call, not a persisted model.

---

### 7. AWS credential redaction

**Added patterns:**
- `AKIA[A-Z0-9]{16}` — AWS access key IDs (always start with AKIA)
- `(?i)aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*\S+` — AWS secret key assignments

**Decision:** Added before WS6 (S3Host) to ensure credentials are never logged in plain text.

---

## SwiftData Testing Learnings

### Shared container pattern
SwiftData's `ModelContainer` crashes (signal trap) when multiple containers are created in the same process, even with unique names or in-memory stores. The solution is a single shared file-backed container (`TestDatabase.shared`) with per-test cleanup via `TestDatabase.reset()`.

### Enum predicates
SwiftData's `#Predicate` does not support captured enum constants in the Xcode test runner. The workaround is fetch-all-then-filter-in-memory. This is acceptable for small datasets (jobs, audit entries) but would need revisiting for large tables.

### Batch delete limitations
`context.delete(model: T.self)` (batch delete) fails with "Constraint trigger violation" when models have mandatory inverse relationships. The workaround is individual object deletion in dependency order (children before parents).

---

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| WS2 complete | 43 |
| WS3 complete | 64 |
| WS3 review fixes | 81 |

New test files added during review fixes:
- `KeychainServiceTests.swift` (6 tests)
- `AudioPipelineTests.swift` (6 tests)
- 3 new AWS redaction tests in `AuditLogTests.swift`
- 2 new JobScheduler integration tests (`start()` execution, `maxAttempts`)

---

## Verdict

**PASS** — All review findings addressed. WS4/WS5/WS6 can proceed in parallel.
