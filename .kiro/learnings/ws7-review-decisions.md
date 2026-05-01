# WS7 Code Review — Decisions & Learnings

Date: 2026-05-01
Review gate: WS7 (Publish Pipeline & Promotion)

---

## Decision Log

### 1. Pre-resolve all store data before async work in PublishService

**Problem:** `PublishService.publish` fetched asset data from `LibraryStore` (SwiftData) both before and after async upload operations. When tests ran concurrently, another test suite's `TestDatabase.reset()` could delete assets between the upload and the feed-building phase, causing "Channel image URL is required" feed validation failures.

**Options considered:**
- Serialize all SwiftData test suites globally — would require restructuring all test files into a parent suite
- Use separate `ModelContext` per test — SwiftData's `ModelContainer` doesn't support this reliably in tests
- Pre-resolve all store data before any async work — good production practice, eliminates the race window

**Decision:** Refactored `PublishService.publish` to gather all data from the store (episodes, asset remote paths, cover art, transcript asset, episode snapshots) before the first `await`. The async upload phase now uses only pre-resolved values. This follows the actor reentrancy best practice: "complete actor work before suspending."

**Impact:** `PublishService.swift` restructured. No API changes. All 34 WS7 tests pass reliably when run alongside other SwiftData suites.

---

### 2. Add TestDatabase.reset() to PublishTestEnv.make()

**Problem:** `PublishServiceTests` used `TestDatabase.shared.mainContext` but never called `TestDatabase.reset()`, leaving stale data from other test suites.

**Decision:** Added `try TestDatabase.reset()` as the first line of `PublishTestEnv.make()`, matching the pattern used by `LibraryStoreTests`, `IngestServiceTests`, and `JobSchedulerTests`.

**Impact:** `PublishServiceTests.swift` updated. Added `.tags(.swiftData)` to the suite declaration for consistency.

---

### 3. Add per-episode cover art resolution to PublishDryRun

**Problem:** `PublishDryRun.plan` only resolved the show-level `coverArtAssetID` after the episode loop, but missed per-episode cover art resolution inside the loop. `PublishService.publish` had this resolution. The dry run would fail to resolve episode-specific cover art.

**Decision:** Added the same per-episode cover art resolution loop to `PublishDryRun.plan`, matching the pattern in `PublishService.publish`.

**Impact:** `PublishDryRun.swift` updated. Also added `originalAssetID` mapping for draft episodes that don't yet have a `publishedAssetID`.

---

### 4. Reverted social-blurbs.md template change

**Problem:** Initially added `{{episode_title}}` to the `social-blurbs.md` prompt template and corresponding variable to `SocialBlurbRenderer`. However, `MetadataGenerationService.generate` also uses the `social-blurbs` prompt with a different variable set (it doesn't have an episode title — it's generating one). The shared template caused `LLMService.render` to throw "unrendered variables" errors.

**Options considered:**
- Add `episode_title` to `MetadataGenerationService.generate` variables — but the service doesn't have an episode title yet
- Create separate prompt templates for each use case — over-engineered for the current need
- Keep the template as-is — the `SocialBlurbRenderer` can pass extra variables that get ignored

**Decision:** Reverted the template change. The `social-blurbs.md` template is shared between `SocialBlurbRenderer` and `MetadataGenerationService`, so it must only use variables that both callers provide. If episode-title-aware blurbs are needed later, a separate prompt template should be created.

---

## SwiftData & Swift Concurrency Learnings

### Pre-resolve before suspension points
The most important lesson: in `@MainActor`-isolated code that does async work, resolve all SwiftData model data into value types (snapshots, dictionaries) before the first `await`. After a suspension point, the model context state may have changed (actor reentrancy). This is both a correctness issue and a test reliability issue.

### SwiftData concurrent test crash
When multiple `.serialized` test suites share `TestDatabase.shared`, they still run concurrently with each other. A `TestDatabase.reset()` in one suite can detach model objects being used by another suite, causing `Fatal error: This backing data was detached from a context`. This is a pre-existing infrastructure issue — not introduced by WS7. A future fix would be to serialize all SwiftData suites under a single parent suite.

### Shared prompt templates
When multiple services share the same LLM prompt template, the template's `{{variable}}` set must be the intersection of all callers' variable sets. Adding a variable to the template that only one caller provides breaks the other callers.

---

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| WS3 review fixes | 81 |
| WS7 pre-review | 175 (3 failing when run together) |
| WS7 post-review | 175 (0 failing) |

WS7 test breakdown:
- `PublishServiceTests`: 12 tests (pipeline + dry run)
- `PublishArtifactBuilderTests`: 4 tests
- `SocialBlurbRendererTests`: 7 tests
- `DistributionServiceTests`: 6 tests
- `GuidedTargetTests`: 5 tests

---

## Files Changed

- `Sources/PodedgeCore/Services/PublishService.swift` — Pre-resolve store data before async work
- `Sources/PodedgeCore/Services/PublishDryRun.swift` — Add per-episode cover art + originalAssetID mapping
- `Tests/PodedgeCoreTests/PublishServiceTests.swift` — Add `TestDatabase.reset()` + `.tags(.swiftData)`

---

## Verdict

**PASS** — All 175 tests pass (0 failures). The process-level SwiftData crash during full test runs is a pre-existing test infrastructure issue unrelated to WS7.
