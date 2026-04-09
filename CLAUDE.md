# CLAUDE.md

Guidance for Claude Code when working in this repo.

## Project

Three bash scripts that surface Claude Code rate-limit, context-window, and token usage. Data originates from Claude Code's statusline API (JSON on stdin) and is shared via `/tmp/claude-usage.json`. Targets Claude Pro/Max subscribers (rate limit data is not present for other plans).

## Architecture

```
Claude Code ──stdin(JSON)──▶ statusline-usage.sh ──▶ /tmp/claude-usage.json
                                    │                        │
                                    │                        ├─▶ claude-dashboard.sh (tty)
                                    ▼                        └─▶ claude-menubar.sh   (SwiftBar/xbar)
                             (also prints its
                              own statusline
                              output to stdout)
```

`statusline-usage.sh` is the sole producer. The dashboard and menu bar are independent consumers that poll the JSON file — they never talk to Claude Code directly. This separation is deliberate: Claude Code only invokes one statusline command, and everything else reads the shared snapshot.

## Files

- **`statusline-usage.sh`** — Claude Code statusline script. Parses JSON from stdin, writes `/tmp/claude-usage.json` as a snapshot, and renders a pipe-separated status line:
  `user@host:cwd | ctx:X% | tokens:X.Xk | 7d:X%(4d3h) | 5h:X%(2h14m)`.
  The `5h` field is intentionally last (far right) because it's the most actionable. Includes a `format_time_until` helper that converts a unix timestamp to a compact duration (`2h14m`, `4d3h`, `0m`).

- **`claude-dashboard.sh`** — Full-screen terminal dashboard. Box-drawing frame with progress bars, reset countdowns, context window, token stats. Refreshes every 3s. Uses `tput` for flicker-free updates: render the whole frame into a buffer, then `tput home` + single `printf` + `tput el` + `tput ed` to repaint atomically. Inner frame width is fixed at `INNER=48` visible chars.

- **`claude-menubar.sh`** — SwiftBar/xbar plugin. Emits the plugin line format: menu bar line, then `---`, then dropdown items with `| color=#hex size=N` attributes. Two color palettes: saturated for the menu bar (dark background), darker variants for the dropdown (light background). Plugin metadata in `<xbar.*>` comments at the top.

## Data format

`/tmp/claude-usage.json`:

```json
{
  "timestamp": 1712345678,
  "context_used_pct": 42.3,
  "input_tokens": 15000,
  "output_tokens": 8500,
  "five_hour_pct": 30.0,
  "five_hour_resets_at": 1712353678,
  "seven_day_pct": 15.0,
  "seven_day_resets_at": 1712705678
}
```

Fields may be `null` when the corresponding data isn't present in Claude Code's input (e.g. rate limits before the first API response, or non-Pro/Max accounts). Consumers check for both empty and the literal string `"null"`.

## Conventions

- Plain bash + `jq` + `awk`. No Python, no Node. Scripts assume bash 4+.
- Parsing: `jq -r '.path.to.field // empty'` so missing fields become empty strings rather than the string `"null"`.
- Token formatting uses `awk` because bash arithmetic lacks floats: `%.1fk` >=1000, `%.1fM` >=1M.
- Colors are inline ANSI escapes (`\033[...m`) in the terminal scripts, hex codes (`#RRGGBB`) in the menu bar script. Threshold convention across all three: **green <50%, yellow/orange 50–80%, red >80%**. Keep thresholds in sync if you change one.
- Box-drawing chars: `╭╮╰╯├┤─│`. Progress bars: `█` filled, `░` empty.
- Reset countdowns use a common shape everywhere: `diff = target - now`, then split into days/hours/minutes. Three scripts each have their own local `countdown`/`format_time_until` function — they're small enough that duplication beats a shared file.

## Gotchas

- **Rate limit data is Pro/Max-only** and only appears after the first API response in a session. Before then, the `rate_limits.*` fields are absent and the dashboard renders only the context/token section.
- **`~` and `$HOME` don't expand in Claude Code's statusline execution environment.** `settings.json` entries must use absolute paths for both the interpreter and the script.
- **SwiftBar symlinks must be absolute.** A relative target (e.g. `./claude-menubar.sh`) resolves relative to the plugins directory, not the cwd where `ln -s` was run, and SwiftBar silently skips the plugin.
- **Date parsing differs between Linux and macOS.** The dashboard tries `date -d @$ts` (GNU) first, then `date -r $ts` (BSD). Preserve this fallback when editing time formatting.
- **`/tmp/claude-usage.json` is shared state with no locking.** Writes are small, single-producer, and effectively atomic — don't add locking unless a real race is observed.
- **The statusline script prints to stdout unconditionally now** (PS1 prompt + metrics). Users who want only the JSON snapshot should copy just the `jq -n ... > $usage_file` block into their own statusline script.

## Testing changes

Feed sample JSON to the statusline script to preview output without touching Claude Code:

```bash
now=$(date +%s)
echo "{\"workspace\":{\"current_dir\":\"$PWD\"},\"context_window\":{\"used_percentage\":42,\"total_input_tokens\":15000,\"total_output_tokens\":8500},\"rate_limits\":{\"five_hour\":{\"used_percentage\":30,\"resets_at\":$((now+8040))},\"seven_day\":{\"used_percentage\":15,\"resets_at\":$((now+359100))}}}" | bash statusline-usage.sh
```

After that runs, `/tmp/claude-usage.json` will be populated, so you can also start `./claude-dashboard.sh` (or point SwiftBar at `claude-menubar.sh`) in another terminal and watch the same data render.
