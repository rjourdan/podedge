# Spec 07 — Social Posting: Design

## Architecture Overview

`SocialPostingTarget` is a new protocol parallel to `DistributionTarget` but scoped to per-episode social posts. Three concrete implementations are added: `BlueskyTarget`, `MastodonTarget`, and `CopyPasteTarget`. A `SocialPostingService` manages the registry of configured targets and is owned by `AppServices`. The Promotion tab in `EpisodeEditorView` is wired to `ToolBroker` for destructive posts and to clipboard for copy-paste targets.

## Types

### New: `SocialPostingTarget` Protocol

```swift
// PodedgeCore/Sources/PodedgeCore/Services/SocialPostingTarget.swift
public enum SocialPostingMode: String, Sendable { case api, copyPaste }

public struct SocialPostResult: Sendable {
    public var postURI: String
    public var mode: SocialPostingMode
}

public protocol SocialPostingTarget: Sendable {
    var platformID: String { get }
    var displayName: String { get }
    var mode: SocialPostingMode { get }
    func post(text: String, episodeURL: URL?) async throws -> SocialPostResult
}
```

### New: `BlueskyTarget`

```swift
// PodedgeCore/Sources/PodedgeCore/Social/BlueskyTarget.swift
public struct BlueskyTarget: SocialPostingTarget, Sendable {
    public let platformID = "bluesky"
    public let displayName = "Bluesky"
    public let mode: SocialPostingMode = .api
    public let handle: String
    private let keychainRef: String  // key for app password in Keychain

    public init(handle: String, keychainRef: String)
    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult
}
```

`post` implementation:
1. `POST https://bsky.social/xrpc/com.atproto.server.createSession` with `{ identifier, password }`.
2. Extract `accessJwt` from response.
3. `POST https://bsky.social/xrpc/com.atproto.repo.createRecord` with `{ repo: did, collection: "app.bsky.feed.post", record: { "$type": "app.bsky.feed.post", text, createdAt } }`.
4. Return `SocialPostResult(postURI: response.uri, mode: .api)`.

