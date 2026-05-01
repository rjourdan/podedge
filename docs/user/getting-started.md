# Getting Started

> Quick-start guide for new Podedge users.
> **Audience:** podcasters setting up Podedge for the first time.

<!--
Changelog
- 2026-05-01: Initial draft.
-->

Podedge is a local-first macOS app that takes a finished MP3 and handles everything after: transcription, show-notes generation, RSS feed building, upload to your S3 bucket, and distribution to Apple Podcasts, Spotify, Amazon Music, Podcast Index, and Podping — all from your Mac, with no audio ever sent to a third-party cloud.

## System requirements

- **Mac:** Apple Silicon (M1 or later)
- **macOS:** 15.0 or later
- **Disk space:** ~5 GB free for local AI models (downloaded during onboarding)
- **Internet:** required for S3 uploads, OP3 analytics, and directory submissions; transcription and metadata generation run fully on-device

## First launch — the onboarding flow

When you open Podedge for the first time, a six-step onboarding wizard walks you through setup. You can skip optional steps and return to them later in Settings.

| Step | What happens | Required? |
|---|---|---|
| 1. Welcome | Overview of what Podedge does | — |
| 2. Create your first show | Enter show title, author, description, category, and cover art | Yes |
| 3. S3 hosting | Connect an S3 bucket (or compatible service) where audio and feeds are stored | Yes |
| 4. OP3 analytics | Enter an OP3 API key to enable download analytics | Optional |
| 5. Download AI models | Downloads the local transcription and language models (~3–5 GB) | Recommended |
| 6. Done | Podedge is ready | — |

If you skip S3 setup during onboarding, you can add it later in **Settings → Hosts**. You cannot publish until at least one host is configured.

For detailed S3 setup instructions, see [S3 Hosting Setup](s3-hosting-setup.md).

## Creating your first show

After onboarding (or from the sidebar at any time):

1. Click the **+** button at the bottom of the Shows sidebar, or choose **File → New Show**.
2. Fill in the required fields:
   - **Title** — your podcast's name
   - **Author** — your name or organization
   - **Description** — a paragraph describing the show (used in the RSS feed)
   - **Language** — e.g. `en-US`
   - **Category** — iTunes category (e.g. Technology, True Crime)
   - **Owner Email** — used in the RSS `<itunes:owner>` tag; not publicly displayed
3. Drag a square image (minimum 1400×1400 px, JPEG or PNG) onto the cover art drop zone.
4. Under **Hosting**, select the S3 host you configured. If you haven't configured one yet, click **Add Host** to open Settings.
5. Click **Create Show**.

Podedge assigns a permanent `<podcast:guid>` to the show at creation time. This UUID is locked forever — it is the show's identity across all podcast directories. It cannot be changed after the first publish.

## Importing your first episode

1. Select your show in the sidebar.
2. Drag an MP3 file onto the episode list (or onto the Podedge dock icon).
3. Podedge immediately starts the ingest pipeline in the background:
   - Validates the file (MPEG frame check, MIME sniff)
   - Copies it to the app's local library
   - Computes SHA-256, duration, bitrate, and waveform
   - Reads any existing ID3 tags
   - Queues transcription and AI metadata generation
4. The episode appears in the list with a blue **Processing** indicator. When transcription and metadata generation finish, the indicator turns green: **Ready**.

While the episode processes, you can already edit its metadata in the **Metadata** tab — title, subtitle, description, season/episode number, explicit flag, and optional per-episode cover art.

## Publishing workflow overview

Once an episode is **Ready**:

1. Open the episode and click the **Publish** tab.
2. Review the pre-publish checklist (required fields, feed validation warnings).
3. Click **Dry Run** to preview exactly what will happen: which files will be uploaded, what the feed diff looks like, which directories will be notified. No changes are made.
4. Click **Publish**. A confirmation sheet lists the specific actions. Click **Confirm** to proceed.
5. Podedge runs the publish pipeline:
   - Uploads the audio file to S3 (skips if already uploaded with the same SHA-256)
   - Uploads the transcript and chapters files if present
   - Regenerates the RSS feed and uploads it
   - Notifies Podcast Index and Podping
6. The episode status changes to **Published**.

For a detailed walkthrough of the publish flow and distribution targets, see [Publishing](publishing.md).

## What's next

- [S3 Hosting Setup](s3-hosting-setup.md) — step-by-step bucket and IAM configuration
- [OP3 Analytics](op3-analytics.md) — enable download tracking
- [Publishing](publishing.md) — the full publish workflow and distribution targets
