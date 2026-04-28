# Podedge UI Design

## Design Philosophy

Native macOS look and feel. No custom chrome, no Electron vibes. Think Apple
Notes meets Locally AI — clean, minimal, uses system fonts, system colors,
standard macOS controls. The app should feel like it shipped with the OS.

Reference: [Locally AI](https://locallyai.app/) for the native-but-slick
aesthetic. Clean sidebar, generous whitespace, no visual clutter.

## Main Window Layout

```
┌─────────────────────────────────────────────────────────────────────┐
│  ◉ ◉ ◉                        Podedge                             │
├──────────────┬──────────────────────────────────────────────────────┤
│              │                                                      │
│  ┌────┬────┐ │              Dashboard (default)                     │
│  │Shows│Eps │ │                                                      │
│  ├────┴────┤ │  ┌─────────────────────────────────────────────┐     │
│  │          │ │  │  Downloads ▲12%    Listeners ▲8%    Eps 42  │     │
│  │ Show A   │ │  └─────────────────────────────────────────────┘     │
│  │ Show B ● │ │                                                      │
│  │ Show C   │ │  ┌─ Per-Episode Breakdown ──────────────────────┐    │
│  │          │ │  │  📊 Chart: downloads over time               │    │
│  │          │ │  │  (or per-show cards if multiple shows)       │    │
│  │          │ │  └──────────────────────────────────────────────┘    │
│  │          │ │                                                      │
│  │          │ │  ┌─ Scheduled Tasks ────────────────────────────┐    │
│  │          │ │  │  🟡 Ep43 publishing...          in 2 min     │    │
│  │          │ │  │  🔵 Ep42 social posts           scheduled 3pm│    │
│  │          │ │  │  ⚪ Ep44 transcription           queued       │    │
│  │          │ │  └──────────────────────────────────────────────┘    │
│  │          │ │                                                      │
│  │          │ ├──────────────────────────────────────────────────────┤
│  │          │ │  💬 Ask Podedge...                                   │
│  │          │ │                                                      │
│  │          │ │  Try: "Publish my latest episode"                    │
│  │          │ │       "How did last week's episode perform?"         │
│  │          │ │       "Draft social posts for Ep42"                  │
│  └──────────┘ │                                                      │
└──────────────┴──────────────────────────────────────────────────────┘
```

### Left Sidebar

Narrow sidebar with two tabs at the top: **Shows** and **Episodes**.

- **Shows tab:** List of podcast shows. Selecting a show filters the
  Episodes tab and updates the dashboard to show that show's metrics.
- **Episodes tab:** Episode list for the selected show (or all shows).
  Status indicator (colored dot), title, date. Selecting an episode opens
  the episode editor in the main area.

The sidebar uses standard `List` with `.sidebar` style. No custom row
chrome — just text, a status dot, and maybe a small cover thumbnail.

### Main Content Area (Center)

Context-dependent. What shows here depends on what's selected:

**Nothing selected (default) → Dashboard**
- Summary metrics cards at the top (downloads, unique listeners, episode
  count, trend arrows). If one show, break down per episode. If multiple
  shows, show per-show cards.
- Scheduled/active tasks: episodes being published, transcriptions in
  progress, social media posts queued. Each row shows task type, target,
  and status/ETA.
- Recent activity feed (last published, last generated metadata, etc.).

**Show selected → Show Detail**
- Show metadata (editable), cover art, host binding, distribution status.
- Per-episode metrics chart (SwiftCharts).
- Feed preview button, analytics deep-link.

**Episode selected → Episode Editor**
- Tabbed view: Metadata, Transcript/Chapters, Promotion, Publish.
- Same as the original spec but rendered in the main content area, not a
  third column.

### Chat Bar (Bottom Center)

Always visible at the bottom of the main content area. Not a separate pane
— it's integrated into the layout like Spotlight or Raycast's input.

- Single-line text input with a send button. Expands into a conversation
  view when active (pushes content up or overlays as a sheet/popover).
- Below the input: 3 context-sensitive prompt suggestions ("Try asking…").
  These rotate based on current selection and recent activity.
- ⌘K focuses the chat input from anywhere.
- When a conversation is active, it takes over the main content area
  (or slides up as a panel). Tool-call rows are inline, collapsible.
- Provider + model label on each assistant response.
- "New chat" clears the conversation. Dismissing returns to the previous
  content view.

### No Right Pane

The original spec had a dockable assistant pane on the right. This design
removes it. The chat lives at the bottom of the center area — always
accessible, never competing for horizontal space. The app stays a clean
two-column layout (sidebar + content).

## Navigation Model

```
Sidebar selection          →  Main content area shows
─────────────────────────────────────────────────
Nothing / Dashboard        →  Metrics + scheduled tasks + activity
Show (from Shows tab)      →  Show detail + per-episode metrics
Episode (from Episodes tab)→  Episode editor (tabbed)
Settings (gear icon)       →  Settings view (tabbed)
```

The sidebar has a gear icon at the bottom for Settings. Onboarding is a
separate window/sheet on first launch.

## Visual Style

- **System font** (SF Pro) throughout. No custom fonts.
- **System colors** for accents. Respect light/dark mode automatically.
- **Generous whitespace.** Don't cram. Let content breathe.
- **Subtle separators.** Use `.plain` list style where possible. Minimal
  borders and dividers.
- **Status indicators:** Small colored dots (SF Symbols `circle.fill`),
  not badges or pills. Draft = gray, processing = blue, ready = green,
  published = teal, failed = red.
- **Charts:** SwiftCharts with default styling. No custom chart chrome.
- **Cover art:** Rounded corners (`.clipShape(.rect(cornerRadius: 8))`),
  subtle shadow.
- **Toolbar:** Standard macOS toolbar with title, search field, and a few
  icon buttons (new episode, refresh, settings).

## Menu Bar Accessory

Separate from the main window. Small menu bar icon
(`dot.radiowaves.left.and.right`).

Dropdown shows:
- Active jobs with progress bars.
- "New Episode" quick action.
- "Open Podedge" to bring up the main window.
- Quit.

## Key Interactions

| Action | How |
|---|---|
| New episode | Drag MP3 onto sidebar, or toolbar + button, or menu bar |
| Open chat | ⌘K or click the chat input |
| Switch show | Click in Shows tab |
| Browse episodes | Click Episodes tab, then select |
| Settings | Gear icon in sidebar footer, or ⌘, |
| Feed preview | Button in show detail view |
| Publish | Button in episode editor Publish tab, or ask the chat |

## Differences from Original Spec

| Original | Revised | Rationale |
|---|---|---|
| Three-column NavigationSplitView | Two-column (sidebar + content) | Cleaner, more native feel. Episode detail doesn't need its own column. |
| Assistant as dockable right pane | Chat bar at bottom of content area | Less chrome, always accessible, doesn't fight for horizontal space. |
| Pane visible by default on first launch | Chat input visible, conversation collapsed | Discoverable without dominating the screen. |
| Episode list as middle column | Episodes tab in sidebar | Keeps sidebar compact, one place for navigation. |
| Dashboard not specified | Dashboard as default main view | Gives the app a useful landing page with metrics + task status. |

## Decisions

1. **Chat expansion:** Inline — pushes content up. No overlay/sheet.
2. **Dashboard refresh:** Pull/timer only. OP3 is not real-time. Manual
   refresh button + background poll on the 6h OP3 cycle.
3. **Drag-drop target:** Both sidebar and main content area.
