# Claude Usage Tracker

A live-updating terminal dashboard that shows your Claude Code rate limits, context window usage, and token counts.

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

Two scripts work together:

1. **`statusline-usage.sh`** — A Claude Code [statusline](https://docs.anthropic.com/en/docs/claude-code/status-line) script that runs automatically after each API response. It writes a JSON snapshot of your current usage data to `/tmp/claude-usage.json`.

2. **`claude-dashboard.sh`** — A terminal dashboard that reads that JSON file every 3 seconds and renders a live display with progress bars, countdowns, and color-coded warnings.

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

Add the following to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-usage.sh"
  }
}
```

If you already have a statusline script, you can integrate the usage-tracking part into your existing script. The key section to copy is the `jq -n ... > /tmp/claude-usage.json` block that writes the snapshot file.

### 3. Run the dashboard

Open a separate terminal (or tmux pane) and run:

```bash
./claude-dashboard.sh
```

Press `Ctrl+C` to exit.

The dashboard will show "Waiting for data..." until you interact with Claude Code in another terminal. After your first message, the statusline script fires and the dashboard picks up the data.

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

A staleness warning appears if the data is more than 5 minutes old.

## Tips

- **tmux split**: `Ctrl+B "` to split horizontally, then run the dashboard in the bottom pane
- **Dedicated tmux session**: `tmux new-session -d -s dashboard './claude-dashboard.sh'`
- **Rate limit data** only appears for Claude Pro/Max subscribers, and only after the first API response in a session
