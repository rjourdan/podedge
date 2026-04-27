# Podedge - User Stories Specification

Podedge is a local-first macOS application for publishing and promoting podcasts.
All compute — transcription, show-notes generation, chapter detection, social
copy — runs on-device. The user supplies a finished MP3 per episode; Podedge
handles hosting, feed generation, distribution, and promotion.

Target platform: Apple Silicon macOS (15+). Single-user. Episodes are authored
elsewhere; Podedge is the last mile.

## Two Ways to Work

Every capability in Podedge is accessible two ways: through the traditional UI
(buttons, forms, menus) and through the in-app Assistant (a chat pane, opened
with ⌘K). Both invoke the same underlying actions, go through the same
permissions, and produce the same audit trail. The Assistant is a v1.1
feature; v1 ships traditional UI only. See `agentic-assistant.md` for the
full design.

- As a user, I want every feature I can do by clicking to also be doable by asking the Assistant so that I can mix styles based on what I'm doing.
- As a user, I want the Assistant to be a dockable pane I can show, hide, or resize so that I control how much of my screen it occupies.
- As a user, I want ⌘K to always open and focus the Assistant, even if the pane is hidden or the main window is closed, so that it's always one shortcut away.
- As a user, I want the Assistant pane visible by default on first launch so that I discover the feature, with a clear way to hide it if I prefer a traditional workflow.
- As a user, I want the traditional UI to keep working if I hide the Assistant forever so that I'm never forced into chat.
- As a user, I want destructive actions (publish, delete, unpublish) to require explicit UI confirmation whether I triggered them by clicking or by asking so that the Assistant can never surprise me.
- As a user, I want the Assistant to label every message with the provider and model that produced it so that I always know what ran.
- As a user, I want to see which tools the Assistant invoked during a response so that I can verify it actually did what it claimed.

## Core Functionality

### Shows
- As a user, I want to create a podcast show with title, author, description, language, category, cover art, copyright, and owner email so that I have a canonical record of my show.
- As a user, I want to edit show metadata at any time so that I can keep it current.
- As a user, I want to delete a show so that I can remove abandoned projects.
- As a user, I want Podedge to lock a show's `<podcast:guid>` at creation time so that my show's identity never accidentally changes.
- As a user, I want to pick a hosting destination per show so that different shows can live in different buckets or accounts.
- As a user, I want to see per-show status (episode counts, last publish, feed URL, distribution health) at a glance so that I can tell which shows need attention.

### Episodes
- As a user, I want to create an episode by dropping an MP3 onto the show so that I can start publishing immediately.
- As a user, I want the app to validate the MP3 (duration, bitrate, channels, sample rate) on import so that I'm warned about bad files before publishing.
- As a user, I want to fill in per-episode metadata (title, subtitle, description, season, episode number, type, explicit flag, optional cover override) so that each episode is complete.
- As a user, I want each episode to have a stable GUID generated at import so that no client ever loses track of it.
- As a user, I want to see each episode's status (draft, processing, ready, scheduled, published, failed) so that I know what's happening.
- As a user, I want to play episodes from inside Podedge so that I can review before publishing.
- As a user, I want to delete a draft episode so that I can discard mistakes, while published episodes require explicit un-publish first.

### MP3 Ingest Pipeline (local, automatic)
- As a user, I want Podedge to compute an accurate duration, sha256, size, and bitrate of my MP3 on import so that the feed metadata is correct.
- As a user, I want Podedge to generate a waveform preview on import so that the UI can show it and I can use it for promotion later.
- As a user, I want Podedge to read existing ID3 tags so that my show's prior metadata is preserved and reconcilable.
- As a user, I want Podedge to optionally rewrite ID3 tags on a copy before upload so that the hosted file has clean, consistent tags and artwork, without ever mutating my original.
- As a user, I want Podedge to embed cover art and chapters (ID3 CHAP) into the hosted copy so that listeners see them in every client.

