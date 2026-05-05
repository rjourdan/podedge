# Spec 01 — Composition Root

The composition root is the single place where every service is instantiated and wired together. Without it, `PodedgeApp` creates a `ModelContainer`, `ToolRegistry`, and `ToolBroker` but never builds `IngestService`, `JobScheduler`, `PublishService`, or any other core service — leaving the app a non-functional shell. This spec defines `AppServices`, the object that owns and connects every service, and the `bootstrap()` method that registers all job handlers and tools.

## User Stories

- As a user, I want the app to start up and be fully functional immediately after launch so that I can drop an MP3 and have the full pipeline run. *(implied by all pipeline stories)*
- As a user, I want background jobs to resume after an app restart so that interrupted transcriptions and uploads pick back up automatically. *(Reliability — podedge-spec-user-stories.md)*

## Functional Requirements

### Startup

WHEN the app launches, THE SYSTEM SHALL instantiate `AppServices` exactly once and inject it into the SwiftUI environment before any view renders.

WHEN `AppServices` is initialized, THE SYSTEM SHALL create a single `ModelContainer` using `PodedgeSchema.makeContainer()` and share it with all services that require SwiftData access.

WHEN `AppServices.bootstrap()` is called, THE SYSTEM SHALL register one `JobHandler` for each `JobKind` case: `.transcribe`, `.generateMetadata`, `.upload`, `.publish`, `.op3Poll`.

WHEN `AppServices.bootstrap()` is called, THE SYSTEM SHALL register every v1 tool in the `ToolRegistry` (see Spec 08 for the full catalog).

WHEN `AppServices.bootstrap()` is called, THE SYSTEM SHALL call `jobScheduler.start()` so that pending jobs from a previous session resume immediately.

### Service Ownership

WHILE the app is running, THE SYSTEM SHALL ensure that `AppServices` is the sole owner of `JobScheduler`, `ToolRegistry`, `ToolBroker`, `IngestService`, `PublishService`, `TranscriptionService`, `LLMService`, `MetadataGenerationService`, `AnalyticsService`, `HostService`, `FeedBuilder`, `FeedValidator`, `FeedXMLSerializer`, `DistributionService`, `PublishArtifactBuilder`, `PublishDryRun`, `ModelManager`, and `ConfirmationCoordinator`.

WHILE the app is running, THE SYSTEM SHALL expose `AppServices` via a SwiftUI `EnvironmentKey` so that any view can access services without passing them through the view hierarchy.

### Shutdown

WHEN the app terminates, THE SYSTEM SHALL call `jobScheduler.stop()` to cancel in-flight tasks cleanly.

### Access Modifiers

IF a `PodedgeCore` type is used by `AppServices` or any view but is not currently `public`, THEN THE SYSTEM SHALL have its access modifier updated to `public` before this spec is considered complete. Affected types include (but are not limited to): `IngestService`, `JobScheduler`, `TranscriptionService`, `LLMService`, `MetadataGenerationService`, `PublishService`, `PublishDryRun`, `PublishArtifactBuilder`, `HostService`, `FeedBuilder`, `FeedValidator`, `FeedXMLSerializer`, `DistributionService`, `AnalyticsService`, `ModelManager`, `LibraryStore`, `ToolRegistry`, `ToolBroker`, `ConfirmationCoordinator`, `PodedgeSchema`.

## Invariants

1. Exactly one `AppServices` instance exists for the lifetime of the process.
2. `AppServices.bootstrap()` is called exactly once, before any view renders.
3. Every `JobKind` case has a registered handler after `bootstrap()`.
4. `jobScheduler.start()` is called during `bootstrap()`.

## Property-Based Testing Targets

```swift
// Invariant 3: every JobKind has a handler after bootstrap
@Test(arguments: JobKind.allCases)
func allJobKindsHaveHandlers(kind: JobKind) async throws {
    let services = AppServices(modelContainer: makeTestContainer())
    await services.bootstrap()
    let handler = await services.jobScheduler.handler(for: kind)
    #expect(handler != nil, "No handler registered for \(kind)")
}
```

## Non-Functional Requirements

- **Performance:** `AppServices.init()` + `bootstrap()` must complete in under 500 ms on M1 so that the app is interactive before the first frame renders.
- **Reliability:** If `PodedgeSchema.makeContainer()` throws, the app must call `fatalError` with a clear message (no silent failure).
- **Testability:** `AppServices` must accept a `ModelContainer` parameter so tests can inject an in-memory container.

## Out of Scope for v1

- Multiple `AppServices` instances (multi-window, multi-user).
- Lazy service initialization.
- Dependency injection framework.
