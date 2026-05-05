# Spec 08 — Tool Registry Wiring: Design

## Architecture Overview

Each tool is a concrete type conforming to `ToolDefinition`. Tools are thin adapters: they decode JSON input, call an `AppServices` method, and encode JSON output. No business logic lives in a tool handler. `AppServices.bootstrap()` instantiates and registers all tools. The `AuditLogService` is called by `ToolBroker` on every invocation — this is already partially implemented; the gap is that `ToolBroker.invoke` does not currently call `AuditLogService`.

## Types

### Tool Input/Output Value Types

Each tool has a dedicated `Codable` input struct and output struct. These live in a new file:

```swift
// PodedgeCore/Sources/PodedgeCore/Services/ToolPayloads.swift
public struct ListShowsInput: Codable, Sendable {}
public struct ListShowsOutput: Codable, Sendable { public var shows: [ShowSummary] }

public struct GetEpisodeInput: Codable, Sendable { public var episodeID: UUID }
public struct GetEpisodeOutput: Codable, Sendable { public var episode: EpisodeSnapshot }

public struct PublishEpisodeInput: Codable, Sendable { public var episodeID: UUID }
public struct PublishEpisodeOutput: Codable, Sendable { public var jobID: UUID }

public struct SocialPostInput: Codable, Sendable { public var episodeID: UUID; public var platformID: String }
// ... one pair per tool
```

### Tool Implementations

Each tool is a small struct in a new directory:

```swift
// PodedgeCore/Sources/PodedgeCore/Tools/LibraryTools.swift
struct ListShowsTool: ToolDefinition {
    let name = "library.list_shows"
    let description = "List all podcast shows in the library"
    let scope: ToolScope = .read
    let requiredTier: CapabilityTier = .t3
    let parameterSchema: String = "{}"
    private let store: LibraryStore
    func execute(input: Data) async throws -> Data { ... }
}
// Similar structs for all read/write/destructive tools
```

Tools are grouped by domain:
- `LibraryTools.swift` — list_shows, get_show, list_episodes, get_episode
- `FeedTools.swift` — build_preview, validate
- `AnalyticsTools.swift` — query_cached
- `DistributionTools.swift` — get_status
- `EpisodeTools.swift` — create_draft, update_metadata, transcribe, publish, unpublish, delete
- `ShowTools.swift` — create, update_metadata, delete
- `LLMTools.swift` — generate_metadata, generate_blurb
- `HostTools.swift` — test_binding, remove_binding
- `SocialTools.swift` — post
- `JobTools.swift` — list

### Modified: `ToolBroker`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/ToolBroker.swift
// Add AuditLogService dependency:
public actor ToolBroker {
    private let registry: ToolRegistry
    private let auditLog: AuditLogService

    public init(registry: ToolRegistry, auditLog: AuditLogService)
    // invoke and invokeConfirmed write AgentAuditEntry on every call
}
```

`invoke` writes an audit entry with `outcome: .needsConfirmation` for destructive tools, then `.success` or `.failure` after execution.

### Modified: `AppServices.bootstrap()`

```swift
// Podedge/Podedge/AppServices.swift
func bootstrap() async {
    // Register all tools
    await toolRegistry.register(ListShowsTool(store: libraryStore))
    await toolRegistry.register(GetShowTool(store: libraryStore))
    // ... all 23 tools
    
    // Register all job handlers
    jobScheduler.registerHandler(TranscribeJobHandler(transcriptionService: transcriptionService))
    jobScheduler.registerHandler(GenerateMetadataJobHandler(metadataService: metadataGenerationService))
    jobScheduler.registerHandler(PublishJobHandler(publishService: publishService, notificationService: notificationService))
    jobScheduler.registerHandler(UploadJobHandler(hostService: hostService))
    jobScheduler.registerHandler(OP3PollJobHandler(analyticsService: analyticsService))
    
    jobScheduler.start()
}
```

### Modified: UI Views

Replace direct service calls with `ToolBroker` invocations:

```swift
// EpisodeEditorView — Publish tab
ToolButton("Publish", toolID: "episode.publish", input: PublishEpisodeInput(episodeID: episode.id))

