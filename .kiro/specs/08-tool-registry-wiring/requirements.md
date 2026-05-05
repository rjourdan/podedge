# Spec 08 — Tool Registry Wiring

The Tool Registry is the bridge between the UI, the Assistant, and PodedgeCore services. Every side-effecting action in the app must be registered as a tool so that both UI buttons and the Assistant invoke the same code path, go through the same confirmation flow, and produce the same audit trail. Currently `ToolRegistry` is empty at runtime — no tools are registered. This spec defines the complete v1 tool catalog and wires every UI button that performs a side effect through `ToolBroker`.

## User Stories

- As a user, I want destructive actions to require explicit UI confirmation whether I triggered them by clicking or by asking so that the Assistant can never surprise me. *(podedge-spec-user-stories.md — Two Ways to Work)*
- As a user, I want every Assistant action recorded in an audit log with caller, tool name, arguments, and outcome so that I can see exactly what happened. *(podedge-spec-user-stories.md — Assistant)*
- As a user, I want every feature I can do by clicking to also be doable by asking the Assistant. *(podedge-spec-user-stories.md — Two Ways to Work)*

## Functional Requirements

### Tool Registration

WHEN `AppServices.bootstrap()` is called, THE SYSTEM SHALL register all tools listed in the v1 catalog below on `ToolRegistry`.

WHEN a tool is invoked via `ToolBroker`, THE SYSTEM SHALL write an `AgentAuditEntry` regardless of whether the caller is a UI button or the Assistant.

### v1 Tool Catalog

**Read tools** (scope `.read`, tier `.t3`):

| Tool ID | Input | Output | Description |
|---------|-------|--------|-------------|
| `library.list_shows` | `{}` | `[ShowSummary]` | List all shows |
| `library.get_show` | `{ showID }` | `ShowSnapshot` | Get show metadata |
| `library.list_episodes` | `{ showID }` | `[EpisodeSummary]` | List episodes for a show |
| `library.get_episode` | `{ episodeID }` | `EpisodeSnapshot` | Get episode metadata |
| `feed.build_preview` | `{ showID }` | `String` (XML) | Build feed without uploading |
| `feed.validate` | `{ showID }` | `[String]` (issues) | Validate feed locally |
| `analytics.query_cached` | `{ showID, since? }` | `[AnalyticsSnapshot]` | Cached OP3 data |
| `distribution.get_status` | `{ showID }` | `[DistributionRecord]` | Distribution status per target |
| `jobs.list` | `{ state? }` | `[JobSummary]` | List jobs |

**Write tools** (scope `.write`, tier `.t3`):

| Tool ID | Input | Output | Description |
|---------|-------|--------|-------------|
| `episode.create_draft` | `{ showID, title }` | `EpisodeSnapshot` | Create a draft episode |
| `episode.update_metadata` | `{ episodeID, patch }` | `EpisodeSnapshot` | Update episode fields |
| `episode.transcribe` | `{ episodeID }` | `JobSummary` | Enqueue transcription job |
| `llm.generate_metadata` | `{ episodeID }` | `JobSummary` | Enqueue metadata generation |
| `llm.generate_blurb` | `{ episodeID, platform }` | `String` | Generate a single blurb |
| `show.create` | `{ title, author, ... }` | `ShowSnapshot` | Create a new show |
| `show.update_metadata` | `{ showID, patch }` | `ShowSnapshot` | Update show fields |
| `host.test_binding` | `{ bindingID }` | `Bool` | Test S3 connection |

**Destructive tools** (scope `.destructive`, tier `.t3`):

| Tool ID | Input | Output | Description |
|---------|-------|--------|-------------|
| `episode.publish` | `{ episodeID }` | `JobSummary` | Publish episode |
| `episode.unpublish` | `{ episodeID }` | `EpisodeSnapshot` | Remove from feed |
| `episode.delete` | `{ episodeID }` | `{}` | Delete episode and assets |
| `show.delete` | `{ showID }` | `{}` | Delete show and all episodes |
| `host.remove_binding` | `{ bindingID }` | `{}` | Remove host binding |
| `social.post` | `{ episodeID, platformID }` | `SocialPostResult` | Post to social platform |

### UI Wiring

WHEN any UI button performs a side effect that corresponds to a registered tool, THE SYSTEM SHALL use `ToolButton` (or call `ToolBroker.invoke` directly) instead of calling the service directly.

WHEN a destructive tool is invoked from the UI, THE SYSTEM SHALL show `ConfirmationSheetView` before executing, identical to the flow used by the Assistant.

WHEN a tool invocation fails, THE SYSTEM SHALL surface the error to the user via an alert or inline error state in the view.

### Audit Log

WHEN any tool is invoked (read, write, or destructive), THE SYSTEM SHALL write an `AgentAuditEntry` with: caller type (`.ui` or `.agent`), tool ID, redacted input JSON, outcome, duration.

WHEN the user opens Settings → Diagnostics → Audit Log, THE SYSTEM SHALL display `AgentAuditEntry` rows filterable by date, tool ID, and caller type.

## Invariants

1. Every `JobKind` case has a corresponding tool that can enqueue it.
2. Every destructive tool invocation produces an `AgentAuditEntry` with `outcome != nil`.
3. No tool handler directly accesses `NSPasteboard`, `NSWorkspace`, or any AppKit type (those are in the UI layer).
4. Tool IDs are unique within the registry; registering a duplicate replaces the previous entry.

## Property-Based Testing Targets

```swift
// Invariant 4: duplicate registration replaces, not duplicates
@Test(arguments: ["library.list_shows", "episode.publish", "social.post"])
func duplicateRegistrationReplaces(toolID: String) async throws {
    let registry = ToolRegistry()
    let tool1 = MockTool(name: toolID, description: "v1")
    let tool2 = MockTool(name: toolID, description: "v2")
    await registry.register(tool1)
    await registry.register(tool2)
    let found = await registry.tool(named: toolID)
    #expect(found?.description == "v2")
}

// Invariant 2: destructive invocation always produces audit entry
@Test(arguments: ["episode.publish", "episode.delete", "social.post"])
func destructiveToolProducesAuditEntry(toolID: String) async throws {
    let env = try await ToolBrokerTestEnv.make()
    _ = await env.broker.invoke(toolNamed: toolID, input: Data(), caller: env.uiCaller)
    let entries = try await env.auditLog.entries(for: toolID)
    #expect(!entries.isEmpty)
}
```

## Non-Functional Requirements

- **Performance:** Tool invocation overhead (broker lookup + audit write) must add < 10 ms to any operation.
- **Reliability:** A tool handler that throws must not corrupt the audit log; the entry is written with `outcome: .failed` regardless.
- **Testability:** Every tool handler must be testable with a mock `AppServices`.

## Out of Scope for v1

- Per-tool rate limiting (v1.1 Assistant adds this).
- Tool versioning or schema evolution.
- External MCP exposure of tools (v1.2).
- Tool discovery UI beyond the `/capabilities` slash command (v1.1 Assistant).
