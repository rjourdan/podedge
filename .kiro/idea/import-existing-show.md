# Import Existing Show — Feature Specification

**Status:** Deferred to v1.1. Specified now so the v1 domain model and
extension points accommodate it without refactoring.

## Motivation

Podcasters already hosting elsewhere (Transistor, Buzzsprout, Libsyn,
self-hosted, Spotify for Podcasters, etc.) need a zero-risk path to try
Podedge. The golden rule: **never break a listener's subscription**. That
means preserving GUIDs, preserving enclosure URLs until an explicit cutover,
and never re-issuing a feed at a new URL without guidance.

## User Stories

### Import
- As a user, I want to paste my podcast's RSS feed URL and have Podedge mirror the show into my local library so that I can start managing it without publishing.
- As a user, I want to paste an Apple Podcasts URL (or iTunes ID) and have Podedge resolve it to the actual feed URL so that I don't have to hunt for it.
- As a user, I want Podedge to parse my feed's channel-level metadata (title, author, description, language, category, cover, owner, `<podcast:guid>`) and create a Show so that I don't retype it.
- As a user, I want Podedge to parse every `<item>` and create Episodes, preserving the original GUID, pubDate, enclosure URL, duration, type, season/episode numbers, artwork, and `<podcast:transcript>`/`<podcast:chapters>` references.
- As a user, I want Podedge to detect Podcasting 2.0 elements (person, location, funding, value) and preserve them so that nothing is lost.

### Enclosure Handling
- As a user, I want to choose whether Podedge downloads the enclosure audio files to my local library or leaves them remote-only, so that I can balance disk use against offline access.
- As a user, I want enclosure downloads to be resumable, deduplicated (by sha256), and backgroundable so that I can import large back catalogs without babysitting.
- As a user, I want Podedge to verify enclosure MIME and MP3 validity on download and flag any episodes with broken files so that I can fix them.

### Transcript & Chapters Import
- As a user, I want Podedge to fetch any referenced `<podcast:transcript>` files and store them locally so that I don't lose transcripts I've already produced.
- As a user, I want Podedge to fetch any referenced `<podcast:chapters>` JSON and store it so that chapters round-trip correctly.
- As a user, I want Podedge to extract ID3 CHAP chapters from downloaded MP3s when no external chapters file exists so that I keep every chapter source I have.
- As a user, I want to optionally transcribe imported episodes that have no transcript so that my whole catalog becomes searchable and promotable.

### OP3 Detection
- As a user, I want Podedge to detect whether my existing feed already uses OP3 prefixing and, if so, extract the OP3 show UUID so that I don't duplicate analytics.
- As a user, I want Podedge to offer to enable OP3 going forward if my feed doesn't use it, without rewriting the prefix for already-published episodes so that existing download counts stay intact.

### Managed-Externally State
- As a user, I want imported shows to start in a "managed externally" mode where Podedge does not regenerate or upload a feed so that importing is zero-risk.
- As a user, I want to browse, edit, and prepare episodes in managed-externally mode without affecting the live feed so that I can explore Podedge safely.
- As a user, I want a clear, always-visible indicator that a show is managed externally so that I don't accidentally publish.

### Cutover to Podedge-Managed
- As a user, I want a cutover assistant that walks me through switching hosting to Podedge so that the transition is guided, not improvised.
- As a user, I want the cutover to validate that every GUID in the new Podedge-generated feed matches the old feed exactly so that subscribers don't lose episodes.
- As a user, I want the cutover to verify that every enclosure URL in the new feed returns a valid response (HEAD or GET of first byte range) before I flip the switch so that I don't publish broken links.
- As a user, I want the option to serve 301 redirects from old enclosure URLs to new ones (via documented DNS/CDN guidance) so that I can change hosting without losing download counts.
- As a user, I want the cutover to produce a step-by-step checklist: upload enclosures, upload transcripts, upload chapters, upload new feed, update feed URL at Apple Podcasts, update feed URL at Spotify, monitor for errors, so that I don't miss a step.
- As a user, I want to roll back from a cutover within a grace period so that I can recover if something goes wrong.

## Flow

### Phase A: Discover
1. User enters a URL: feed URL, Apple Podcasts URL, or iTunes ID.
2. If not a feed URL, resolve via iTunes Lookup API (`https://itunes.apple.com/lookup?id=...`) → extract `feedUrl`.
3. Fetch the feed (respect redirects, handle User-Agent, handle password-protected feeds — rare).
4. Validate that it parses as RSS 2.0 with iTunes namespace.

### Phase B: Parse
1. Channel metadata → populate draft `Show`. User confirms/edits in UI before save.
2. For each `<item>` → build a draft `Episode`.
3. Detect `<podcast:guid>` → if present, carry over. If absent, offer to generate one and write it at cutover time (with a warning that this changes the feed-level GUID, which is why we require explicit consent).
4. Detect OP3 prefix in enclosure URLs (match against `op3.dev/e` pattern) → if present, extract show UUID, pre-populate `AnalyticsBinding`.

### Phase C: Download (Optional, Background)
1. For each episode, if user opted to download, enqueue an `ImportEnclosureJob`.
2. Per episode: HEAD the enclosure, compare against any cached sha256, skip if already present.
3. Range-get for resumable downloads. Verify MP3 on completion. Create `Asset` rows.
4. Fetch `<podcast:transcript>` and `<podcast:chapters>` if referenced. Create transcript/chapters `Asset`s.

