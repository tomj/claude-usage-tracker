#!/usr/bin/env bash
# Claude Usage Dashboard — live terminal display
# Reads from /tmp/claude-usage.json (written by statusline-command.sh)

USAGE_FILE="/tmp/claude-usage.json"
STATUS_CACHE="/tmp/claude-status-rss.cache"
STATUS_MAX_AGE=60
REFRESH=3

# Colors
RST="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
WHITE="\033[37m"

INNER=48  # visible chars between │ and │

# ── Drawing primitives ──────────────────────────────────────
# Every row outputs exactly INNER+2 visible characters (│ + 48 + │)

hline() { # hline <left_corner> <right_corner>
  local fill=""
  for ((i = 0; i < INNER; i++)); do fill+="─"; done
  printf '%s%s%s\n' "$1" "$fill" "$2"
}

blank() { printf '│%*s│\n' $INNER ""; }

# Center text with optional color
center() { # center <text> [ansi_color]
  local t="$1" c="${2:-}"
  local lp=$(( (INNER - ${#t}) / 2 ))
  local rp=$(( INNER - ${#t} - lp ))
  printf "│%*s%b%s%b%*s│\n" $lp "" "$c$BOLD" "$t" "$RST" $rp ""
}

# Section header (bold, 2-space indent, no colon)
hdr() { # hdr <title>
  local t="$1"
  local pad=$(( INNER - 2 - ${#t} ))
  printf "│  %b%s%b%*s│\n" "$BOLD$WHITE" "$t" "$RST" $pad ""
}

# Label: Value row (2-space indent)
lv() { # lv <label> <value> [ansi_color]
  local lab="$1" val="$2" c="${3:-$WHITE}"
  # visible: 2(indent) + label + 2(": ") + value
  local pad=$(( INNER - 2 - ${#lab} - 2 - ${#val} ))
  (( pad < 0 )) && pad=0
  printf "│  %b%s:%b %b%s%b%*s│\n" "$DIM" "$lab" "$RST" "$c" "$val" "$RST" $pad ""
}

# Indented label: value (4-space indent)
lv2() { # lv2 <label> <value> [ansi_color]
  local lab="$1" val="$2" c="${3:-$WHITE}"
  local pad=$(( INNER - 4 - ${#lab} - 2 - ${#val} ))
  (( pad < 0 )) && pad=0
  printf "│    %b%s:%b %b%s%b%*s│\n" "$DIM" "$lab" "$RST" "$c" "$val" "$RST" $pad ""
}

# Progress bar
pbar() { # pbar <percentage>
  local pct="$1" bw=34 c
  local int_pct
  int_pct=$(printf '%.0f' "$pct")

  if   (( int_pct < 50 )); then c="$GREEN"
  elif (( int_pct < 80 )); then c="$YELLOW"
  else c="$RED"; fi

  local filled
  filled=$(awk "BEGIN { printf \"%d\", $pct * $bw / 100 }")
  (( filled > bw )) && filled=$bw
  local empty=$(( bw - filled ))

  local b=""
  for ((i = 0; i < filled; i++)); do b+="█"; done
  for ((i = 0; i < empty; i++)); do b+="░"; done

  local ps
  ps=$(printf "%5.1f%%" "$pct")  # always 6 chars wide
  # visible: 2(indent) + bw(bar) + 1(space) + 6(pct) = 43
  local pad=$(( INNER - 2 - bw - 1 - ${#ps} ))
  (( pad < 0 )) && pad=0
  printf "│  %b%s%b %b%s%b%*s│\n" "$c" "$b" "$RST" "$BOLD" "$ps" "$RST" $pad ""
}

# ── Status page ────────────────────────────────────────────

fetch_status() {
  local now
  now=$(date +%s)
  # Re-fetch if cache is missing or stale
  if [ ! -f "$STATUS_CACHE" ] || \
     (( now - $(stat -f %m "$STATUS_CACHE" 2>/dev/null || echo 0) > STATUS_MAX_AGE )); then
    curl -sf --max-time 5 https://status.claude.com/history.rss > "$STATUS_CACHE.tmp" 2>/dev/null \
      && mv "$STATUS_CACHE.tmp" "$STATUS_CACHE" \
      || rm -f "$STATUS_CACHE.tmp"
  fi
}

# Returns the title of the first unresolved incident, or empty string
get_active_incident() {
  [ -f "$STATUS_CACHE" ] || return
  # Extract items, check if the first <strong> in description is NOT "Resolved"
  awk '
    /<item>/      { in_item=1; title=""; desc="" }
    /<\/item>/    { in_item=0
      # Check if latest status (first <strong>) is Resolved
      if (desc !~ /<strong>Resolved<\/strong>/) {
        print title
        exit
      }
    }
    in_item && /<title>/ {
      gsub(/.*<title>/, ""); gsub(/<\/title>.*/, "")
      title = $0
    }
    in_item && /<description>/ { in_desc=1; desc="" }
    in_desc { desc = desc $0 }
    /<\/description>/ { in_desc=0 }
  ' "$STATUS_CACHE"
}

# ── Helpers ─────────────────────────────────────────────────

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

# ── Main render ─────────────────────────────────────────────

render() {
  local now
  now=$(date +%s)

  # Render entire frame into buffer to avoid flicker
  local buf
  buf=$(
    echo ""
    hline "╭" "╮"
    center "Claude Usage Dashboard" "$CYAN"
    hline "├" "┤"

    if [ ! -f "$USAGE_FILE" ]; then
      blank
      center "Waiting for data..." "$DIM"
      center "Start a Claude Code session" "$DIM"
      center "to begin tracking" "$DIM"
      blank
      hline "╰" "╯"
      exit 0
    fi

    local data
    data=$(<"$USAGE_FILE") 2>/dev/null
    if [ -z "$data" ]; then
      center "No data available" "$DIM"
      hline "╰" "╯"
      exit 0
    fi

    local ts fh fhr sd sdr ctx tin tout
    ts=$(echo "$data" | jq -r '.timestamp // empty')
    fh=$(echo "$data" | jq -r '.five_hour_pct // empty')
    fhr=$(echo "$data" | jq -r '.five_hour_resets_at // empty')
    sd=$(echo "$data" | jq -r '.seven_day_pct // empty')
    sdr=$(echo "$data" | jq -r '.seven_day_resets_at // empty')
    ctx=$(echo "$data" | jq -r '.context_used_pct // empty')
    tin=$(echo "$data" | jq -r '.input_tokens // empty')
    tout=$(echo "$data" | jq -r '.output_tokens // empty')

    blank

    # 5-Hour Rate Limit
    if [ -n "$fh" ] && [ "$fh" != "null" ]; then
      hdr "5-Hour Limit"
      pbar "$fh"
      if [ -n "$fhr" ] && [ "$fhr" != "null" ]; then
        lv2 "Resets in" "$(countdown "$fhr")" "$CYAN"
      fi
      blank
    fi

    # 7-Day Rate Limit
    if [ -n "$sd" ] && [ "$sd" != "null" ]; then
      hdr "7-Day Limit"
      pbar "$sd"
      if [ -n "$sdr" ] && [ "$sdr" != "null" ]; then
        lv2 "Resets in" "$(countdown "$sdr")" "$CYAN"
      fi
      blank
    fi

    # Active session stats
    hline "├" "┤"
    blank
    hdr "Active Session"

    if [ -n "$ctx" ] && [ "$ctx" != "null" ]; then
      local cc="$GREEN" ci
      ci=$(printf '%.0f' "$ctx")
      if   (( ci > 80 )); then cc="$RED"
      elif (( ci > 50 )); then cc="$YELLOW"; fi
      lv "Context Window" "${ci}%" "$cc"
    fi

    if [ -n "$tin" ] && [ "$tin" != "null" ] && [ -n "$tout" ] && [ "$tout" != "null" ]; then
      local total=$(( tin + tout ))
      lv "Session Tokens" "$(fmttok $total)" "$WHITE"
      lv2 "In / Out" "$(fmttok "$tin") / $(fmttok "$tout")" "$DIM"
    fi

    blank

    # Footer
    hline "├" "┤"
    local ut="--:--:--"
    if [ -n "$ts" ]; then
      ut=$(date -d "@$ts" +"%H:%M:%S" 2>/dev/null || date -r "$ts" +"%H:%M:%S" 2>/dev/null || echo "unknown")
    fi
    lv "Last data" "$ut" "$DIM"
    lv "Clock" "$(date +%H:%M)" "$WHITE"

    # Status page incidents
    fetch_status
    local incident
    incident=$(get_active_incident)
    if [ -n "$incident" ]; then
      local short
      short=$(echo "$incident" | awk '{print $1, $2}')
      hline "├" "┤"
      local _t="Active Incident"
      local _d="$short"
      printf '│  %b%s%b%*s│\n' "$BOLD$YELLOW" "$_t" "$RST" $(( INNER - 2 - ${#_t} )) ""
      printf '│  %b%s%b%*s│\n' "$DIM$YELLOW" "$_d" "$RST" $(( INNER - 2 - ${#_d} )) ""
    fi

    hline "╰" "╯"
  )

  # Single atomic write: reposition cursor, paint buffer, clear leftovers
  tput home
  printf '%s' "$buf"
  tput el      # clear rest of last line
  tput ed      # clear any trailing lines from a previously taller frame
}

# ── Entry point ─────────────────────────────────────────────

trap 'tput cnorm; tput clear; exit 0' INT TERM
tput civis  # hide cursor
tput clear

while true; do
  render
  sleep "$REFRESH"
done