### Local AI Assistance
- As a user, I want on-device transcription of each episode so that I get a transcript without sending audio to any cloud.
- As a user, I want Podedge to suggest a title, subtitle, description, and SEO keywords from the transcript so that writing show notes is faster.
- As a user, I want Podedge to suggest chapter markers with timestamps from the transcript so that I can add chapters without manual scrubbing.
- As a user, I want Podedge to draft social-media copy (X, Bluesky, Mastodon, LinkedIn, Threads) so that I can promote without starting from a blank page.
- As a user, I want every AI suggestion to be editable and opt-in per-field so that I stay in control of my show's voice.
- As a user, I want suggestions to regenerate on demand so that I can explore alternatives.

## Hosting

### S3 (Default)
- As a user, I want to connect an S3 bucket by providing credentials, bucket name, region, and prefix so that Podedge can upload my audio and feed.
- As a user, I want my S3 credentials stored only in the macOS Keychain so that they never sit in plaintext on disk.
- As a user, I want Podedge to validate my credentials and bucket access before saving so that I don't discover errors at publish time.
- As a user, I want to configure an optional CloudFront/CDN alias for the public base URL so that my audio is served from a custom domain.
- As a user, I want resumable multipart uploads for large MP3s so that flaky networks don't force me to restart from zero.
- As a user, I want uploads to be idempotent (keyed on sha256 + remote path) so that retries never duplicate or corrupt files.

### Future Hosts
- As a user, I want the option to add other S3-compatible hosts (R2, B2, Spaces) later so that I'm not locked to AWS. (v1.1+)
- As a user, I want SFTP/WebDAV support for self-hosted setups. (v1.1+)

## RSS Feed Generation

- As a user, I want Podedge to generate a valid RSS 2.0 feed with the iTunes namespace and Podcasting 2.0 extensions so that my show is accepted by every major directory.
- As a user, I want the feed to include `<podcast:guid>`, `<podcast:transcript>`, `<podcast:chapters>`, `<podcast:person>`, and `<podcast:locked>` so that modern clients render rich information.
- As a user, I want Podedge to validate the feed locally before upload so that I can fix warnings before anyone downloads a broken feed.
- As a user, I want to preview the exact feed XML before publishing so that I can spot-check before pushing.
- As a user, I want Podedge to upload the feed with correct `Content-Type` and `Cache-Control` so that directories refresh reliably.
- As a user, I want Podedge to publish the feed with a content-hash check so that unchanged feeds aren't re-uploaded.

## OP3 Analytics

- As a user, I want Podedge to integrate OP3 for analytics so that I can see downloads, unique listeners, apps, and geographies.
- As a user, I want my OP3 API key stored in the Keychain so that it's secure.
- As a user, I want Podedge to prefix every enclosure URL with OP3 at feed-generation time so that stats collection is automatic.
- As a user, I want the OP3 prefix decision to be made and locked at show creation so that I never accidentally break my download-count continuity by toggling it.
- As a user, I want Podedge to periodically fetch OP3 stats in the background so that my dashboard stays current without manual refresh.
- As a user, I want show-level and per-episode analytics views so that I can understand both overall trends and individual episode performance.
- As a user, I want analytics data cached locally so that I can view trends offline.

## Distribution

- As a user, I want Podedge to submit my feed to Podcast Index via its API so that many smaller clients pick it up automatically.
- As a user, I want Podedge to send a Podping notification whenever I publish so that subscribed clients refresh quickly.
- As a user, I want a guided flow for submitting to Apple Podcasts, Spotify, and Amazon Music that opens the relevant submission page with my feed URL pre-filled so that I'm not hunting for links.
- As a user, I want to paste back the resulting show IDs from Apple/Spotify/Amazon so that Podedge can link out to my show pages later.
- As a user, I want a per-show "Distribution" panel that shows each destination's status (not submitted, pending, live, rejected) so that I know my reach.

## Publishing Flow

