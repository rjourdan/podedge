# Spec 07 — Social Posting: Decisions & Learnings

Date: 2026-05-29
Review gate: Spec 07 (Social Posting)

---

## Decision Log

### 1. URLSession injection for testability

**Problem:** `BlueskyTarget` and `MastodonTarget` use `URLSession` for HTTP calls. Testing requires intercepting network requests.

**Options considered:**
- `URLProtocol.registerClass` on shared session — global state, affects all tests
- Accept `URLSession` parameter with default `.shared` — clean, testable, no global mutation

**Decision:** Both targets accept `session: URLSession = .shared` in their initializer. Tests pass a session configured with `StubURLProtocol`. Production code uses the default.

**Impact:** `BlueskyTarget.swift`, `MastodonTarget.swift` have an extra init parameter. No API change for production callers.

---

### 2. truncateAtWordBoundary as module-internal free function

**Problem:** Both Bluesky (300 char) and Mastodon (500 char) need text truncation at word boundaries.

**Options considered:**
- Method on String extension — pollutes String namespace
- Static method on a utility type — over-engineered for one function
- Module-internal free function — simple, accessible from both targets and tests

**Decision:** `truncateAtWordBoundary(_:limit:)` is a free function in `BlueskyTarget.swift` with implicit `internal` access. Both targets and tests can use it.

**Impact:** Single definition, no duplication. If more text utilities accumulate, extract to a `Utilities/TextHelpers.swift`.

---

### 3. CopyPasteTarget clipboard write in UI layer, not PodedgeCore

**Problem:** `NSPasteboard` is AppKit-only. PodedgeCore must not import AppKit.

**Decision:** `CopyPasteTarget.post()` is a no-op that returns `.copyPaste` mode. The actual clipboard write happens in `PromotionTabView` (app target). This matches the design doc exactly.

**Impact:** Clean separation. `CopyPasteTarget` is testable without AppKit.

---

### 4. Social posting uses .confirmationDialog, not ToolBroker

**Problem:** Spec 08 (Tool Registry Wiring) hasn't been implemented yet. `ToolBroker` has no registered `social.post` tool.

**Decision:** `PromotionTabView` uses SwiftUI `.confirmationDialog` directly for destructive social posts. A `// TODO: Spec 08` comment marks the call site for future replacement with `ToolButton`.

**Impact:** Temporary pattern, consistent with the Spec 06 decision for publish buttons.

---

### 5. Social targets registered in bootstrap(), not lazily

**Problem:** Copy-paste targets (X, LinkedIn, Threads) don't need credentials. API targets (Bluesky, Mastodon) need credentials that may not exist yet.

**Decision:** Copy-paste targets are registered in `AppServices.bootstrap()` unconditionally. API targets are registered when the user connects an account in Settings → Social. This avoids failing on missing credentials at startup.

**Impact:** `SocialPostingService.allTargets()` returns only configured targets. The Promotion tab checks mode from the hardcoded `platforms` array, not from the service.

---

## Test Count Progression

| Milestone | Tests |
|-----------|-------|
| Pre-Spec 07 | 189 |
| Spec 07 complete | 197 (+8 new) |

Spec 07 test breakdown:
- `BlueskyTargetTests`: 4 tests
- `MastodonTargetTests`: 4 tests (includes CopyPasteTarget property test)

---

## Files Created

- `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingTarget.swift`
- `PodedgeCore/Sources/PodedgeCore/Social/BlueskyTarget.swift`
- `PodedgeCore/Sources/PodedgeCore/Social/MastodonTarget.swift`
- `PodedgeCore/Sources/PodedgeCore/Social/CopyPasteTarget.swift`
- `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingService.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/BlueskyTargetTests.swift`
- `PodedgeCore/Tests/PodedgeCoreTests/MastodonTargetTests.swift`

## Files Modified

- `PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift` — Added `socialPostFailed(platform:reason:)`
- `PodedgeCore/Sources/PodedgeCore/Services/KeychainService.swift` — Added social credential accessors
- `Podedge/Podedge/AppServices.swift` — Added `socialPostingService`, registered copy-paste targets
- `Podedge/Podedge/Views/Components/PromotionTabView.swift` — Rewrote with Post/Copy buttons
- `Podedge/Podedge/Views/Settings/SettingsView.swift` — Added Social tab

---

## Verdict

**PASS** — All 8 new tests pass. PodedgeCore builds clean. Implementation matches spec requirements and design doc.
