# Implementation Plan: Publish Pipeline

## Overview

This plan implements the publish pipeline end-to-end: three new `JobHandler` types (`PublishJobHandler`, `UploadJobHandler`, `OP3PollJobHandler`) that bridge the job system to existing services, a `NotificationServiceProtocol` for testable notification delivery, a `BGTaskCoordinator` for scheduled publishing via `BGTaskScheduler`, `Episode.validateScheduledFor(_:)` for date validation, wiring the Publish tab buttons (Publish, Dry Run, Unpublish) through `ToolBroker`, and registration of all handlers in the app's composition root.

## Tasks

- [ ] 1. Create NotificationServiceProtocol and conform NotificationService
  - [ ] 1.1 Create `NotificationServiceProtocol`
    - Create `PodedgeCore/Sources/PodedgeCore/Services/NotificationServiceProtocol.swift`
    - Define `public protocol NotificationServiceProtocol: Sendable` with two methods:
      - `func sendPublishSuccess(episodeTitle: String) async`
      - `func sendPublishFailure(episodeTitle: String, reason: String) async`
    - _Requirements: Publish Button, PublishJobHandler (notifications)_

  - [ ] 1.2 Conform `NotificationService` to `NotificationServiceProtocol`
    - Modify `Podedge/Podedge/Services/NotificationService.swift`
    - Add conformance to `NotificationServiceProtocol`
    - Implement `sendPublishSuccess(episodeTitle:)` by delegating to existing `notifyPublishSuccess(episodeTitle:)`
    - Implement `sendPublishFailure(episodeTitle:reason:)` by delegating to existing `notifyPublishFailure(episodeTitle:reason:)`
    - _Requirements: PublishJobHandler (notifications)_

- [ ] 2. Create PublishJobHandler
  - [ ] 2.1 Create `PublishJobHandler`
    - Create `PodedgeCore/Sources/PodedgeCore/Services/PublishJobHandler.swift`
    - Implement `JobHandler` and `Sendable` conformance with `handledKind: .publish`
    - Accept `PublishService` and `NotificationServiceProtocol` via init
    - In `execute(jobID:container:)`: create `ModelContext`, fetch `Job` → `Episode` → `Show` via predicate + fetchLimit
    - Guard that `episode.status != .published` (idempotency — Invariant 3)
    - Call `await publishService.publish(show:episode:)`
    - On success: call `notificationService.sendPublishSuccess(episodeTitle:)`
    - On failure: set `episode.status = .failed`, call `notificationService.sendPublishFailure(episodeTitle:reason:)`, rethrow
    - Follow the same fetch pattern as `TranscribeJobHandler` and `GenerateMetadataJobHandler`
    - _Requirements: PublishJobHandler_

  - [ ] 2.2 Write unit tests for PublishJobHandler
    - Create `PodedgeCore/Tests/PodedgeCoreTests/PublishJobHandlerTests.swift`
    - Test handler calls publish service once on execute
    - Test handler sets `episode.status = .failed` when publish throws
    - Test handler sends success notification after successful publish
    - Test handler sends failure notification on error
    - Test handler does not re-publish an already-published episode (idempotency guard)
    - Use `MockNotificationService` conforming to `NotificationServiceProtocol`
    - _Requirements: PublishJobHandler, Invariant 3_

- [ ] 3. Create UploadJobHandler
  - [ ] 3.1 Create `UploadJobHandler`
    - Create `PodedgeCore/Sources/PodedgeCore/Services/UploadJobHandler.swift`
    - Implement `JobHandler` and `Sendable` conformance with `handledKind: .upload`
    - Accept `HostService` via init
    - In `execute(jobID:container:)`: create `ModelContext`, fetch `Job`, decode `payloadJSON` for `assetID`, `remotePath`, `contentType`
    - Fetch the `Asset` by decoded `assetID`
    - Resolve host binding and call `hostService` upload (uses HEAD-before-PUT idempotency from `S3Host`)
    - Update `asset.remotePath` and `asset.remoteURL` on success
    - _Requirements: UploadJobHandler_

  - [ ] 3.2 Write unit tests for UploadJobHandler
    - Create `PodedgeCore/Tests/PodedgeCoreTests/UploadJobHandlerTests.swift`
    - Test handler decodes payload JSON correctly
    - Test handler throws `PodedgeError.notFound` when asset is missing
    - Test handler updates asset remote path on success
    - _Requirements: UploadJobHandler_

