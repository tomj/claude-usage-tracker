#!/usr/bin/env bash
# Claude Usage — SwiftBar/xbar plugin
# Reads /tmp/claude-usage.json and displays usage in the macOS menu bar.
#
# Install: symlink or copy to your SwiftBar plugins directory as:
#   claude-usage.3s.sh
#
# The "3s" in the filename means SwiftBar runs this every 3 seconds.

USAGE_FILE="/tmp/claude-usage.json"

countdown() {
  local ra="$1" now diff
  now=$(date +%s)
  diff=$(( ra - now ))
  (( diff <= 0 )) && { echo "now"; return; }
  local d=$(( diff / 86400 )) h=$(( diff % 86400 / 3600 )) m=$(( diff % 3600 / 60 ))
  if   (( d > 0 )); then printf '%dd %dh %dm' "$d" "$h" "$m"
  elif (( h > 0 )); then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

fmttok() {
  local t="$1"
  if   (( t >= 1000000 )); then awk "BEGIN { printf \"%.1fM\", $t/1000000 }"
  elif (( t >= 1000 ));    then awk "BEGIN { printf \"%.1fk\", $t/1000 }"
  else echo "$t"; fi
}

color_for_pct() {
  local pct="$1"
  local int_pct
  int_pct=$(printf '%.0f' "$pct")
  if   (( int_pct < 50 )); then echo "#4CAF50"  # green
  elif (( int_pct < 80 )); then echo "#FF9800"  # orange
  else echo "#F44336"; fi                         # red
}

# ── No data yet ─────────────────────────────────────────────
if [ ! -f "$USAGE_FILE" ]; then
  echo "Claude: --"
  echo "---"
  echo "No usage data yet"
  echo "Start a Claude Code session to begin tracking"
  exit 0
fi

data=$(<"$USAGE_FILE") 2>/dev/null
if [ -z "$data" ]; then
  echo "Claude: --"
  echo "---"
  echo "Empty data file"
  exit 0
fi

# ── Parse JSON ──────────────────────────────────────────────
ts=$(echo "$data" | jq -r '.timestamp // empty')
fh=$(echo "$data" | jq -r '.five_hour_pct // empty')
fhr=$(echo "$data" | jq -r '.five_hour_resets_at // empty')
sd=$(echo "$data" | jq -r '.seven_day_pct // empty')
sdr=$(echo "$data" | jq -r '.seven_day_resets_at // empty')
ctx=$(echo "$data" | jq -r '.context_used_pct // empty')
tin=$(echo "$data" | jq -r '.input_tokens // empty')
tout=$(echo "$data" | jq -r '.output_tokens // empty')

# ── Menu bar line (compact) ─────────────────────────────────
bar_parts=""
bar_color="#4CAF50"

if [ -n "$fh" ] && [ "$fh" != "null" ]; then
  fh_int=$(printf '%.0f' "$fh")
  bar_parts="5h:${fh_int}%"
  bar_color=$(color_for_pct "$fh")
fi

if [ -n "$sd" ] && [ "$sd" != "null" ]; then
  sd_int=$(printf '%.0f' "$sd")
  if [ -n "$bar_parts" ]; then
    bar_parts="$bar_parts  7d:${sd_int}%"
  else
    bar_parts="7d:${sd_int}%"
  fi
  # Use the worse color of the two
  sd_color=$(color_for_pct "$sd")
  sd_i=$(printf '%.0f' "$sd")
  fh_i=$(printf '%.0f' "${fh:-0}")
  if (( sd_i > fh_i )); then bar_color="$sd_color"; fi
fi

if [ -z "$bar_parts" ]; then
  bar_parts="Claude: --"
fi

echo "$bar_parts | color=$bar_color size=13"

# ── Dropdown ────────────────────────────────────────────────
echo "---"

# 5-Hour Limit
if [ -n "$fh" ] && [ "$fh" != "null" ]; then
  fh_color=$(color_for_pct "$fh")
  printf "5-Hour Limit: %.1f%% | color=%s\n" "$fh" "$fh_color"
  if [ -n "$fhr" ] && [ "$fhr" != "null" ]; then
    echo "  Resets in: $(countdown "$fhr") | color=#999999 size=12"
  fi
fi

# 7-Day Limit
if [ -n "$sd" ] && [ "$sd" != "null" ]; then
  sd_color=$(color_for_pct "$sd")
  printf "7-Day Limit: %.1f%% | color=%s\n" "$sd" "$sd_color"
  if [ -n "$sdr" ] && [ "$sdr" != "null" ]; then
    echo "  Resets in: $(countdown "$sdr") | color=#999999 size=12"
  fi
fi

echo "---"

# Active Session
echo "Active Session | size=12 color=#999999"
if [ -n "$ctx" ] && [ "$ctx" != "null" ]; then
  ci=$(printf '%.0f' "$ctx")
  ctx_color=$(color_for_pct "$ctx")
  echo "  Context Window: ${ci}% | color=$ctx_color"
fi
if [ -n "$tin" ] && [ "$tin" != "null" ] && [ -n "$tout" ] && [ "$tout" != "null" ]; then
  total=$(( tin + tout ))
  echo "  Tokens: $(fmttok $total) (in: $(fmttok "$tin") / out: $(fmttok "$tout")) | color=#CCCCCC"
fi

echo "---"

# Footer
if [ -n "$ts" ]; then
  ut=$(date -d "@$ts" +"%H:%M:%S" 2>/dev/null || date -r "$ts" +"%H:%M:%S" 2>/dev/null || echo "unknown")
  echo "Last data: $ut | size=11 color=#666666"
fi
echo "Refresh | refresh=true"
