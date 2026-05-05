# Spec 06 — Publish Pipeline

Publishing is the core action of Podedge: upload audio, regenerate the RSS feed, upload the feed, notify distribution directories, and update episode state. `PublishService` is fully implemented but never called from the UI — the Publish tab has no wired button. This spec adds `PublishJobHandler`, wires the Publish button, implements the dry-run UI, adds scheduled publishing via `BGTaskScheduler`, and adds `OP3PollJobHandler` for periodic analytics refresh.

## User Stories

- As a user, I want a single "Publish" action per episode that runs upload → feed regen → feed upload → distribution notifications so that I don't orchestrate this manually. *(podedge-spec-user-stories.md — Publishing Flow)*
- As a user, I want a publish dry-run that shows exactly what will change so that I can review before committing. *(podedge-spec-user-stories.md — Publishing Flow)*
- As a user, I want to un-publish an episode so that I can remove it from the feed. *(podedge-spec-user-stories.md — Publishing Flow)*
- As a user, I want publish to be resumable so that interrupted publishes pick back up cleanly. *(podedge-spec-user-stories.md — Publishing Flow)*
- As a user, I want notifications on publish success or failure so that I know outcomes without staring at the app. *(podedge-spec-user-stories.md — Publishing Flow)*
- As a user, I want to schedule episodes to publish at a future date/time so that I can batch production. *(podedge-spec-user-stories.md — Future, confirmed for v1)*

## Functional Requirements

### Publish Button

WHEN the user taps "Publish" in the episode editor's Publish tab, THE SYSTEM SHALL invoke `ToolBroker` with tool ID `episode.publish` (destructive), which triggers `ConfirmationCoordinator` to show a confirmation sheet.

WHEN the user confirms the publish action, THE SYSTEM SHALL enqueue a `Job(kind: .publish, targetID: episodeID)` and set `episode.status = .processing`.

### PublishJobHandler

WHEN `JobScheduler` picks up a job of kind `.publish`, THE SYSTEM SHALL execute `PublishJobHandler`:
1. Fetch `Episode` and its `Show`.
2. Call `publishService.publish(show:episode:)`.
3. On success: episode status is already set to `.published` by `PublishService`; send a success notification.
4. On failure: set `episode.status = .failed`; send a failure notification.

### UploadJobHandler

WHEN `JobScheduler` picks up a job of kind `.upload`, THE SYSTEM SHALL execute `UploadJobHandler` which uploads a single asset to the host. This handler is used for resumable multipart uploads of large audio files. `PublishJobHandler` enqueues `.upload` jobs for each asset before the feed step.

IF an `.upload` job fails and is retried, THE SYSTEM SHALL use HEAD-before-PUT idempotency (already implemented in `S3Host`) to skip already-uploaded parts.

### Dry-Run UI

WHEN the user taps "Preview Publish" in the Publish tab, THE SYSTEM SHALL call `publishDryRun.plan(show:episode:)` and display the resulting `PublishPlan` in a sheet showing:
- Files to upload (name, size, remote path).
- Feed diff (new vs current published feed, if any).
- Distribution targets to notify.

### Unpublish

WHEN the user invokes the `episode.unpublish` tool (destructive), THE SYSTEM SHALL:
1. Remove the episode from the feed (regenerate and re-upload without it).
2. Set `episode.status = .draft`.
3. Optionally delete the remote audio file (user-configurable, default: keep).

### Scheduled Publishing

WHEN an episode has `scheduledFor` set to a future date, THE SYSTEM SHALL NOT publish it immediately; instead, `BGTaskScheduler` schedules a background task to fire at that time.

WHEN the scheduled time arrives, THE SYSTEM SHALL enqueue a `.publish` job for the episode.

WHEN the app registers background tasks, THE SYSTEM SHALL register task identifier `"dev.podedge.scheduled-publish"` with `BGTaskScheduler`.

IF the app is not running when the scheduled time arrives, THE SYSTEM SHALL be woken by the OS via the registered `BGProcessingTask` and enqueue the publish job.

### OP3PollJobHandler

WHEN `JobScheduler` picks up a job of kind `.op3Poll`, THE SYSTEM SHALL execute `OP3PollJobHandler`:
1. Fetch the `Show` by `job.targetID`.
2. Call `analyticsService.fetchAndPersistSnapshot(for:)`.
3. Enqueue the next `.op3Poll` job with `scheduledFor = now + 6h` (stored in `job.payloadJSON`).

WHEN a show with an `AnalyticsBinding` is published for the first time, THE SYSTEM SHALL enqueue an initial `.op3Poll` job with a 24-hour delay.

## Invariants

1. An episode with `status == .published` always has a non-nil `pubDate`.
2. An episode with `status == .published` always has a non-nil `publishedAssetID`.
3. A `.publish` job is never enqueued for an episode with `status == .published` (idempotency guard).
4. `episode.scheduledFor` is always in the future when set; setting it to a past date is rejected.
5. At most one pending `.publish` job exists per episode at any time.

## Property-Based Testing Targets

```swift
// Invariant 1: published episode always has pubDate
@Test
func publishedEpisodeHasPubDate() async throws {
    let env = try await PublishTestEnv.make()
    try await env.publish(episode: env.episode)
    let updated = try #require(env.store.episode(id: env.episode.id))
    #expect(updated.pubDate != nil)
}

// Invariant 4: scheduledFor must be in the future
@Test(arguments: [-3600.0, -1.0, 0.0])
func pastScheduledForIsRejected(offset: TimeInterval) throws {
    let pastDate = Date().addingTimeInterval(offset)
    #expect(throws: PodedgeError.self) {
        try Episode.validateScheduledFor(pastDate)
    }
}
```

## Non-Functional Requirements

- **Performance:** Feed build for a 200-episode show must complete in ≤ 500 ms (already a target in the technical design).
- **Reliability:** A publish interrupted mid-upload resumes from the last successful step on next launch (idempotent uploads via SHA-256 HEAD check).
- **Notifications:** Success/failure notifications are delivered via `NotificationService` (already implemented).
- **Privacy:** Audio is uploaded only to the user-configured S3 host; no third-party upload services.

## Out of Scope for v1

- Scheduled publishing UI calendar picker (basic date/time picker is sufficient).
- Publish queue with ordering (episodes publish in the order jobs are enqueued).
- Rollback of a failed partial publish.
- Multiple simultaneous publish jobs.