- [ ] 4. Create OP3PollJobHandler
  - [ ] 4.1 Create `OP3PollJobHandler`
    - Create `PodedgeCore/Sources/PodedgeCore/Services/OP3PollJobHandler.swift`
    - Implement `JobHandler` and `Sendable` conformance with `handledKind: .op3Poll`
    - Accept `AnalyticsService` via init
    - In `execute(jobID:container:)`: create `ModelContext`, fetch `Job`, get `targetID` (show ID)
    - Call `analyticsService.fetchAndPersistSnapshot(for:)` (or equivalent)
    - Enqueue the next `.op3Poll` job with `scheduledFor = now + 6h` via `payloadJSON: { "delaySeconds": 21600 }`
    - _Requirements: OP3PollJobHandler_

  - [ ] 4.2 Write unit tests for OP3PollJobHandler
    - Create `PodedgeCore/Tests/PodedgeCoreTests/OP3PollJobHandlerTests.swift`
    - Test handler enqueues next poll job after execution
    - Test next poll job has correct delay (6h = 21600s)
    - Test handler fetches analytics for the correct show
    - _Requirements: OP3PollJobHandler_

- [ ] 5. Checkpoint — Job handlers complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Add Episode.validateScheduledFor validation
  - [ ] 6.1 Add `Episode.validateScheduledFor(_:)` static method
    - Modify `PodedgeCore/Sources/PodedgeCore/Models/Episode.swift`
    - Add `public static func validateScheduledFor(_ date: Date) throws` that throws `PodedgeError.preconditionViolated` if `date <= Date()`
    - This enforces Invariant 4: `scheduledFor` is always in the future when set
    - _Requirements: Scheduled Publishing, Invariant 4_

  - [ ] 6.2 Write property test: past scheduledFor is rejected
    - **Property: Invariant 4 — scheduledFor must be in the future**
    - **Validates: Requirements — Invariant 4 (past scheduledFor rejected)**
    - Create test in `PodedgeCore/Tests/PodedgeCoreTests/PublishPipelinePropertyTests.swift`
    - Use Swift Testing `@Test(arguments:)` with offsets `[-3600.0, -1.0, 0.0]` to verify `Episode.validateScheduledFor(_:)` throws for past/now dates
    - Verify a future date (e.g. `+3600`) does not throw

  - [ ] 6.3 Write property test: published episode has pubDate
    - **Property: Invariant 1 — published episode always has non-nil pubDate**
    - **Validates: Requirements — Invariant 1 (published episode has pubDate)**
    - Add test to `PodedgeCore/Tests/PodedgeCoreTests/PublishPipelinePropertyTests.swift`
    - Use Swift Testing `@Test` to verify that after `PublishService.publish(show:episode:)` succeeds, `episode.pubDate != nil`
    - Can use a mock host to simulate successful publish

- [ ] 7. Create BGTaskCoordinator with BGTaskScheduling protocol
  - [ ] 7.1 Define `BGTaskScheduling` protocol for testability
    - Create `Podedge/Podedge/Services/BGTaskScheduling.swift`
    - Define `protocol BGTaskScheduling` with methods mirroring `BGTaskScheduler.shared`:
      - `func register(forTaskWithIdentifier: String, using: DispatchQueue?, launchHandler: @escaping (BGTask) -> Void) -> Bool`
      - `func submit(_ taskRequest: BGTaskRequest) throws`
    - Add extension conforming `BGTaskScheduler` to `BGTaskScheduling`
    - _Requirements: Scheduled Publishing (Open Question 1 — testability)_

  - [ ] 7.2 Create `BGTaskCoordinator`
    - Create `Podedge/Podedge/Services/BGTaskCoordinator.swift`
    - Implement `@MainActor public final class BGTaskCoordinator`
    - Define `static let scheduledPublishTaskID = "dev.podedge.scheduled-publish"`
    - Accept `JobScheduler`, `LibraryStore`, and `BGTaskScheduling` via init (default to `BGTaskScheduler.shared`)
    - Implement `registerTasks()` — calls `scheduler.register(forTaskWithIdentifier:)` for the publish task ID
    - Implement `schedulePublish(for episode: Episode)` — creates a `BGProcessingTaskRequest` with `earliestBeginDate = episode.scheduledFor`
    - In the task handler: fetch episodes with `scheduledFor <= now`, enqueue `.publish` jobs for each
    - _Requirements: Scheduled Publishing_

  - [ ] 7.3 Write unit tests for BGTaskCoordinator
    - Create `Podedge/PodedgeTests/BGTaskCoordinatorTests.swift`
    - Use `MockBGTaskScheduler` conforming to `BGTaskScheduling`
    - Test `registerTasks()` registers the correct task identifier
    - Test `schedulePublish(for:)` submits a task request with correct `earliestBeginDate`
    - Test handler enqueues publish jobs for due episodes
    - _Requirements: Scheduled Publishing_

