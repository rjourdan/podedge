# Spec 06 — Publish Pipeline: Decisions & Learnings

Date: 2026-05-28
Review gate: Spec 06 (Publish Pipeline)

---

## Decision Log

### 1. BGTaskScheduler unavailable on macOS — Timer-based alternative

**Problem:** `BGTaskScheduler` is `API_UNAVAILABLE(macos)` per SDK headers. The design doc specified it for periodic OP3 polling and scheduled publish fire-time.

**Options considered:**
- Wrap the symbol behind `#if os(iOS)` guards and skip scheduling on macOS — would silently no-op the feature
- Use `BGTaskScheduler` anyway and accept a compile-time warning — not acceptable
- `DispatchSourceTimer` via a `ScheduledTaskScheduling` protocol — testable via mock injection, same interface

**Decision:** Created `ScheduledTaskScheduling` protocol with a `TimerTaskScheduler` implementation using `DispatchSourceTimer`. `BGTaskCoordinator` depends on the protocol, not the concrete type, so tests inject a `MockTaskScheduler`.

**Impact:** `BGTaskSchedulerPermittedIdentifiers` in `Info.plist` is unnecessary and was skipped. Timer fires on the main run loop. No entitlement changes required.

---

### 2. PublishJobHandler uses container.mainContext (not new ModelContext)

**Problem:** Other handlers (e.g., `TranscribeJobHandler`) create their own `ModelContext(container)` for isolation. But `PublishService` is `@MainActor` and mutates models via `mainContext`. A separate context in the handler would be out of sync with `PublishService`'s mutations — reads after a `PublishService` write would see stale data.

**Options considered:**
- Create a separate `ModelContext` and accept eventual-consistency races — incorrect for publish correctness
- Pass pre-resolved value types into the handler — workable but loses the ability to re-fetch on retry
- Make the handler `@MainActor` and share `container.mainContext` — matches ws7's "pre-resolve before async work" lesson, extends it to sharing the context

**Decision:** `PublishJobHandler` is `@MainActor` and uses `container.mainContext`. All model reads happen before the first `await`; async upload work uses pre-resolved value types (following the ws7 pattern).

**Impact:** `PublishJobHandler` is `@MainActor` (unlike other handlers which are plain `Sendable` structs). This is an intentional exception, not a pattern to generalize.

---

### 3. Publish/Unpublish buttons use direct confirmation dialogs, not ToolBroker

**Problem:** Spec 08 (Tool Registry Wiring) hasn't been implemented yet. `ToolBroker` has no registered tools. Routing publish through `broker.invokeConfirmed("episode.publish")` would silently fail — the broker returns `.failure("Tool not found")` and nothing happens.

**Options considered:**
- Block the Publish tab UI until Spec 08 — bad UX, blocks testing the pipeline
- Stub a tool registration just for publish — creates dead code that Spec 08 will undo
- Use SwiftUI `.confirmationDialog` directly for now — straightforward, easily replaced

**Decision:** `PublishTab` uses SwiftUI `.confirmationDialog` directly. On confirm, it enqueues the job via `jobScheduler.enqueue()`. A `// TODO: Spec 08 — replace with ToolButton` comment marks both call sites.

**Impact:** Temporary pattern. Will be replaced with `ToolButton` invocations when Spec 08 lands.

---

### 4. OP3PollJobHandler self-schedules via payloadJSON

**Problem:** OP3 polling needs to repeat every 6 hours. Without a cron-like scheduler, there is no native mechanism to re-fire a job on a delay.

**Options considered:**
- Use `BGTaskScheduler` — unavailable on macOS (see Decision 1)
- `DispatchAfter` — not durable across app restarts
- Self-scheduling: after each successful poll, insert a new `.op3Poll` Job with a delay encoded in `payloadJSON`

**Decision:** After each successful poll, the handler inserts a new `.op3Poll` Job with `payloadJSON: {"delaySeconds":21600}`. `JobScheduler` reads `delaySeconds` when picking pending jobs and skips any job whose `createdAt + delaySeconds` is still in the future. Crash-safe: if the app restarts, the pending job is already in SwiftData and will fire once the delay elapses.

**Impact:** Simple, durable, no external timer dependency. The `delaySeconds` field is the only addition to the `payloadJSON` contract for `.op3Poll` jobs.

---

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| Pre-Spec 06 | 175 |
| Spec 06 complete | 189 (+14 new) |

Spec 06 test breakdown:
- `PublishJobHandlerTests`: 5 tests
- `UploadJobHandlerTests`: 3 tests
- `OP3PollJobHandlerTests`: 3 tests
- `PublishPipelinePropertyTests`: 3 tests

---

## Files Created

- `PodedgeCore/Sources/PodedgeCore/Services/NotificationServiceProtocol.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/PublishJobHandler.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/UploadJobHandler.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/OP3PollJobHandler.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/PublishJobHandlerTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/UploadJobHandlerTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/OP3PollJobHandlerTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/PublishPipelinePropertyTests.swift`
- `Podedge/Podedge/Services/BGTaskScheduling.swift`
- `Podedge/Podedge/Services/BGTaskCoordinator.swift`

## Files Modified

- `PodedgeCore/Sources/PodedgeCore/Models/Episode.swift` — Added `validateScheduledFor(_:)`
- `Podedge/Podedge/Services/NotificationService.swift` — Added `NotificationServiceProtocol` conformance
- `Podedge/Podedge/AppServices.swift` — Registered 3 handlers, added `BGTaskCoordinator`
- `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — Rewrote `PublishTab` with publish/unpublish/dry-run/scheduling
