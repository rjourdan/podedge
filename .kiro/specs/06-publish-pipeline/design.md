# Spec 06 — Publish Pipeline: Design

## Architecture Overview

Three new `JobHandler` types bridge the job system to the existing `PublishService`, `HostService`, and `AnalyticsService`. The Publish tab in `EpisodeEditorView` is wired to `ToolBroker` via `ToolButton`. Scheduled publishing uses `BGTaskScheduler` with a single registered task identifier. `OP3PollJobHandler` self-schedules by enqueuing the next poll job on completion.

## Types

### New: `PublishJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/PublishJobHandler.swift
public struct PublishJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .publish
    private let publishService: PublishService
    private let notificationService: NotificationServiceProtocol

    public init(publishService: PublishService, notificationService: NotificationServiceProtocol)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

`execute` fetches `Episode` + `Show`, calls `publishService.publish(show:episode:)`, sends success notification. On error: sets `episode.status = .failed`, sends failure notification, rethrows.

### New: `UploadJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/UploadJobHandler.swift
public struct UploadJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .upload
    private let hostService: HostService

    public init(hostService: HostService)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

Payload JSON: `{ "assetID": "<uuid>", "remotePath": "<path>", "contentType": "<type>" }`. Fetches asset, calls `hostService.upload(asset:remotePath:contentType:)`.

### New: `OP3PollJobHandler`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/OP3PollJobHandler.swift
public struct OP3PollJobHandler: JobHandler, Sendable {
    public let handledKind: JobKind = .op3Poll
    private let analyticsService: AnalyticsService

    public init(analyticsService: AnalyticsService)
    public func execute(jobID: UUID, container: ModelContainer) async throws
}
```

After fetching the snapshot, enqueues the next `.op3Poll` job with `payloadJSON: { "delaySeconds": 21600 }`. `JobScheduler.pickAndRun` respects the backoff delay field for scheduling.

### New: `BGTaskCoordinator`

```swift
// Podedge/Podedge/Services/BGTaskCoordinator.swift
@MainActor
public final class BGTaskCoordinator {
    public static let scheduledPublishTaskID = "dev.podedge.scheduled-publish"

    public init(jobScheduler: JobScheduler, store: LibraryStore)
    public func registerTasks()
    public func schedulePublish(for episode: Episode)
}
```

`registerTasks()` calls `BGTaskScheduler.shared.register(forTaskWithIdentifier:)`. The handler fetches episodes with `scheduledFor <= now` and enqueues `.publish` jobs.

### Modified: `NotificationServiceProtocol`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/NotificationServiceProtocol.swift
public protocol NotificationServiceProtocol: Sendable {
    func sendPublishSuccess(episodeTitle: String) async
    func sendPublishFailure(episodeTitle: String, reason: String) async
}
```

`NotificationService` (app target) conforms. A `MockNotificationService` is used in tests.

### Modified: `EpisodeEditorView` — Publish Tab

```swift
// Podedge/Podedge/Views/Content/EpisodeEditorView.swift
// Publish tab:
// - "Preview Publish" button → calls publishDryRun.plan → shows PublishPlanSheet
// - ToolButton("Publish", toolID: "episode.publish", input: episodeID) — destructive
// - ToolButton("Unpublish", toolID: "episode.unpublish", input: episodeID) — destructive, shown only when published
// - DatePicker for episode.scheduledFor (optional)
```

### Modified: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
public let bgTaskCoordinator: BGTaskCoordinator

// bootstrap():
// Register PublishJobHandler, UploadJobHandler, OP3PollJobHandler
// bgTaskCoordinator.registerTasks()
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/PublishJobHandler.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/UploadJobHandler.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/OP3PollJobHandler.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/NotificationServiceProtocol.swift` |
| **Create** | `Podedge/Podedge/Services/BGTaskCoordinator.swift` |
| **Modify** | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — wire Publish tab |
| **Modify** | `Podedge/Podedge/AppServices.swift` — register handlers, BGTaskCoordinator |
| **Modify** | `Podedge/Podedge/Info.plist` — add `BGTaskSchedulerPermittedIdentifiers` key |

## Data Flow

**Immediate publish:**
1. User taps "Publish" → `ToolBroker.invoke("episode.publish")` → `ConfirmationCoordinator` shows sheet.
2. User confirms → `episode.status = .processing`, `Job(kind: .publish)` enqueued.
3. `JobScheduler` picks up job → `PublishJobHandler.execute`.
4. `PublishService.publish(show:episode:)` — full pipeline (already implemented).
5. `NotificationService.sendPublishSuccess`.

**Scheduled publish:**
1. User sets `episode.scheduledFor` → `BGTaskCoordinator.schedulePublish(for:)`.
2. OS fires `BGProcessingTask` at scheduled time.
3. Handler fetches due episodes → enqueues `.publish` jobs.
4. Normal publish flow.

**OP3 poll:**
1. First publish → `OP3PollJobHandler` enqueued with 24h delay.
2. Job fires → `AnalyticsService.fetchAndPersistSnapshot`.
3. Handler enqueues next poll job with 6h delay.

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.uploadFailed` | S3 upload fails | Job retried with backoff; failure notification after max attempts |
| `PodedgeError.feedValidation` | Feed invalid before upload | Job `.failed`; user sees validation errors in Feed Preview tab |
| `PodedgeError.notFound(entity: "HostBinding")` | No host configured | Job `.failed`; UI prompts to configure host |
| `PodedgeError.analyticsUnavailable` | OP3 API unreachable | OP3 poll job retried; non-fatal |

## Concurrency Model

- `PublishJobHandler`, `UploadJobHandler`, `OP3PollJobHandler` are `Sendable` structs.
- Each handler creates its own `ModelContext` within `execute`.
- `PublishService` is `@MainActor`; handlers call it via `await` from the cooperative thread pool.
- `BGTaskCoordinator` is `@MainActor`; `BGTaskScheduler` callbacks are dispatched to main actor.

## Test Strategy

**Unit tests** (`PublishJobHandlerTests.swift`):
- `testHandlerCallsPublishService` — mock `PublishService` → verify called once.
- `testHandlerSetsEpisodePublished` — episode status `.published` after success.
- `testHandlerSetsEpisodeFailedOnError` — mock throws → episode `.failed`.
- `testHandlerSendsSuccessNotification` — mock notification service → verify called.

**Property tests:**
- `testPublishedEpisodeHasPubDate` (see requirements).
- `testPastScheduledForIsRejected` (see requirements).

**Integration:** `PublishServiceTests.swift` already covers the service. Add `PublishJobHandlerIntegrationTests.swift` with a mock host.

## Open Questions / Risks

1. **`BGTaskScheduler` in tests:** `BGTaskScheduler` cannot be used in unit tests. `BGTaskCoordinator` should accept a protocol (`BGTaskScheduling`) so tests can inject a mock.
2. **`scheduledFor` enforcement:** `Episode.scheduledFor` is currently a plain `Date?` with no validation. Add `Episode.validateScheduledFor(_:)` as a static method that throws if the date is not in the future.
3. **Unpublish feed regeneration:** Unpublishing requires regenerating the feed without the episode. `PublishService` currently only adds episodes; a `regenerateFeed(for:excluding:)` method is needed.
4. **`Info.plist` BGTask identifier:** The identifier `"dev.podedge.scheduled-publish"` must match the app's bundle ID prefix. Confirm the bundle ID before hardcoding.