- [ ] 8. Register handlers in AppServices and update Info.plist
  - [ ] 8.1 Register all new handlers in `AppServices.bootstrap()`
    - Modify `Podedge/Podedge/AppServices.swift`
    - Add `public let bgTaskCoordinator: BGTaskCoordinator` property
    - Initialize `BGTaskCoordinator` in `init` with `jobScheduler`, `libraryStore`
    - In `bootstrap()`, register:
      - `PublishJobHandler(publishService: publishService, notificationService: NotificationService.shared)`
      - `UploadJobHandler(hostService: hostService)`
      - `OP3PollJobHandler(analyticsService: analyticsService)`
    - Call `bgTaskCoordinator.registerTasks()`
    - Update the placeholder handler `where` clause to exclude `.publish`, `.upload`, `.op3Poll` (only `.ingest` remains)
    - _Requirements: PublishJobHandler, UploadJobHandler, OP3PollJobHandler, Scheduled Publishing_

  - [ ] 8.2 Add `BGTaskSchedulerPermittedIdentifiers` to Info.plist
    - Modify `Podedge/Podedge/Info.plist`
    - Add key `BGTaskSchedulerPermittedIdentifiers` as an array containing `"dev.podedge.scheduled-publish"`
    - _Requirements: Scheduled Publishing_

- [ ] 9. Checkpoint — Backend integration complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Wire the Publish tab UI
  - [ ] 10.1 Wire "Publish" button via ToolBroker
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `PublishTab`
    - Replace the current manual `publishEpisode()` function with a `ToolButton` (or equivalent invocation) that calls `ToolBroker` with tool ID `"episode.publish"` (destructive)
    - `ConfirmationCoordinator` shows confirmation sheet; on confirm: set `episode.status = .processing` and enqueue `Job(kind: .publish, targetID: episode.id)`
    - Only enabled when `episode.status == .ready || episode.status == .scheduled`
    - _Requirements: Publish Button_

  - [ ] 10.2 Wire "Dry Run" button to show PublishPlan sheet
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `PublishTab`
    - Add `@State private var showingDryRun = false` and `@State private var publishPlan: PublishPlan?`
    - "Preview Publish" button calls `publishDryRun.plan(show:episode:)` and sets `showingDryRun = true`
    - Display a `.sheet` showing files to upload (name, size, remote path), feed diff, and distribution targets
    - _Requirements: Dry-Run UI_

  - [ ] 10.3 Wire "Unpublish" button
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `PublishTab`
    - Show "Unpublish" button only when `episode.status == .published`
    - Invoke `ToolBroker` with tool ID `"episode.unpublish"` (destructive) through `ConfirmationCoordinator`
    - On confirm: regenerate feed excluding the episode (`publishService.regenerateFeed(for:excluding:)`), set `episode.status = .draft`
    - _Requirements: Unpublish_

  - [ ] 10.4 Add DatePicker for `episode.scheduledFor` with validation
    - Modify `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — `PublishTab`
    - Add a `DatePicker` bound to `episode.scheduledFor` with `in: Date()...` to prevent past dates in UI
    - On change, call `Episode.validateScheduledFor(_:)` and if valid, call `bgTaskCoordinator.schedulePublish(for:)`
    - Show validation error if user somehow selects a past date
    - _Requirements: Scheduled Publishing, Invariant 4_

- [ ] 11. Final checkpoint — Full integration
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Each task references specific requirements for traceability
- Checkpoints at tasks 5, 9, and 11 ensure incremental validation
- Property tests validate universal correctness properties (Invariants 1 and 4)
- Unit tests validate specific examples and edge cases for each handler
- `TranscribeJobHandler` / `GenerateMetadataJobHandler` pattern (fetch via predicate + fetchLimit, `ModelContext` from container) is the established convention for all job handlers
- `BGTaskCoordinator` uses a `BGTaskScheduling` protocol so tests can inject a mock scheduler (design Open Question 1)
- `NotificationServiceProtocol` lives in PodedgeCore for testability; `NotificationService` (app target) conforms
- `PublishService.regenerateFeed(for:excluding:)` is needed for unpublish (design Open Question 3); implement inline during task 10.3 if not already present
- The placeholder handler loop in `AppServices.bootstrap()` will only cover `.ingest` after all handlers are registered
- `Info.plist` BGTask identifier `"dev.podedge.scheduled-publish"` must match the bundle ID prefix (design Open Question 4)

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.1", "4.1", "6.1"] },
    { "id": 2, "tasks": ["2.2", "3.2", "4.2", "6.2", "6.3", "7.1"] },
    { "id": 3, "tasks": ["7.2"] },
    { "id": 4, "tasks": ["7.3", "8.1", "8.2"] },
    { "id": 5, "tasks": ["10.1", "10.2", "10.3", "10.4"] }
  ]
}
```
