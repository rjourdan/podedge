# Spec 08 — Tool Registry Wiring: Decisions & Learnings

Date: 2026-06-01
Review gate: Spec 08 (Tool Registry Wiring)

---

## Decision Log

### 1. ToolBroker audit logging is optional (nil default)

**Problem:** Adding `AuditLogService` to `ToolBroker.init` would break all existing test code.

**Options considered:**
- Required parameter — breaks every test that constructs a `ToolBroker`
- Protocol-based mock injection — more code, same outcome
- Optional parameter with `nil` default — backward-compatible, production passes real service

**Decision:** Made `auditLog` parameter optional with `nil` default. Existing tests continue to work without audit logging. Production code passes the real service.

**Impact:** Backward-compatible change. No test modifications needed for the parameter addition.

---

### 2. Tools use `await MainActor.run {}` for LibraryStore access

**Problem:** `LibraryStore` and `JobScheduler` are `@MainActor`-isolated. Tool structs are `Sendable` and their `execute` method is `async` but not `@MainActor`.

**Options considered:**
- Mark tool `execute` as `@MainActor` — forces all tool execution onto the main actor, even tools that don't need it
- Use `nonisolated(unsafe)` — hides real safety issues
- Wrap calls in `await MainActor.run { }` — standard pattern, explicit about the hop

**Decision:** Each tool wraps its service calls in `await MainActor.run { }`. This is the standard pattern for calling `@MainActor` code from a non-isolated async context.

**Impact:** All tools follow the same pattern. No actor isolation conflicts.

---

### 3. All tools use `.full` capability tier

**Problem:** The spec says all v1 tools use tier `.t3`. The actual enum case is `.full` (not `.t3`).

**Options considered:**
- Rename `.full` to `.t3` — unnecessary churn, `.full` is more descriptive
- Mix tiers for different tools — premature, no Assistant consumer yet
- All tools `.full` — simplest correct choice for v1

**Decision:** All tools set `requiredTier: .full`. The tier system gates access for the Assistant (Spec 09/10); in v1 with only UI callers, all callers have `.full` tier.

**Impact:** No access restrictions in v1. Tier enforcement becomes meaningful when the Assistant is added.

---

### 4. Destructive tools in UI use existing confirmation patterns

**Problem:** `ToolButton` exists but its API is designed for simple button-style invocations. Some views (ShowListView, EpisodeListView) use swipe-to-delete which doesn't map to a button.

**Options considered:**
- Force all destructive actions through `ToolButton` — requires rearchitecting swipe gestures
- Skip broker for swipe-to-delete — loses audit trail
- Mixed approach: `ToolButton` for buttons, `toolBroker.invokeConfirmed` for swipes — both paths audited

**Decision:** For swipe-to-delete, call `toolBroker.invokeConfirmed` directly after the existing SwiftUI `.alert` confirmation. For button-style actions (publish, unpublish, social post), use `ToolButton`. Both paths go through the broker and produce audit entries.

**Impact:** Mixed approach but all destructive actions are audited. Consistent with the "two modalities, one action layer" principle.

---

### 5. SocialPostTool accepts text in input payload

**Problem:** The social post tool needs the blurb text to post. The original spec had `{ episodeID, platformID }` but the actual posting requires text content.

**Options considered:**
- Have the tool generate text internally — conflates posting with generation
- Require only IDs and fetch text from model — couples tool to model internals
- Accept `text: String` in input — caller provides content, tool only posts

**Decision:** Extended `SocialPostInput` to include `text: String`. The UI provides the blurb text from `EpisodeSuggestions`. The tool doesn't generate text — it only posts what it's given.

**Impact:** Clean separation: LLM generates blurbs (via `llm.generate_blurb` tool), social tool posts them.

---

### 6. Codable conformance added to Snapshot types

**Problem:** `ShowSnapshot` and `EpisodeSnapshot` were `Sendable` but not `Codable`. Tools need to JSON-encode them as output.

**Options considered:**
- Return raw dictionaries from tools — loses type safety
- Create separate DTO types — duplication for no benefit
- Add `Codable` to existing Snapshot types — minimal, all properties already Codable

**Decision:** Added `Codable` conformance to `ShowSnapshot`, `EpisodeSnapshot`, and `HostBindingSnapshot` in `Snapshots.swift`.

**Impact:** Minimal change — all stored properties were already Codable types.

---

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| Pre-Spec 08 | 189 |
| Spec 08 complete | 194 (+5 new ToolRegistryWiring tests) |

Note: 10 pre-existing test failures in ModelManager (3) and GenerateMetadataJobHandler (7) are unrelated to Spec 08.

---

## Files Created (13 total)

### PodedgeCore
- `Sources/PodedgeCore/Services/ToolPayloads.swift`
- `Sources/PodedgeCore/Tools/LibraryTools.swift`
- `Sources/PodedgeCore/Tools/FeedTools.swift`
- `Sources/PodedgeCore/Tools/AnalyticsTools.swift`
- `Sources/PodedgeCore/Tools/DistributionTools.swift`
- `Sources/PodedgeCore/Tools/EpisodeTools.swift`
- `Sources/PodedgeCore/Tools/ShowTools.swift`
- `Sources/PodedgeCore/Tools/LLMTools.swift`
- `Sources/PodedgeCore/Tools/HostTools.swift`
- `Sources/PodedgeCore/Tools/SocialTools.swift`
- `Sources/PodedgeCore/Tools/JobTools.swift`
- `Tests/PodedgeCoreTests/ToolRegistryWiringTests.swift`

### App Target
- `Podedge/Views/Settings/AuditLogView.swift`

## Files Modified

- `PodedgeCore/Sources/PodedgeCore/Services/ToolBroker.swift` — Added AuditLogService dependency + audit recording
- `PodedgeCore/Sources/PodedgeCore/Models/Snapshots.swift` — Added Codable conformance
- `Podedge/Podedge/AppServices.swift` — Added AuditLogService, registered 23 tools in bootstrap()
- `Podedge/Podedge/Views/Content/EpisodeEditorView.swift` — ToolButton for publish/unpublish
- `Podedge/Podedge/Views/Sidebar/ShowListView.swift` — Broker call for delete
- `Podedge/Podedge/Views/Sidebar/EpisodeListView.swift` — Broker call for delete
- `Podedge/Podedge/Views/Components/PromotionTabView.swift` — ToolButton for social post
- `Podedge/Podedge/Views/Settings/SettingsView.swift` — Added Audit Log tab

---

## Verdict

**PASS** — PodedgeCore builds clean. All 5 new tests pass. 23 tools registered. Audit logging wired. UI destructive actions route through broker.
