# Agent Access — Feature Specification

**Status:** Deferred to v1.2+. Re-scoped after the v1.1 in-app Assistant
became the primary "AI-native" priority (see `agentic-assistant.md`). The
v1 Action Layer (technical design §16) and the v1.1 Assistant's tool
catalog mean exposing Podedge to *external* agents via MCP is now a thin
transport wrapper — most of the heavy lifting (tools, broker, audit log,
confirmation flow) already exists.

**For the in-app assistant (⌘K chat inside Podedge), see
`agentic-assistant.md`.** This document covers *external* agent access —
letting Claude Desktop, Cursor, Zed, and other MCP-capable clients drive
Podedge from outside.

## Motivation

Podedge is an AI-native desktop app. The natural next step beyond "Podedge
has AI inside it" is "other AI can drive Podedge." Concretely: a user
working in Claude Desktop, Claude Code, Cursor, or Zed should be able to
ask their agent to list their shows, draft a title for their latest
episode, preview a feed, and (with explicit confirmation) publish — without
switching context to the Podedge UI.

Two protocols cover this:

- **MCP (Model Context Protocol):** Anthropic's open protocol for exposing
  tools, resources, and prompts to LLM clients. Already supported by Claude
  Desktop/Code, Cursor, Zed, Continue, and others. Swift SDK available.
  Transport: stdio (local IPC) or HTTP+SSE (networked).
- **A2A (Agent-to-Agent):** Google's emerging protocol for agent-to-agent
  task handoff and discovery. Worth tracking; not yet stable enough to
  implement against.

Both are thin wire protocols on top of the same capability surface. Podedge
defines that surface once (`AgentInterface`) and binds multiple protocols
to it.

## Guiding Principles

1. **User consent is explicit, per client, per scope.** Agents cannot connect
   silently. Every new client pairs through a macOS sheet the user clicks.
2. **Least privilege by default.** New sessions start read-only, scoped to
   zero shows. The user explicitly grants shows and modes.
3. **Destructive operations require a confirmation token.** Publish, delete,
   unpublish cannot be one-shot by an agent. Two-step flow with a plan.
4. **Everything is audited.** Every tool invocation is logged. Audit log is
   the source of truth for "what has an agent done to my library."
5. **Revocable at any time.** A "revoke" button per session immediately
   cancels active calls and blocks future ones.
6. **On-device-only shows stay on-device-only.** An agent-triggered LLM call
   honors the same `keepOnDevice` rule as a user-triggered one. No backdoor
   through the agent surface.
7. **Protocol-agnostic core.** Tool and resource definitions live in
   `PodedgeCore` independent of MCP/A2A. Adding A2A later is a new
   transport, not a rewrite.

## User Stories

### Discovery & Pairing
- As a user, I want to enable/disable the MCP server in Podedge Settings so that I control whether agents can connect at all.
- As a user, I want the MCP server to run in stdio mode for local-only clients (e.g., Claude Desktop launched via the MCP config file) so that no network surface is exposed.
- As a user, I want the MCP server to optionally run in HTTP+SSE mode on `127.0.0.1:<port>` so that networked clients (Cursor, browser-based IDEs) can connect locally.
- As a user, I want a one-click `podedge-cli agent install --client claude-desktop` so that wiring into Claude Desktop's MCP config is automatic.
- As a user, I want every new client connection to trigger a pairing sheet showing client name, requested scopes, and requested shows so that I know exactly what's attaching.

### Scoping
- As a user, I want to grant an agent read-only access to a subset of shows so that a writing assistant can see my library without risking my data.
- As a user, I want to grant write access (metadata edits, draft creation, transcribe, generate suggestions) separately from publish access so that I can delegate drafting without delegating launch authority.
- As a user, I want to grant publish access per show so that I can opt one show into fully-agented publishing while keeping others manual.
- As a user, I want scopes to be per-session, not global, so that different clients can have different authority.
- As a user, I want to change a session's scopes after the fact so that I can upgrade or downgrade without re-pairing.

