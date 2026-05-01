# Publishing

> Guide to the episode publish workflow and distribution targets.
> **Audience:** podcasters ready to publish their first episode.

<!--
Changelog
- 2026-05-01: Initial draft.
-->

## Episode lifecycle

Every episode moves through a fixed set of states. You can see the current state as a colored dot next to each episode in the list.

| State | Color | Meaning |
|---|---|---|
| Draft | Gray | Episode created; metadata may be incomplete |
| Processing | Blue | Ingest pipeline running (transcription, metadata generation) |
| Ready | Green | All processing complete; episode can be published |
| Scheduled | Teal | Publish queued for a future date/time *(v1.1)* |
| Published | Teal | Live in the RSS feed |
| Failed | Red | A pipeline step failed; see the error detail |

An episode must reach **Ready** before you can publish it. If processing fails, the error detail in the episode editor explains what went wrong and offers a retry option.

## What happens when you publish

Publishing runs a sequential pipeline. Each step must succeed before the next begins. If any step fails, the pipeline stops and the episode stays in its current state — you can retry from the failed step.

```
1. Prepare artifact
   └─ Decide: use original MP3, or write a tag-rewritten copy
      (cover art + chapters embedded into ID3 tags)

2. Upload audio
   └─ HEAD-before-PUT: if the file already exists with the same
      SHA-256, skip the upload (safe to retry)

3. Upload transcript  (if transcription completed)
   └─ Uploads as .vtt to your S3 bucket

4. Upload chapters  (if chapters were generated)
   └─ Uploads as Podcasting 2.0 chapters JSON

5. Regenerate RSS feed
   └─ Rebuilds the feed from all published episodes + this one
   └─ Validates locally before upload

6. Upload RSS feed
   └─ Uploads to the path configured in your show's settings
   └─ Sets Content-Type: application/rss+xml
   └─ Sets Cache-Control: public, max-age=300

7. Notify distributions  (API targets only)
   └─ Podcast Index: submits feed URL via API
   └─ Podping: sends a publish notification

8. Mark published
   └─ Episode status → Published
   └─ pubDate set to now (or scheduledFor if scheduled)

9. Schedule analytics poll
   └─ First OP3 fetch queued for 24 hours out
```

## Dry run

Before committing to a publish, click **Dry Run** in the Publish tab. Podedge produces a plan showing:

- Which files will be uploaded (with sizes)
- The RSS feed diff (what changes between the current live feed and the new one)
- Which distribution targets will be notified

No files are uploaded and no notifications are sent during a dry run. Use it to catch mistakes before they go live.

## The confirmation sheet

When you click **Publish**, Podedge shows a confirmation sheet listing the specific actions it will take. You must click **Confirm** to proceed. This sheet appears whether you click the button yourself or trigger publish through the Assistant (v1.1).

Destructive actions — publish, unpublish, delete — always require this confirmation. There is no way to bypass it.

## Distribution targets

Podedge supports two kinds of distribution targets.

### API targets — automatic on every publish

These targets are called automatically each time you publish an episode. No manual steps required after initial setup.

**Podcast Index**
Submits your feed URL to [Podcast Index](https://podcastindex.org) using their API. Podcast Index powers many independent podcast apps (Fountain, Podverse, Castamatic, and others). Requires a Podcast Index API key, entered in **Settings → Distribution**.

**Podping**
Sends a [Podping](https://podping.org) notification announcing that your feed has updated. Podcast apps that subscribe to Podping refresh your feed within seconds of a publish, rather than waiting for their next scheduled poll.

### Guided targets — one-time setup per show

These directories do not offer a programmatic submission API. Podedge opens the submission page in your browser with your feed URL pre-filled, and you complete the submission manually. Once approved, you paste the resulting show ID back into Podedge so it can link to your show page.

**Apple Podcasts**
1. In the show's **Distribution** tab, click **Submit to Apple Podcasts**.
2. Podedge opens [Podcasts Connect](https://podcastsconnect.apple.com) with your feed URL ready to paste.
3. Complete the submission in your browser. Apple typically approves within 24–48 hours.
4. Once approved, copy your Apple show ID from Podcasts Connect and paste it into the **Apple Show ID** field in Podedge.

**Spotify**
1. Click **Submit to Spotify**.
2. Podedge opens [Spotify for Podcasters](https://podcasters.spotify.com) with your feed URL.
3. Complete the submission. Spotify typically approves within a few hours.
4. Paste your Spotify show ID back into Podedge.

**Amazon Music**
1. Click **Submit to Amazon Music**.
2. Podedge opens the [Amazon Music for Podcasters](https://podcasters.amazon.com) submission page.
3. Complete the submission and paste the resulting show ID back into Podedge.

### Distribution status

The **Distribution** tab on each show shows the current status of every target:

| Status | Meaning |
|---|---|
| Not submitted | You haven't submitted to this directory yet |
| Pending | Submission sent; waiting for directory approval |
| Live | Your show is live in this directory |
| Rejected | The directory rejected the submission; see the note for details |

## Unpublishing an episode

To remove an episode from the feed:

1. Open the episode and go to the **Publish** tab.
2. Click **Unpublish**.
3. Confirm in the sheet that appears.

Unpublishing removes the episode from the RSS feed and re-uploads the feed. The audio file remains in your S3 bucket — Podedge does not delete it automatically. To delete the file from S3 as well, check **Also delete from storage** in the confirmation sheet.

Podcast apps that have already downloaded the episode will keep their local copy. Unpublishing only prevents new downloads.

## Troubleshooting

**"Feed validation failed" before publish**
The feed validator checks required fields, GUID uniqueness, enclosure URL reachability, and artwork dimensions. The error detail lists exactly which check failed. Fix the flagged issue and try again.

**Upload failed / network error**
Podedge retries uploads automatically with exponential backoff. If the upload still fails after several retries, check your S3 credentials in **Settings → Hosts** and verify the bucket is accessible. The publish pipeline is resumable — when you retry, it picks up from the failed step, not from the beginning.

**Podcast Index submission rejected**
Verify your Podcast Index API key in **Settings → Distribution**. The API key must have write permissions. You can test it at [api.podcastindex.org](https://api.podcastindex.org).