// ShowListView — delete show
ToolButton("Delete Show", toolID: "show.delete", input: DeleteShowInput(showID: show.id))

// EpisodeListView — delete episode (replace .onDelete handler)
// PromotionTabView — post to Bluesky/Mastodon
ToolButton("Post to Bluesky", toolID: "social.post", input: SocialPostInput(episodeID: episode.id, platformID: "bluesky"))
```

### Modified: `AuditLogView`

```swift
// Podedge/Podedge/Views/Settings/AuditLogView.swift (new file, referenced in SettingsView)
// @Query for AgentAuditEntry, sorted by timestamp desc
// Filter by toolName, callerType, date range
// Export JSONL button
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/ToolPayloads.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/LibraryTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/FeedTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/AnalyticsTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/DistributionTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/EpisodeTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/ShowTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/LLMTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/HostTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/SocialTools.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Tools/JobTools.swift` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Services/ToolBroker.swift` — add `AuditLogService`, write entries |
| **Modify** | `Podedge/Podedge/AppServices.swift` — register all tools in `bootstrap()` |
| **Modify** | `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — ToolButton for publish/unpublish |
| **Modify** | `Podedge/Podedge/Views/Sidebar/ShowListView.swift` — ToolButton for delete show |
| **Modify** | `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` — ToolButton for delete episode |
| **Modify** | `Podedge/Podedge/Views/Components/PromotionTabView.swift` — ToolButton for social post |
| **Create** | `Podedge/Podedge/Views/Settings/AuditLogView.swift` |
| **Modify** | `Podedge/Podedge/Views/Settings/SettingsView.swift` — add Audit Log tab |

## Data Flow

**UI button → tool invocation:**
1. `ToolButton` tapped → `ToolBroker.invoke(toolNamed:input:caller: .ui(...))`.
2. Broker resolves tool, checks tier.
3. If `.destructive`: returns `.needsConfirmation` → `ConfirmationCoordinator` shows sheet.
4. User confirms → `ToolBroker.invokeConfirmed`.
5. Tool handler executes → calls `AppServices` method.
6. `AuditLogService.record(entry:)` called with outcome.
7. Result returned to `ToolButton` → loading state cleared, error shown if failed.

## Error Model

All tool handler errors are caught by `ToolBroker`, wrapped in `ToolResult.failure(String)`, and written to the audit log. The `ToolButton` view reads the failure and shows an alert.

## Concurrency Model

- Tool structs are `Sendable` (value types with `Sendable` dependencies).
- `ToolBroker` is an `actor`; all invocations are serialized through it.
- Tool handlers call `@MainActor`-isolated services via `await`; this is safe from within the actor.
- `AuditLogService` is already an actor; `ToolBroker` calls `await auditLog.record(...)`.

## Test Strategy

**Unit tests** (`ToolRegistryWiringTests.swift`):
- `testAllToolsRegisteredAfterBootstrap` — verify all 23 tool IDs are present.
- `testDuplicateRegistrationReplaces` — property test (see requirements).
- `testDestructiveToolProducesAuditEntry` — property test (see requirements).
- `testReadToolDoesNotRequireConfirmation` — `.read` tool returns `.success` directly.
- `testDestructiveToolReturnsNeedsConfirmation` — `.destructive` tool returns `.needsConfirmation`.

## Open Questions / Risks

1. **`ToolBroker` + `AuditLogService` init change:** `ToolBroker` currently takes only `registry`. Adding `auditLog` is a breaking change to its initializer. Update `PodedgeApp` and all test setup code.
2. **`ToolCaller` for UI:** The existing `ToolCaller` protocol has `capabilityTier`. UI callers should use `.t3` (highest tier — the user can do anything). Define a `UIToolCaller: ToolCaller` struct with `capabilityTier = .t3`.
3. **JSON encoding of `UUID`:** Swift's `JSONEncoder` encodes `UUID` as a lowercase hyphenated string by default. Ensure all tool input/output types use `UUID` consistently and that the decoder handles both uppercase and lowercase.
4. **`ShowSummary` / `EpisodeSummary` types:** These are referenced in the tool catalog but may not exist yet. Define them as lightweight `Codable, Sendable` structs in `ToolPayloads.swift` or `Snapshots.swift`.