### Confirmation & Safety
- As a user, I want destructive tool calls (`publish_episode`, `delete_episode`, `unpublish_episode`, `delete_show`) to return a confirmation token and a human-readable plan so that an agent cannot execute them in one step.
- As a user, I want confirmation tokens to be single-use and time-limited (5 minutes) so that stale plans cannot be replayed.
- As a user, I want a "require UI confirmation" option on publish so that even after the token flow, the final step is a click in Podedge, not just an agent re-call.

### Audit & Observability
- As a user, I want every tool call logged with timestamp, client, session ID, tool name, redacted argument summary, duration, and result status so that I can review agent activity.
- As a user, I want the audit log to be exportable (JSONL) so that I can keep records outside the app.
- As a user, I want a small menu-bar glyph showing active agent sessions and in-flight calls so that I know when agents are working.
- As a user, I want a notification when an agent attempts a denied operation so that I can spot misconfigured clients.

### Revocation
- As a user, I want to revoke a session with a single click so that a misbehaving client is immediately cut off.
- As a user, I want in-flight calls for a revoked session to cancel (not finish) so that revoke is not merely advisory.
- As a user, I want all stored tokens and credentials for a revoked session wiped from Keychain automatically.

### Tools (What Agents Can Do)
- As a user, I want agents to list and read my shows and episodes so that they can reason about what's there.
- As a user, I want agents to fetch transcripts and feed XML so that they can analyze my content.
- As a user, I want agents to run AI tasks (transcribe, suggest metadata, generate social blurbs) on my behalf so that I can delegate that work.
- As a user, I want agents to build and preview feeds (without uploading) so that they can validate proposed changes.
- As a user, I want agents to publish episodes with my confirmation so that end-to-end automation is possible when I trust the client.

### A2A (Future)
- As a user, I want Podedge to advertise capabilities via A2A once that spec stabilizes so that other agents can discover and call it in multi-agent workflows.

## Architecture

### Core Abstractions (live in `PodedgeCore`)

```swift
struct AgentTool {
    let name: String                    // "podedge.publish_episode"
    let description: String             // human + model-readable
    let inputSchema: JSONSchema
    let outputSchema: JSONSchema
    let requiredScope: AgentScope       // .read | .write | .publish
    let destructive: Bool               // triggers confirmation-token flow
}

struct AgentResource {
    let uriTemplate: String             // "podedge://episodes/{id}/transcript"
    let mimeType: String
    let description: String
    let requiredScope: AgentScope
}

enum AgentScope { case read, write, publish }

struct AgentSession {
    let id: UUID
    var clientName: String
    var clientVersion: String?
    var grantedScopes: Set<AgentScope>
    var allowedShowIDs: Set<UUID>       // empty = no shows; not "all shows"
    var createdAt: Date
    var lastSeenAt: Date
    var revokedAt: Date?
}

struct AgentToolResult {
    let content: JSONValue
    let confirmationRequired: ConfirmationRequired?
}

struct ConfirmationRequired {
    let token: String
    let expiresAt: Date
    let planSummary: String              // human-readable
    let planDetails: JSONValue           // machine-readable
}

protocol AgentInterface {               // defined in v1, implemented in v1.1
    var id: String { get }
    var tools: [AgentTool] { get }
    var resources: [AgentResource] { get }
    func invoke(_ toolName: String,
                arguments: JSONValue,
                session: AgentSession) async throws -> AgentToolResult
    func readResource(_ uri: String,
                      session: AgentSession) async throws -> AgentResourceContent
}
```

### Protocol Bindings (v1.1)

`MCPServerInterface` wraps the MCP Swift SDK and routes `tools/call` and
`resources/read` into the `AgentInterface` implementation. The MCP server
runs in one of two transports:

