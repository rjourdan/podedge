# Spec 07 — Social Posting

After publishing, podcasters promote their episodes on social media. Podedge generates platform-specific blurbs (Spec 05) and needs to post them. In v1, Bluesky and Mastodon support real API posting; X, LinkedIn, and Threads are copy-paste only. `SocialBlurbRenderer` already generates text; this spec adds the posting infrastructure and wires the Promotion tab.

## User Stories

- As a user, I want Podedge to draft social-media copy so that I can promote without starting from a blank page. *(podedge-spec-user-stories.md — Local AI Assistance)*
- As a user, I want to post to Bluesky and Mastodon directly from Podedge after I confirm so that I don't jump between five apps. *(podedge-spec-user-stories.md — Assistant, adapted for v1 direct UI)*
- As a user, I want copy-to-clipboard for X, LinkedIn, and Threads so that I can paste into those apps. *(implied by promotion workflow)*
- As a user, I want my Bluesky and Mastodon credentials stored only in the Keychain so that they are secure. *(podedge-spec-user-stories.md — Privacy)*
- As a user, I want destructive social posting to require explicit confirmation so that I don't accidentally post. *(podedge-spec-user-stories.md — Two Ways to Work)*

## Functional Requirements

### SocialPostingTarget Protocol

WHEN a `SocialPostingTarget` is implemented, THE SYSTEM SHALL conform to:
```swift
protocol SocialPostingTarget: Sendable {
    var platformID: String { get }       // "bluesky", "mastodon", "x", "linkedin", "threads"
    var displayName: String { get }
    var mode: SocialPostingMode { get }  // .api or .copyPaste
    func post(text: String, episodeURL: URL?) async throws -> SocialPostResult
}
```

### BlueskyTarget

WHEN `BlueskyTarget.post(text:episodeURL:)` is called, THE SYSTEM SHALL:
1. Call `com.atproto.server.createSession` with the stored handle and app password to obtain an access token.
2. Call `com.atproto.repo.createRecord` with `$type: "app.bsky.feed.post"`, `text`, and `createdAt`.
3. Return a `SocialPostResult` with the post URI.

WHEN Bluesky credentials are configured, THE SYSTEM SHALL store the handle and app password in the Keychain under `bluesky.<accountHandle>`.

IF `createSession` returns a 401, THE SYSTEM SHALL throw `PodedgeError.socialPostFailed(platform: "bluesky", reason: "Invalid credentials")`.

### MastodonTarget

WHEN `MastodonTarget.post(text:episodeURL:)` is called, THE SYSTEM SHALL call `POST /api/v1/statuses` on the configured server URL with the stored access token and `status` body.

WHEN Mastodon credentials are configured, THE SYSTEM SHALL store the server URL and access token in the Keychain under `mastodon.<serverHost>`.

IF the Mastodon API returns a non-2xx status, THE SYSTEM SHALL throw `PodedgeError.socialPostFailed(platform: "mastodon", reason: <response body>)`.

### CopyPasteTarget

WHEN `CopyPasteTarget.post(text:episodeURL:)` is called, THE SYSTEM SHALL copy `text` to the system clipboard and return a `SocialPostResult` indicating copy-paste mode.

`CopyPasteTarget` is used for X, LinkedIn, and Threads.

### Promotion Tab UI

WHEN the Promotion tab is shown and `EpisodeSuggestions` exists, THE SYSTEM SHALL display one row per platform with the generated blurb text and a platform-specific action button.

WHEN the action button is tapped for Bluesky or Mastodon, THE SYSTEM SHALL invoke `ToolBroker` with tool ID `social.post` (destructive), which triggers `ConfirmationCoordinator`.

WHEN the action button is tapped for X, LinkedIn, or Threads, THE SYSTEM SHALL copy the blurb to the clipboard and show a brief "Copied!" confirmation.

WHEN the user has not configured credentials for Bluesky or Mastodon, THE SYSTEM SHALL show a "Connect account" button that opens the relevant Settings tab.

### Credential Management

WHEN the user adds a Bluesky account in Settings, THE SYSTEM SHALL prompt for handle and app password, test the connection via `createSession`, and store credentials in the Keychain on success.

WHEN the user adds a Mastodon account in Settings, THE SYSTEM SHALL prompt for server URL and access token, test via `GET /api/v1/accounts/verify_credentials`, and store in the Keychain on success.

## Invariants

1. Social credentials are never stored in SwiftData; they live only in the Keychain.
2. `BlueskyTarget` and `MastodonTarget` never log the access token or app password.
3. A `SocialPostResult` from a `.api` mode target always contains a non-empty `postURI`.
4. `CopyPasteTarget.post` always returns without throwing.

## Property-Based Testing Targets

```swift
// Invariant 4: CopyPasteTarget never throws
@Test(arguments: ["", "Hello", String(repeating: "x", count: 500)])
func copyPasteTargetNeverThrows(text: String) async throws {
    let target = CopyPasteTarget(platformID: "x", displayName: "X")
    let result = try await target.post(text: text, episodeURL: nil)
    #expect(result.mode == .copyPaste)
}

// Invariant 3: API post result has non-empty URI
@Test
func blueskyPostResultHasURI() async throws {
    let target = BlueskyTarget(handle: "test.bsky.social", keychainRef: "test")
    // Use URLProtocol stub for Bluesky API
    let result = try await target.post(text: "Test post", episodeURL: nil)
    #expect(!result.postURI.isEmpty)
}
```

## Non-Functional Requirements

- **Security:** App passwords and access tokens are stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlock`. They are never logged or included in diagnostic exports.
- **Reliability:** If a post fails due to a network error, the error is surfaced in the UI; the blurb text is preserved so the user can retry.
- **Rate limits:** Bluesky and Mastodon have rate limits. If a 429 is returned, surface a "Rate limited — try again in X minutes" message.

## Out of Scope for v1

- Scheduling social posts for a future time.
- Posting images or audiograms alongside text.
- Multi-account support per platform (one account per platform in v1).
- Analytics on post engagement.
- X, LinkedIn, Threads API posting (copy-paste only in v1).
