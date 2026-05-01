# OP3 Analytics

> Guide to enabling and using OP3 download analytics in Podedge.
> **Audience:** podcasters who want to track downloads and listener geography.

<!--
Changelog
- 2026-05-01: Initial draft.
-->

## What is OP3?

[OP3](https://op3.dev) (Open Podcast Prefix Project) is a free, open-source podcast analytics service. It works by prefixing your episode enclosure URLs — when a listener's app downloads your audio, the request passes through OP3's servers first, which record the download before redirecting to your actual file.

OP3 gives you:
- **Download counts** per episode and per show
- **Unique listener estimates**
- **App breakdown** (Apple Podcasts, Spotify, Overcast, etc.)
- **Geographic breakdown** by country

All data is open and auditable. OP3 does not sell listener data.

## How Podedge uses OP3

When OP3 is enabled for a show, Podedge wraps every episode's enclosure URL in the RSS feed with the OP3 prefix:

```
https://op3.dev/e,pg=YOUR-SHOW-UUID/https://your-cdn.com/shows/my-show/episode-1.mp3
```

The `pg=` parameter is your show's permanent UUID (the same `<podcast:guid>` Podedge assigns at show creation). This ties all downloads to your show in OP3's database.

Podedge polls OP3 every 6 hours and caches the results locally. You can view download trends in the **Analytics** view without an internet connection — the charts are built from the local cache.

## Important: the OP3 decision is permanent

Once you publish your first episode with OP3 enabled, the prefix is baked into your RSS feed. Disabling OP3 later would change all your enclosure URLs, which breaks download-count continuity and may confuse podcast apps that have cached the old URLs.

Podedge locks this setting after the first publish and shows a warning if you try to change it. **Decide before you publish episode 1.**

## Setting up OP3

### 1. Register at op3.dev

1. Go to [op3.dev](https://op3.dev) and click **Sign in** (uses GitHub OAuth).
2. After signing in, navigate to **API Keys** and create a new key.
3. Copy the API key — you'll enter it in Podedge.

### 2. Enter the API key in Podedge

**During onboarding:** Step 4 of the onboarding wizard asks for your OP3 API key. Paste it in and click **Continue**.

**After onboarding:** Go to **Settings → Analytics**, enter your OP3 API key, and click **Save**.

Podedge stores the key in the macOS Keychain. It is never written to disk in plain text.

### 3. Enable OP3 for a show

1. Select your show in the sidebar.
2. Click the **Settings** tab in the show detail view.
3. Toggle **Enable OP3 analytics** on.
4. Podedge registers your show with OP3 (one API call) and stores the resulting OP3 show ID.

From this point on, every feed build for this show will prefix enclosure URLs with `https://op3.dev/e`.

## Viewing analytics

Open the **Analytics** view from the sidebar (the chart icon). You'll see:

- **Show-level totals** — downloads and unique listeners over the selected time window
- **Per-episode breakdown** — a bar chart of downloads per episode
- **App breakdown** — which podcast apps your listeners use
- **Geographic breakdown** — downloads by country

Data is refreshed from OP3 every 6 hours in the background. To force a refresh, click the **Refresh** button in the Analytics toolbar.

## Troubleshooting

**No data showing after publishing**
OP3 data typically appears within a few hours of the first download. If you see no data after 24 hours, verify that:
- The OP3 API key in **Settings → Analytics** is correct
- The show has OP3 enabled (show settings → Analytics tab)
- At least one episode has been published (draft episodes are not tracked)

**"OP3 registration failed" error**
This usually means the API key is invalid or expired. Generate a new key at [op3.dev](https://op3.dev) and update it in **Settings → Analytics**.

**Analytics stopped updating**
Check **Settings → Analytics** to confirm the API key is still valid. OP3 API keys do not expire automatically, but you may have regenerated one and forgotten to update Podedge.
