# Claude Usage Tracker

Track your Claude Code rate limits, context window usage, and token counts — in a terminal dashboard or the macOS menu bar. No API keys or session cookies needed; it reads directly from Claude Code's statusline data.

```
╭────────────────────────────────────────────────╮
│             Claude Usage Dashboard             │
├────────────────────────────────────────────────┤
│                                                │
│  5-Hour Limit                                  │
│  ██████████████░░░░░░░░░░░░░░░░░░░░  42.3%     │
│    Resets in: 2h 34m                           │
│                                                │
│  7-Day Limit                                   │
│  ██████████████████████████░░░░░░░░  78.7%     │
│    Resets in: 3d 12h 5m                        │
│                                                │
├────────────────────────────────────────────────┤
│                                                │
│  Context Window: 24%                           │
│  Session Tokens: 47.0k                         │
│    In / Out: 34.2k / 12.8k                     │
│                                                │
├────────────────────────────────────────────────┤
│  Last data: 14:32:05                           │
│  Clock: 14:35                                  │
╰────────────────────────────────────────────────╯
```

## How it works

Three scripts share a simple data pipeline:

1. **`statusline-usage.sh`** — A Claude Code [statusline](https://docs.anthropic.com/en/docs/claude-code/status-line) script that runs automatically after each API response. It writes a JSON snapshot of your current usage data to `/tmp/claude-usage.json` **and** renders a compact, color-coded status line in your Claude Code prompt (see below).

2. **`claude-dashboard.sh`** — A terminal dashboard that reads that JSON file every 3 seconds and renders a live display with progress bars, countdowns, and color-coded warnings.

3. **`claude-menubar.sh`** — A [SwiftBar](https://github.com/swiftbar/SwiftBar)/[xbar](https://github.com/matryer/xbar) plugin that displays the same data in the macOS menu bar.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Claude Pro/Max subscription for rate limit data)
- `jq` — JSON processor
- `bash` 4+
- A terminal that supports Unicode and ANSI colors

## Setup

### 1. Install the statusline script

Copy `statusline-usage.sh` somewhere permanent:

```bash
cp statusline-usage.sh ~/.claude/statusline-usage.sh
```

### 2. Configure Claude Code to use it

Add the following to your `~/.claude/settings.json`, using **absolute paths** for both the interpreter and the script:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/bin/bash /Users/YOUR_USER/.claude/statusline-usage.sh"
  }
}
```

> **Important:** Tilde (`~`) and `$HOME` may not expand in the statusline execution environment. Always use fully resolved absolute paths (e.g. `/Users/yourname/...` on macOS, `/home/yourname/...` on Linux).

Your Claude Code prompt will now show something like:

```
user@host:/path/to/project | ctx:42% | tokens:23.5k | 7d:15%(4d3h) | 5h:30%(2h14m)
```

Fields (left to right): current working directory, context window %, total session tokens, 7-day rate limit with time until reset, 5-hour rate limit with time until reset. The 5-hour limit is pinned to the far right since it's the one that matters most day-to-day.

If you already have a statusline script, you can integrate just the usage-tracking part into your existing script — copy the `jq -n ... > /tmp/claude-usage.json` block that writes the snapshot file and leave the rest of your script alone.

### 3. Choose a display

#### Option A: Terminal dashboard

Open a separate terminal (or tmux pane) and run:

```bash
./claude-dashboard.sh
```

Press `Ctrl+C` to exit.

The dashboard will show "Waiting for data..." until you interact with Claude Code in another terminal. After your first message, the statusline script fires and the dashboard picks up the data.

#### Option B: macOS menu bar (SwiftBar)

Install [SwiftBar](https://github.com/swiftbar/SwiftBar):

```bash
brew install --cask swiftbar
```

On first launch, SwiftBar will ask you to choose a plugin directory (e.g. `~/swiftbar-plugins/`). Then symlink the plugin using **absolute paths** for both arguments:

```bash
ln -s /absolute/path/to/claude-menubar.sh /absolute/path/to/swiftbar-plugins/claude-usage.1m.sh
```

> **Important:** Both the symlink target and destination must be absolute paths. A relative target (e.g. `./claude-menubar.sh`) will resolve relative to the plugins directory, not where you ran the command, and SwiftBar will silently fail to load it.

The suffix in the filename tells SwiftBar how often to refresh (e.g. `3s`, `10s`, `1m`).

The menu bar will show a compact `5h:42% 7d:19%` summary, color-coded green/yellow/red. Click it to see the full dropdown with reset countdowns, context window, and token stats.

> **Note:** [xbar](https://github.com/matryer/xbar) uses the same plugin format, so `claude-menubar.sh` works with either.

## What it shows

| Section | Description |
|---------|-------------|
| **5-Hour Limit** | Rolling 5-hour rate limit usage with reset countdown |
| **7-Day Limit** | Rolling 7-day rate limit usage with reset countdown |
| **Context Window** | How much of the current session's context window is used |
| **Session Tokens** | Total tokens consumed in the current session (in/out) |

Progress bars are color-coded:
- **Green** — under 50%
- **Yellow** — 50–80%
- **Red** — over 80%

## Tips

- **tmux split**: `Ctrl+B "` to split horizontally, then run the dashboard in the bottom pane
- **Dedicated tmux session**: `tmux new-session -d -s dashboard './claude-dashboard.sh'`
- **Rate limit data** only appears for Claude Pro/Max subscribers, and only after the first API response in a session
