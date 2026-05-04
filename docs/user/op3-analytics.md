# OP3 Analytics

> How download analytics work in Podedge, and how to manage them.
> **Audience:** podcasters who want to track downloads and listener geography.

<!--
Changelog
- 2026-05-04: Rewrote for hands-off UX — auto-registration, no API key required, import path for existing OP3 data.
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

## Setup — nothing to do

During onboarding, the **Download Analytics** step has a single toggle: **Enable download analytics**. It is on by default. Leave it on and continue — that's all.

- No account to create
- No API key to enter
- No URL to configure

Podedge registers your show with OP3 automatically the first time you publish. After that, every episode's download URL is prefixed with `https://op3.dev/e` in your RSS feed, and stats start accumulating.

## Important: this setting is permanent

Once you publish your first episode with analytics enabled, the OP3 prefix is baked into your RSS feed. Disabling it later would change all your enclosure URLs, which breaks download-count continuity and may confuse podcast apps that have cached the old URLs.

Podedge locks this setting after the first publish. **Decide before you publish episode 1.**

## Viewing analytics

Open the **Analytics** view from the sidebar. You'll see:

- **Show-level totals** — downloads and unique listeners over the selected time window
- **Per-episode breakdown** — downloads per episode
- **App breakdown** — which podcast apps your listeners use
- **Geographic breakdown** — downloads by country

Data is refreshed from OP3 every 6 hours in the background. To force a refresh, click **Refresh** in the Analytics toolbar.

You can also view your data directly at [op3.dev](https://op3.dev) — a link is available in **Settings → Analytics**.

## Managing OP3 after setup

Go to **Settings → Analytics** to:

- See your registration status: **Registered** (shows your OP3 Show UUID) or **Pending** (registers on first publish)
- Open your op3.dev dashboard
- Enable or disable analytics for the show
- Import an existing OP3 Show UUID (see below)

## Migrating from another podcast app

If you were already using OP3 with a previous app, your historical download data is tied to an OP3 Show UUID. You can link Podedge to that existing UUID so your analytics history carries over.

### Finding your existing OP3 Show UUID

1. Go to [op3.dev](https://op3.dev) and sign in.
2. Navigate to your show's page.
3. The Show UUID appears in the URL and on the show detail page — it looks like `a1b2c3d4-e5f6-...`.

### Importing the UUID into Podedge

**During onboarding:** On the **Download Analytics** step, expand the **Already using OP3?** section and paste your Show UUID.

**After onboarding:** Go to **Settings → Analytics**, find the **Import existing OP3 data** section, and paste your Show UUID there.

Podedge will use this UUID when registering with OP3 on first publish, linking your new feed to your existing analytics history.

## Troubleshooting

**No data showing after publishing**
OP3 data typically appears within a few hours of the first download. If you see nothing after 24 hours, check that:
- At least one episode has been published (drafts are not tracked)
- The show's registration status in **Settings → Analytics** shows **Registered**

**Analytics stopped updating**
Check **Settings → Analytics** — if registration shows **Pending**, the first publish may not have completed successfully. Try publishing a new episode or contact support.
