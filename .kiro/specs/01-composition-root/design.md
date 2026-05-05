# Spec 01 — Composition Root: Design

## Architecture Overview

`AppServices` is a `@MainActor final class` that owns every service in the app. It is constructed in `PodedgeApp.init()` and injected into the SwiftUI environment via a custom `EnvironmentKey`. Views read it with `@Environment(\.appServices)`. No service is ever constructed inside a view.

`bootstrap()` is a separate async method (not part of `init`) so that it can be `await`-ed inside a `.task` modifier on the root view, ensuring the scheduler and tool registry are fully populated before any user interaction is possible.

## Types

### New: `AppServices`

```swift
// Podedge/Podedge/AppServices.swift
@MainActor
public final class AppServices {
    public let modelContainer: ModelContainer
    public let jobScheduler: JobScheduler
    public let toolRegistry: ToolRegistry
    public let toolBroker: ToolBroker
    public let confirmationCoordinator: ConfirmationCoordinator
    public let audioPipeline: any AudioPipeline
    public let ingestService: IngestService
    public let modelManager: ModelManager
    public let transcriptionService: TranscriptionService
    public let llmService: LLMService
    public let metadataGenerationService: MetadataGenerationService
    public let hostService: HostService
    public let feedBuilder: FeedBuilder
    public let feedValidator: FeedValidator
    public let feedSerializer: FeedXMLSerializer
    public let distributionService: DistributionService
    public let artifactBuilder: PublishArtifactBuilder
    public let publishService: PublishService
    public let publishDryRun: PublishDryRun
    public let analyticsService: AnalyticsService
    public let libraryStore: LibraryStore

    public init(modelContainer: ModelContainer)
    public func bootstrap() async
}
```

`bootstrap()` registers all `JobHandler`s on `jobScheduler`, registers all tools on `toolRegistry`, then calls `jobScheduler.start()`.

### New: `AppServicesKey` (EnvironmentKey)

```swift
// Podedge/Podedge/AppServices.swift (extension section)
private struct AppServicesKey: EnvironmentKey {
    static let defaultValue: AppServices? = nil
}
extension EnvironmentValues {
    var appServices: AppServices? { get set }
}
```

### Modified: `PodedgeApp`

```swift
// Podedge/Podedge/PodedgeApp.swift
@main
struct PodedgeApp: App {
    @State private var services: AppServices
    init() { /* build AppServices */ }
    var body: some Scene { /* inject via .environment(\.appServices, services) */ }
}
```

`PodedgeApp.init()` calls `AppServices(modelContainer: try PodedgeSchema.makeContainer())`. The `.task` on the root `WindowGroup` content calls `await services.bootstrap()`.

### `JobScheduler` addition

```swift
// PodedgeCore — JobScheduler.swift (add method)
public func handler(for kind: JobKind) -> (any JobHandler)?
```

Needed for testability (Invariant 3 property test).

## File Map

| Action | Path |
|--------|------|
| **Create** | `Podedge/Podedge/AppServices.swift` |
| **Modify** | `Podedge/Podedge/PodedgeApp.swift` — replace manual service construction with `AppServices` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Services/JobScheduler.swift` — add `handler(for:)`, make `handlers` readable for tests |

All other service files in `PodedgeCore` need their access modifiers audited and set to `public` where currently `internal`. A non-exhaustive list:

| File | Types to make `public` |
|------|------------------------|
| `Services/IngestService.swift` | `IngestService` (already public) |
| `Services/JobScheduler.swift` | `JobScheduler` (already public) |
| `Services/LibraryStore.swift` | `LibraryStore` |
| `Services/HostService.swift` | `HostService` |
| `Services/FeedBuilder.swift` | `FeedBuilder` |
| `Services/FeedValidator.swift` | `FeedValidator` |
| `Services/FeedXMLSerializer.swift` | `FeedXMLSerializer` |
| `Services/DistributionService.swift` | `DistributionService` |
| `Services/PublishArtifactBuilder.swift` | `PublishArtifactBuilder` |
| `Services/PublishService.swift` | `PublishService` |
| `Services/PublishDryRun.swift` | `PublishDryRun` |
| `Services/AnalyticsService.swift` | `AnalyticsService` |
| `Services/LLMService.swift` | `LLMService` |
| `Services/MetadataGenerationService.swift` | `MetadataGenerationService` |
| `Services/ModelManager.swift` | `ModelManager` |
| `Services/TranscriptionService.swift` | `TranscriptionService` |
| `Models/ModelContainerSetup.swift` | `PodedgeSchema` |

## Data Flow

1. `PodedgeApp.init()` → `AppServices(modelContainer:)` — synchronous, builds all services.
2. Root view `.task` → `await services.bootstrap()` — registers handlers + tools, starts scheduler.
3. `JobScheduler.start()` — begins the 1-second poll loop; resumes any `.running` jobs left from a previous session.
4. SwiftUI environment propagation — all child views can read `@Environment(\.appServices)`.

## Error Model

- `PodedgeSchema.makeContainer()` failure → `fatalError` in `PodedgeApp.init()`. No recovery path; the app cannot function without a model container.
- `bootstrap()` failures (e.g., handler registration) → logged via `PodedgeLogger`; non-fatal since the scheduler will simply skip unhandled job kinds.

## Concurrency Model

- `AppServices` is `@MainActor`-isolated. All service properties are accessed on the main actor.
- Services that are themselves actors (`TranscriptionService`, `ModelManager`, `ToolRegistry`, `ToolBroker`) are safe to call from any isolation domain.
- `bootstrap()` is `async` to allow `await`-ing actor-isolated registrations on `ToolRegistry` and `JobScheduler`.

## Test Strategy

**Unit tests** (`AppServicesTests.swift` in the app test target):
- `testAllJobKindsHaveHandlers` — property test over `JobKind.allCases`.
- `testBootstrapIdempotent` — calling `bootstrap()` twice does not double-register handlers.
- `testServicesNotNilAfterInit` — spot-check that key services are non-nil.

**Integration:** Covered transitively by Spec 02–06 tests, which all require a bootstrapped `AppServices`.

## Open Questions / Risks

1. **`@MainActor` init cost:** Building all services synchronously in `init()` may add latency before the first frame. If profiling shows > 100 ms, move heavy construction into `bootstrap()`.
2. **`ConfirmationCoordinator` ownership:** Currently `@State` in `PodedgeApp`. Moving it into `AppServices` means it must be `@Observable` or `ObservableObject`. Confirm the coordinator's observation model before implementing.
3. **`ToolBroker` vs `ToolRegistry` environment keys:** Currently `PodedgeApp` injects `toolBroker` via a custom key. After this spec, only `appServices` needs to be injected — views access `appServices.toolBroker`. Remove the standalone `ToolBrokerKey`.