Text is truncated to 300 characters (Bluesky's limit) if longer.

### New: `MastodonTarget`

```swift
// PodedgeCore/Sources/PodedgeCore/Social/MastodonTarget.swift
public struct MastodonTarget: SocialPostingTarget, Sendable {
    public let platformID = "mastodon"
    public let displayName = "Mastodon"
    public let mode: SocialPostingMode = .api
    public let serverURL: URL
    private let keychainRef: String  // key for access token

    public init(serverURL: URL, keychainRef: String)
    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult
}
```

`post` calls `POST <serverURL>/api/v1/statuses` with `Authorization: Bearer <token>` and `status=<text>`. Returns `SocialPostResult(postURI: response.url, mode: .api)`.

Text is truncated to 500 characters.

### New: `CopyPasteTarget`

```swift
// PodedgeCore/Sources/PodedgeCore/Social/CopyPasteTarget.swift
public struct CopyPasteTarget: SocialPostingTarget, Sendable {
    public let platformID: String
    public let displayName: String
    public let mode: SocialPostingMode = .copyPaste
    // Clipboard write happens in the UI layer, not here
    public func post(text: String, episodeURL: URL?) async throws -> SocialPostResult {
        SocialPostResult(postURI: "", mode: .copyPaste)
    }
}
```

The actual clipboard write is done in `PromotionTabView` after `post` returns, since `NSPasteboard` is AppKit and cannot be in `PodedgeCore`.

### New: `SocialPostingService`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/SocialPostingService.swift
public actor SocialPostingService {
    private var targets: [String: any SocialPostingTarget] = [:]

    public func register(_ target: any SocialPostingTarget)
    public func post(platformID: String, text: String, episodeURL: URL?) async throws -> SocialPostResult
    public func allTargets() -> [any SocialPostingTarget]
}
```

### New: `PodedgeError` addition

```swift
// PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift
case socialPostFailed(platform: String, reason: String)
```

### Modified: `KeychainService`

```swift
// PodedgeCore/Sources/PodedgeCore/Services/KeychainService.swift
// Add typed accessors:
public func blueskyAppPassword(handle: String) throws -> String
public func setBlueskyAppPassword(_ password: String, handle: String) throws
public func mastodonAccessToken(serverHost: String) throws -> String
public func setMastodonAccessToken(_ token: String, serverHost: String) throws
```

### Modified: `PromotionTabView`

```swift
// Podedge/Podedge/Views/Components/PromotionTabView.swift
// For each platform:
// - Show blurb text (editable)
// - Bluesky/Mastodon: ToolButton("Post", toolID: "social.post", ...) — destructive
// - X/LinkedIn/Threads: Button("Copy") { NSPasteboard.general.setString(blurb, ...) }
// - "Connect account" if not configured
```

### Modified: `SettingsView`

```swift
// Podedge/Podedge/Views/Settings/SettingsView.swift
// Add "Social" tab with Bluesky and Mastodon account configuration forms
```

## File Map

| Action | Path |
|--------|------|
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingTarget.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Social/BlueskyTarget.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Social/MastodonTarget.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Social/CopyPasteTarget.swift` |
| **Create** | `PodedgeCore/Sources/PodedgeCore/Services/SocialPostingService.swift` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Models/PodedgeError.swift` — add `socialPostFailed` |
| **Modify** | `PodedgeCore/Sources/PodedgeCore/Services/KeychainService.swift` — add social accessors |
| **Modify** | `Podedge/Podedge/Views/Components/PromotionTabView.swift` — wire Post/Copy buttons |
| **Modify** | `Podedge/Podedge/Views/Settings/SettingsView.swift` — add Social tab |
| **Modify** | `Podedge/Podedge/AppServices.swift` — construct and register `SocialPostingService` |

## Data Flow

**Bluesky post:**
1. User taps "Post to Bluesky" → `ToolBroker.invoke("social.post", input: { platformID: "bluesky", episodeID: ... })`.
2. `ConfirmationCoordinator` shows sheet with blurb preview.
3. User confirms → `SocialPostingService.post(platformID: "bluesky", text: blurb, episodeURL: ...)`.
4. `BlueskyTarget.post` → `createSession` → `createRecord`.
5. `SocialPostResult` returned → UI shows "Posted ✓" with link.

**Copy-paste:**
1. User taps "Copy" → `NSPasteboard.general.setString(blurb, forType: .string)`.
2. Brief "Copied!" toast shown. No `ToolBroker` involvement (not a side-effect requiring audit).

## Error Model

| Error | Trigger | Handling |
|-------|---------|----------|
| `PodedgeError.socialPostFailed(platform: "bluesky", reason: "Invalid credentials")` | 401 from createSession | Alert with "Check your app password in Settings" |
| `PodedgeError.socialPostFailed(platform: "mastodon", reason: ...)` | Non-2xx from /api/v1/statuses | Alert with server error message |
| Network error | No connectivity | Alert with retry option |

## Concurrency Model

- `BlueskyTarget` and `MastodonTarget` are `Sendable` structs; their `post` methods use `URLSession.data(for:)` which is `async`.
- `SocialPostingService` is an `actor` to serialize target registration.
- `KeychainService` is already a struct with synchronous Keychain calls; no actor needed.

## Test Strategy

**Unit tests** (`BlueskyTargetTests.swift`, `MastodonTargetTests.swift`):
- URLProtocol stubs for AT Protocol and Mastodon API endpoints.
- `testPostSuccessReturnsURI` — stub returns 200 → `SocialPostResult.postURI` non-empty.
- `testPostFailsOn401` — stub returns 401 → throws `socialPostFailed`.
- `testTextTruncatedToLimit` — text > 300 chars → truncated before posting.

**Unit tests** (`CopyPasteTargetTests.swift`):
- `testCopyPasteTargetNeverThrows` — property test (see requirements).

## Open Questions / Risks

1. **Bluesky PDS URL:** The AT Protocol PDS URL is `https://bsky.social` for most users but can be a custom PDS. For v1, hardcode `bsky.social`; add custom PDS support in v1.1.
2. **Mastodon OAuth vs access token:** Mastodon supports both OAuth flows and static access tokens. For v1, use static access tokens (user generates in Mastodon settings). OAuth flow is v1.1.
3. **Text truncation strategy:** Simply truncating at the character limit may cut mid-word or mid-sentence. Consider truncating at the last word boundary before the limit and appending "…".
4. **`NSPasteboard` in `CopyPasteTarget`:** `NSPasteboard` is AppKit-only and cannot be in `PodedgeCore`. The current design puts the clipboard write in the view layer, which is correct. Ensure the `social.post` tool for copy-paste targets does not try to write to the clipboard — that's a UI concern.