- As a user, I want a single "Publish" action per episode that runs upload → feed regen → feed upload → distribution notifications so that I don't orchestrate this manually.
- As a user, I want a publish dry-run that shows exactly what will change (files to upload, feed diff, distributions to notify) so that I can review before committing.
- As a user, I want to un-publish an episode so that I can remove it from the feed (the file can optionally stay in the bucket).
- As a user, I want publish to be resumable so that interrupted publishes pick back up cleanly.
- As a user, I want notifications on publish success or failure so that I know outcomes without staring at the app.

## Menu Bar & Main Window

- As a user, I want Podedge to live in the menu bar with a quick status glyph so that I can see background job progress without opening the main window.
- As a user, I want a full main window with Shows sidebar, Episodes list, and per-episode editor so that I can do detailed work when I need to.
- As a user, I want keyboard-first navigation so that I can work fast.
- As a user, I want drag-and-drop MP3 onto the dock/menu-bar to start a new episode so that ingest is one motion.

## Onboarding

- As a user, I want a first-run flow that walks me through creating my first show, entering S3 credentials, and optionally entering an OP3 API key so that I'm productive within minutes.
- As a user, I want Podedge to download required local AI models during onboarding with clear progress so that I know when I'm ready to go.
- As a user, I want to be told explicitly that no audio ever leaves my Mac except to my chosen host so that I trust the tool.

## Privacy & Security

- As a user, I want all transcription, LLM generation, and audio processing to happen on-device so that my unreleased content stays local.
- As a user, I want all credentials (S3, OP3, Podcast Index) stored only in the Keychain so that they're not readable from disk.
- As a user, I want secrets, signed URLs, and keys redacted from logs so that sharing a log file is safe.
- As a user, I want an option to export diagnostics (redacted) so that I can get help without leaking anything.

## Performance & Reliability

- As a user, I want ingest (hash + probe + waveform) to finish in under 10 seconds for a one-hour MP3 on Apple Silicon.
- As a user, I want transcription to run in the background without freezing the UI so that I can keep working.
- As a user, I want uploads to run in the background and survive app restarts so that I can close the window without losing progress.
- As a user, I want the app to recover gracefully from network failures so that a dropped Wi-Fi doesn't corrupt state.

## Future (v1.1+) — Spec'd Now, Not Built

- As a user, I want to import an existing podcast by pasting its feed URL so that I can migrate to Podedge without losing history. (See `import-existing-show.md`.)
- As a user, I want to generate audiograms (short video clips with waveform + captions) from any transcript span so that I can promote on social platforms that want video.
- As a user, I want to generate quote cards from transcript highlights so that I have ready-to-post images.
- As a user, I want to schedule episodes to publish at a future date/time so that I can batch production.
- As a user, I want the app to apply advanced audio processing (normalize, denoise, filler-word removal, chapter detection from silence, intro/outro bumper) so that I can skip external editors when I want to.
- As a user, I want additional hosting backends (R2, B2, SFTP, WebDAV) so that I can use my preferred infrastructure.
- As a user, I want Podcasting 2.0 value-for-value and dynamic-ad-insertion metadata so that I can monetize if I choose to.

### Bring Your Own AI (v1.1+)
- As a user, I want to route AI tasks to a local Ollama instance so that I can run larger or specialized models than Podedge's bundled default.
- As a user, I want to route AI tasks to Anthropic's Claude API so that I can use top-tier quality when I need it.
- As a user, I want to route AI tasks to OpenAI's API so that I can use GPT models.
- As a user, I want to point Podedge at any OpenAI-compatible endpoint (Groq, Together, Fireworks, LM Studio, LiteLLM, vLLM, self-hosted) so that I'm not locked into a specific vendor.
- As a user, I want to store API keys for cloud providers in the macOS Keychain so that my credentials are secure.
- As a user, I want to configure routing per task (show-notes vs chapters vs social-blurbs vs title-suggestions) so that I can mix providers — say, Claude for show notes, local MLX for quick titles.
- As a user, I want an explicit first-use consent sheet when a task is first routed to a cloud provider so that I know exactly what will be sent to whom.
- As a user, I want a per-show "keep on-device" toggle that hard-blocks cloud providers for that show so that sensitive content never leaves my Mac.
- As a user, I want every AI suggestion in the UI to be labeled with the provider and model that produced it so that I always know where a piece of output came from.
- As a user, I want a global "disable all cloud providers" switch so that I can enforce on-device-only mode across the whole app.
- As a user, I want Podedge to show estimated cost per call and cumulative cost per show for metered providers so that I can see spending at a glance.
- As a user, I want to pick how Podedge behaves when a cloud provider is unreachable (fall back to local model, or fail loudly) so that offline behavior matches my preference.