- **stdio:** `podedge-agent` standalone executable. Claude Desktop launches
  it via `mcpServers` config. Lifecycle: one process per Claude Desktop
  session.
- **HTTP+SSE:** embedded in the main app, bound to `127.0.0.1:<port>`.
  Authentication via a per-client bearer token issued at pairing time.

`A2AInterface` (v1.2+) will wrap the A2A SDK similarly when the spec is
stable. No architectural change — same `AgentInterface` underneath.

### Tool Catalog (v1.1 Initial Set)

Read scope:
- `podedge.list_shows` → `[ShowSummary]`
- `podedge.get_show(id)` → `Show` (full metadata)
- `podedge.list_episodes(show_id, filter?)` → `[EpisodeSummary]`
- `podedge.get_episode(id)` → `Episode` (full metadata)
- `podedge.get_transcript(episode_id)` → VTT text
- `podedge.get_feed_xml(show_id, include_drafts?)` → XML
- `podedge.validate_feed(show_id)` → `[ValidationMessage]`
- `podedge.get_analytics(show_id | episode_id, window)` → rollup stats
- `podedge.list_jobs(filter?)` → `[Job]`

Write scope:
- `podedge.create_episode_draft(show_id, mp3_path, title, description, ...)` → `episode_id`
- `podedge.update_episode(id, patch)` → updated `Episode`
- `podedge.transcribe_episode(id, model?)` → job ID (async)
- `podedge.suggest_metadata(episode_id, task, provider?)` → suggestions
- `podedge.generate_social_blurbs(episode_id, platforms[])` → blurbs
- `podedge.build_feed_preview(show_id)` → preview XML + validation
- `podedge.cancel_job(id)` → bool

Publish scope (destructive — confirmation token required):
- `podedge.publish_episode(id, dry_run?)` — dry_run skips token flow.
- `podedge.unpublish_episode(id)`
- `podedge.delete_episode(id)`
- `podedge.delete_show(id)`

Resources:
- `podedge://shows` — list of all accessible shows
- `podedge://shows/{id}` — show metadata JSON
- `podedge://episodes/{id}` — episode metadata JSON
- `podedge://episodes/{id}/transcript` — VTT
- `podedge://feed/{show_id}` — current published feed XML
- `podedge://feed/{show_id}/preview` — preview feed XML (includes drafts)

### Confirmation Token Flow

1. Agent calls `podedge.publish_episode(id="ep42")`.
2. Server validates scope + show access. Produces a `PublishPlan` (list of uploads, feed diff, distribution notifications).
3. Server responds with `AgentToolResult(content: {}, confirmationRequired: { token: "ct_abc123", expiresAt: ..., planSummary: "Publish ep42 to my-show: 1 MP3 (24.3 MB), 1 feed update, notify Podcast Index + Podping", planDetails: {...} })`.
4. Agent presents the plan summary to the user (MCP clients do this natively).
5. Agent re-calls `podedge.publish_episode(id="ep42", confirmation_token="ct_abc123")`.
6. Server validates token (single-use, not expired, matches original plan). If the underlying state changed since the plan was built (e.g., episode edited), reject — agent must re-plan.
7. If the user has "require UI confirmation" enabled for this session, a Podedge sheet appears with the plan; only a click in-app actually runs the publish.

### Pairing Flow

Stdio (local Claude Desktop etc.):
1. User runs `podedge-cli agent install --client claude-desktop`.
2. CLI writes an entry into `~/Library/Application Support/Claude/claude_desktop_config.json` with the `podedge-agent` command and a pre-generated session ID.
3. First time Claude Desktop launches `podedge-agent`, the agent process hands off the session ID to the running Podedge app via a Unix socket. Podedge shows a pairing sheet.
4. User approves scopes + shows. Session is marked active.
5. `podedge-agent` now relays MCP calls to Podedge.
6. If the Podedge app isn't running, `podedge-agent` launches it headless (menu bar only) and then proceeds.

