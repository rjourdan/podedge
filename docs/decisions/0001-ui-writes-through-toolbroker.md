# 0001 — UI writes go through ToolBroker; reads use SwiftData directly

<!--
Changelog
- 2026-05-05: Initial. Ratifies the split data-access model that was implicit in the pre-v1 work streams.
-->

- **Status:** Accepted
- **Date:** 2026-05-05
- **Deciders:** Lead developer

## Context

Podedge is a multi-surface, auditable, AI-native app. The same actions must be
invocable from three callers — the SwiftUI UI, the in-app Assistant (v1), and a
future CLI / MCP server — with identical confirmation, audit, and permission
behaviour. Several forces push against the plain Apple-idiomatic SwiftData
pattern:

- **Assistant parity.** The in-app Assistant must be able to perform every
  action the UI performs. If writes are scattered across `modelContext.insert`
  and `@Bindable` mutations in views, the assistant has no single surface to
  call.
- **Uniform confirmation.** Destructive actions (publish, delete, unpublish,
  social post) need a confirmation sheet regardless of whether the caller is a
  button click or an LLM tool call. A single broker enforces this uniformly.
- **Audit log.** Every write must produce an `AgentAuditEntry` (caller, tool ID,
  redacted args, outcome, duration). This is impossible if writes are spread
  across the view layer.
- **Future CLI and MCP server.** Both need a write API that is decoupled from
  SwiftUI. `ToolBroker` is that API.

At the same time, SwiftData's reactive strengths — `@Query` for live-updating
lists, `@Bindable` for form binding — are valuable and should not be abandoned.

## Decision

Podedge uses a **split data-access model**:

- **Reads:** views use `@Query`, `@Bindable`, and `@Environment(\.modelContext)`
  directly. This is Apple's idiomatic SwiftData pattern and is unchanged.
- **Writes:** any user-initiated side-effect — creating, updating, or deleting
  records, uploading files, publishing, posting, calling external APIs — is
  invoked via a registered tool through `ToolBroker`. Views never call
  `modelContext.insert()`, `modelContext.delete()`, or mutate `@Bindable`
  properties in response to explicit user actions that represent a write.

`@Bindable` is permitted for transient form state (edit buffering), but the
commit ("Save" / "Apply") must invoke a tool. Implicit autosave through
`@Bindable` mutation is disallowed for anything a user recognises as an action.

Services (`IngestService`, `PublishService`, job handlers, etc.) create their
own `ModelContext` inside actor-isolated methods. This is the correct pattern
for cross-isolation SwiftData access and is unaffected by this decision.

## Consequences

**Easier:**
- The Assistant and the UI call the same tools the same way — no parallel code
  paths.
- Confirmation UX is identical whether triggered by a button or an LLM tool
  call.
- Every write is audited automatically by `ToolBroker` without per-view
  instrumentation.
- Adding a CLI or MCP server is a transport wrapper around the existing tool
  catalog.

**Harder:**
- Every write operation requires a registered `ToolDefinition`. Adding a new
  write means adding a tool, not just calling `modelContext.insert`.
- The tool catalog must stay complete. A write that bypasses the broker is a
  silent audit gap.
- Reads and writes are handled by different disciplines (`@Query` vs
  `ToolBroker`), which can surprise developers familiar only with Apple's
  idiomatic SwiftData guidance.

## Alternatives considered

**A. Pure Apple-idiomatic** — `@Bindable` + `modelContext.insert/delete` in
views, no broker. Rejected: the Assistant cannot achieve parity because there is
no single callable surface. Audit and confirmation would require per-view
instrumentation.

**B. Strict hexagonal** — reads also go through a store facade; views never
touch SwiftData directly. Rejected: abandons `@Query`'s live-update reactivity
for no corresponding gain. The broker is worth the cost for writes; it is not
worth the cost for reads.

**C. This decision (Path A, split model)** — reads are free via SwiftData
idioms; writes are tools. Chosen.

## References

- [`docs/dev/mental-model.md`](../dev/mental-model.md) — tenets 2, 3, and 6
  describe the broker's role and the reads-are-free rule.
- [`.kiro/specs/`](../../.kiro/specs/README.md) — all 10 v1 specs are bound by
  this rule; see the cross-cutting rule section in the specs README.
- [`.kiro/idea/podedge-technical-design.md`](../../.kiro/idea/podedge-technical-design.md)
  §16 — Action Layer design (ToolBroker, ToolCaller, ToolScope).
