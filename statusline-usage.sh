#!/usr/bin/env bash
# Claude Code statusline script — writes usage data to /tmp/claude-usage.json
# for the claude-dashboard.sh to read.
#
# This script is called by Claude Code via the statusLine setting.
# It receives JSON on stdin with rate limits, context window, and token data.
#
# You can add your own statusline output (printf/echo) alongside this script,
# or source it from an existing statusline script.

input=$(cat)

# Parse rate limit and session data from Claude Code's JSON
ctx_used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Write usage snapshot for the dashboard
usage_file="/tmp/claude-usage.json"
jq -n \
  --arg ts "$(date +%s)" \
  --arg ctx "${ctx_used:-}" \
  --arg tin "${total_in:-}" \
  --arg tout "${total_out:-}" \
  --arg fh "${five_hour:-}" \
  --arg fhr "${five_hour_resets:-}" \
  --arg sd "${seven_day:-}" \
  --arg sdr "${seven_day_resets:-}" \
  '{
    timestamp: ($ts | tonumber),
    context_used_pct: (if $ctx != "" then ($ctx | tonumber) else null end),
    input_tokens: (if $tin != "" then ($tin | tonumber) else null end),
    output_tokens: (if $tout != "" then ($tout | tonumber) else null end),
    five_hour_pct: (if $fh != "" then ($fh | tonumber) else null end),
    five_hour_resets_at: (if $fhr != "" then ($fhr | tonumber) else null end),
    seven_day_pct: (if $sd != "" then ($sd | tonumber) else null end),
    seven_day_resets_at: (if $sdr != "" then ($sdr | tonumber) else null end)
  }' > "$usage_file" 2>/dev/null

# Format seconds until a target unix timestamp as e.g. "2h14m" or "4d3h"
format_time_until() {
  local target=$1
  local now diff days hours minutes
  now=$(date +%s)
  diff=$((target - now))
  if [ "$diff" -le 0 ]; then
    printf "0m"
    return
  fi
  days=$((diff / 86400))
  hours=$(((diff % 86400) / 3600))
  minutes=$(((diff % 3600) / 60))
  if [ "$days" -gt 0 ]; then
    printf "%dd%dh" "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf "%dh%dm" "$hours" "$minutes"
  else
    printf "%dm" "$minutes"
  fi
}

# Optional: print a compact status to the Claude Code statusline
metrics=""
if [ -n "$ctx_used" ]; then
  metrics="ctx:$(printf '%.0f' "$ctx_used")%"
fi
if [ -n "$five_hour" ]; then
  metrics="$metrics 5h:$(printf '%.0f' "$five_hour")%"
  if [ -n "$five_hour_resets" ]; then
    metrics="$metrics($(format_time_until "$five_hour_resets"))"
  fi
fi
if [ -n "$seven_day" ]; then
  metrics="$metrics 7d:$(printf '%.0f' "$seven_day")%"
  if [ -n "$seven_day_resets" ]; then
    metrics="$metrics($(format_time_until "$seven_day_resets"))"
  fi
fi
if [ -n "$metrics" ]; then
  printf "%s" "$metrics"
fi