HTTP+SSE (networked, e.g., Cursor, browser IDE):
1. In Podedge Settings → Agents, user clicks "Generate pairing code."
2. App displays a 6-digit code + the `http://127.0.0.1:<port>` URL.
3. User configures the client with the URL + code.
4. Client's first request exchanges the code for a bearer token; pairing sheet appears in Podedge.
5. User approves. Token is now valid for the duration of the session.

### Session Storage

`AgentSession` persisted in SwiftData. Bearer tokens stored in Keychain
(one entry per session ID). Revocation wipes both.

### Audit Log

New `@Model AgentAuditEntry`:
- session → AgentSession
- timestamp, tool name, resource URI
- arguments (redacted: large blobs replaced with `{size: N, sha256: ...}`, credentials never stored)
- outcome (`.ok`, `.denied(reason)`, `.failed(error)`, `.cancelled`)
- durationMs
- confirmationToken (nilable)

UI: filterable + exportable JSONL. Retention configurable (default 90 days).

### Data-Model Extensions

```swift
@Model final class AgentSession {
    @Attribute(.unique) var id: UUID
    var clientName: String
    var clientVersion: String?
    var transport: AgentTransport        // .stdio, .httpSSE
    var grantedScopesRaw: Int            // bitmask of AgentScope
    var allowedShowIDsJSON: String       // [UUID]
    var keychainRef: String?             // bearer token for HTTP+SSE
    var requireUIConfirmation: Bool
    var createdAt: Date
    var lastSeenAt: Date
    var revokedAt: Date?
}

@Model final class AgentAuditEntry {
    @Attribute(.unique) var id: UUID
    var session: AgentSession
    var timestamp: Date
    var toolName: String?
    var resourceURI: String?
    var argumentsJSON: String
    var outcome: String
    var outcomeDetail: String?
    var durationMs: Int
    var confirmationToken: String?
}

@Model final class PendingConfirmation {
    @Attribute(.unique) var token: String
    var session: AgentSession
    var toolName: String
    var planJSON: String
    var planSummary: String
    var createdAt: Date
    var expiresAt: Date
    var consumed: Bool
}
```

### Executable Layout

- `podedge-agent` — small executable linked against `PodedgeCore` + MCP
  Swift SDK. Runs stdio transport. Talks to the main app via Unix socket
  for session resolution and audit logging (so audit isn't lost if the
  agent process crashes).
- Main Podedge app — runs HTTP+SSE transport in-process when the user
  enables it. Owns SwiftData store, audit log, pairing UI.

## Open Questions

1. Should agents be able to create new shows (not just episodes)? Initial stance: no in v1.1. Show creation is the highest-friction, highest-commitment step; keep it human-only until we have evidence agents won't surprise users.
2. Should Podedge publish a standard MCP "prompts" catalog (reusable prompt templates) alongside tools? Would let Claude Desktop offer "Write show notes for my latest episode" as a slash-command. Low effort, nice-to-have.
3. Handle Ollama/Anthropic/OpenAI provider swaps *from agent calls*? Initial stance: no. Provider choice is user config; agents must not mutate it. They can read it.
4. Rate-limiting on the agent surface — per-session and per-tool. Prevents a buggy agent from hammering MLX or burning cloud spend. Defaults: 60 tool calls/minute per session, configurable.
5. Expose a "capabilities" endpoint that lists all tools/resources with their schemas? MCP has this natively via `tools/list` and `resources/list`. A2A will need its own. Keep the Podedge-side catalog as the single source of truth.

## Out of Scope

- Agent-to-agent orchestration logic inside Podedge (Podedge is a leaf service, not an orchestrator).
- Publishing public MCP servers (hosted Podedge-as-a-service via MCP) — this is local only.
- Agent-driven host-binding configuration (too sensitive; human-only).
- Agent-driven credential changes (Keychain writes remain human-only).