### Phase D: Managed-Externally Mode
- Show persists with a flag `managementMode = .externallyManaged`.
- `PublishService` refuses to run for externally-managed shows.
- `FeedBuilder` can still build a preview feed for the user to inspect — side-by-side diff with the live feed.
- User can create new episodes locally in "draft" state but cannot publish until cutover.

### Phase E: Cutover Assistant
1. **Prerequisite check:** every imported episode has a local enclosure (download complete), every GUID is preserved, cover art present, host binding configured.
2. **Feed diff:** build the Podedge-managed feed, diff against the current live feed. Warn on any GUID mismatch, missing episode, reordered pubDate sequence, changed channel `<podcast:guid>`.
3. **Upload plan:** list every file that will be uploaded to the new host — enclosures, transcripts, chapters, feed. Show total bytes.
4. **Dry-run execution:** upload everything to a `staging/` prefix on the host, generate a staging feed URL. User can subscribe to it in a podcast client to spot-check.
5. **Commit:** move files from `staging/` to the production prefix. Upload the real feed.
6. **Directory update checklist:** display the exact URLs to paste into Apple Podcasts Connect, Spotify for Podcasters, Amazon Music. For each, mark as done when user confirms.
7. **Grace window:** for N days (default 14), keep the old feed URL monitored — if the feed URL is the same as before (self-hosted cutover), this is trivial; if it's new, Podedge warns that subscribers on old URL won't auto-migrate and surfaces the 301-redirect guidance.
8. **Flip management mode:** `show.managementMode = .podedgeManaged`.

### Phase F: Post-Cutover
- Normal publish flow becomes available.
- Podedge starts OP3 analytics polling if enabled.
- First post-cutover publish is a fully normal publish — no special path.

## Data Model Extensions (v1.1)

Add to `Show`:
```swift
var managementMode: ManagementMode   // .podedgeManaged (default for new), .externallyManaged
var importedFromFeedURL: URL?
var importedAt: Date?
```

Add `ImportSession` model:
```swift
@Model final class ImportSession {
    @Attribute(.unique) var id: UUID
    var show: Show
    var sourceFeedURL: URL
    var itemsDiscovered: Int
    var itemsImported: Int
    var enclosuresDownloaded: Int
    var transcriptsDownloaded: Int
    var chaptersDownloaded: Int
    var detectedOP3ShowID: String?
    var warnings: [String]
    var state: ImportState  // .discovering, .parsing, .downloading, .ready, .cutover, .done, .failed
    var createdAt: Date
}
```

Add `CutoverPlan` value type (transient, not persisted):
```swift
struct CutoverPlan {
    let show: Show
    let uploads: [UploadDescriptor]
    let feedDiff: FeedDiff
    let distributionUpdates: [DistributionTarget.ID]
    let warnings: [CutoverWarning]
    let blockers: [CutoverBlocker]
}
```

## New Components

- `FeedImporter` — fetches and parses RSS, produces draft Show/Episodes.
- `iTunesLookupClient` — resolves Apple URLs to feed URLs.
- `EnclosureDownloader` — resumable, background downloads, dedup by sha256.
- `OP3Detector` — pattern-match existing OP3 prefix.
- `FeedDiffer` — structural diff between two feed versions (GUID/order/URL changes).
- `CutoverAssistant` — orchestrates Phase E, produces a `CutoverPlan`, executes it.

None of these require changes to the v1 extension-point protocols.

## Risks & Rules

1. **GUID preservation is sacred.** Any cutover that would change an episode's GUID is blocked, not warned. The user must explicitly opt in with an "I understand this will reset download counts" confirmation.
2. **Enclosure URL preservation during cutover.** If the host binding's public base URL differs from the original feed's enclosure base, Podedge issues a warning and offers a 301-redirect plan. Without redirects, download counts reset.
3. **Feed URL changes.** If the user's Apple/Spotify submission points to the old feed URL, Podedge cannot change that remotely. The cutover checklist makes this explicit.
4. **Privacy during import.** Podedge fetches the user's feed and enclosures over HTTPS. No third-party service is called beyond iTunes Lookup (only if user provides an Apple URL) and OP3 (only if user enables it).
5. **Large back catalog.** A show with 500 one-hour episodes is ~50GB of audio. Import must gracefully handle this: background downloads, pausable, disk-space-aware warnings, opt-out of download per-episode.

## Out of Scope (for the v1.1 import feature)

- Importing analytics history from the previous host.
- Importing listener subscription lists (impossible anyway — RSS has no such concept).
- Importing paid/member-only episodes (different auth model; deferred).
- Two-way sync with an external host (Podedge doesn't stay in sync after cutover; it takes over).
- Automatic DNS / CDN configuration for 301 redirects.

## Open Questions

- Do we implement a "shadow publish" mode where Podedge uploads to the production host during managed-externally mode but doesn't replace the live feed — useful for users who host on S3 and want Podedge to take over transparently?
- Should we offer to import directly from a Transistor/Buzzsprout/Libsyn API (faster than RSS scraping, gets us the originals) for specific hosts? Scope creep risk, but high UX value for those users.
- How do we handle feeds that violate spec (common in the wild)? Hard-fail vs best-effort parse with warnings. Lean best-effort.