### Command-Line Interface (v1.1+)
- As a user, I want a `podedge-cli` tool installed alongside the app so that I can script publishing and automation.
- As a user, I want CLI commands for show CRUD, episode add, publish, feed build/validate, analytics pull, and host test so that every common flow can run headless.
- As a user, I want the CLI to share the app's library (same SwiftData store) so that changes made in one are visible in the other.
- As a user, I want the CLI to support `--dry-run` on any destructive operation so that I can preview before executing.
- As a user, I want CLI output to be structured (JSON) when piped, and human-readable when interactive, so that it works well in scripts and in my terminal.

### Assistant (v1.1)
- As a user, I want to type "publish my latest episode" and have the Assistant walk me through the publish flow with explicit UI confirmation at each destructive step so that I can work conversationally when that's easier.
- As a user, I want to ask "promote this episode on Mastodon and Bluesky with a technical-tone hook" and have the Assistant draft per-platform posts, show them to me for approval, and post them after I confirm so that I don't jump between five apps.
- As a user, I want to ask "how did EU listeners compare to US for the last 5 episodes" and get an analytics chart back so that I don't have to click through dashboards.
- As a user, I want to ask "why didn't Apple Podcasts pick up my episode" and get an explanation based on my feed, its validation state, and distribution logs so that debugging is conversational.
- As a user, I want to ask "what can you do" (or type /capabilities) and get a categorized list of Assistant capabilities so that I can discover features without guessing.
- As a user, I want the Assistant to show context-sensitive "Try asking…" suggestions based on what I have selected and what I recently did so that there's always a next step visible.
- As a user, I want each ⌘K invocation to start a fresh conversation so that stale context doesn't affect new requests.
- As a user, I want to write per-show markdown guides (voice, promotion style, saved analytics queries) that the Assistant reads so that I can shape its output without retraining anything.
- As a user, I want the Assistant to tell me when my current model may be unreliable for a given task and suggest upgrading (a bigger local model via Ollama, or a cloud provider) so that I know my options before things fail.
- As a user, I want the Assistant to fall back to "do it manually — here's where" with a deep-link when it can't complete a request so that I'm never stuck.
- As a user, I want the Assistant to use on-device models (MLX) by default so that my content stays local.
- As a user, I want to connect Ollama (for a bigger local model) or a cloud provider (Anthropic / OpenAI) per task so that I can upgrade the Assistant's capabilities when I choose to.
- As a user, I want every Assistant action recorded in an audit log with caller, tool name, arguments, and outcome so that I can see exactly what happened in my library.
- As a user, I want per-session rate and budget caps (tool calls per hour, destructive actions per hour, cloud spend per session) so that a confused Assistant can't burn through my time or money.

### External Agent Access via MCP (v1.2+)
Deferred — see `agent-access.md`. Lets external agents (Claude Desktop, Cursor, Zed) drive Podedge. The in-app Assistant (above) is the v1.1 priority; external MCP exposes the same tool surface to non-Podedge agents later.

## Out of Scope for v1

- Audio editing or processing (beyond optional ID3 tag rewrite).
- Multi-track session recording.
- Multi-user / team collaboration.
- Intel Mac support.
- Cloud-sync of the local library across Macs.
- Hosted payment, subscriptions, or listener authentication.
