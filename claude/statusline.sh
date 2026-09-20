#!/bin/bash
# Claude Code status line
# 2-line status: (1) directory + git branch + diff stats
#                (2) model / context gauge / rate limits / compact count
# Reads session JSON from stdin. Requires jq and git.

input=$(cat)

# --- Parse everything in a single jq pass -------------------------------------
IFS=$'\t' read -r MODEL CUR_DIR CTX_USED CTX_IN CTX_OUT CTX_SIZE \
        RL5_PCT RL5_RESET RL7_PCT RL7_RESET \
        LINES_ADD LINES_DEL SESSION_ID EFFORT < <(
  echo "$input" | jq -r '
    [ (.model.display_name // "?"),
      (.workspace.current_dir // .cwd // "."),
      (.context_window.used_percentage // 0 | floor),
      (.context_window.total_input_tokens // 0),
      (.context_window.total_output_tokens // 0),
      (.context_window.context_window_size // 200000),
      (.rate_limits.five_hour.used_percentage // -1 | floor),
      (.rate_limits.five_hour.resets_at // 0),
      (.rate_limits.seven_day.used_percentage // -1 | floor),
      (.rate_limits.seven_day.resets_at // 0),
      (.cost.total_lines_added // 0),
      (.cost.total_lines_removed // 0),
      (.session_id // "nosession"),
      (.effort.level // "")
    ] | @tsv'
)

# --- Colors -------------------------------------------------------------------
RESET=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
CYAN=$'\033[36m'; MAGENTA=$'\033[35m'; BLUE=$'\033[34m'
GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'

# --- Line 1: directory + git branch + diff stats ------------------------------
# Home directory collapses to ~
DISP_DIR="${CUR_DIR/#$HOME/~}"

BRANCH=""
if GIT_OPTIONAL_LOCKS=0 git -C "$CUR_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(GIT_OPTIONAL_LOCKS=0 git -C "$CUR_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null \
           || GIT_OPTIONAL_LOCKS=0 git -C "$CUR_DIR" rev-parse --short HEAD 2>/dev/null)
fi

line1="${BOLD}${BLUE}📁 ${DISP_DIR}${RESET}"
[ -n "$BRANCH" ] && line1+="  ${MAGENTA}⎇ ${BRANCH}${RESET}"
if [ "$LINES_ADD" -gt 0 ] || [ "$LINES_DEL" -gt 0 ]; then
  line1+="  ${GREEN}+${LINES_ADD}${RESET}${DIM}/${RESET}${RED}-${LINES_DEL}${RESET}"
fi

# --- Gauge bar (10 cells, half-block aware) -----------------------------------
# usage: gauge <percentage> [width]
gauge() {
  local pct=$1 width=${2:-10}
  # -1 means "not known": draw the track, claim no reading.
  if [ "$pct" -lt 0 ]; then
    local empty="" j
    for ((j=0; j<width; j++)); do empty+="░"; done
    printf '%s' "$empty"; return
  fi
  # tenths of a cell filled (each cell = 10% -> pct maps directly to tenths of width)
  local units=$(( pct * width / 100 ))          # full cells
  local rem=$(( pct * width % 100 ))            # remainder for half cell
  local half=0
  [ "$rem" -ge 50 ] && half=1
  [ $(( units + half )) -gt "$width" ] && { units=$width; half=0; }
  local bar="" i
  for ((i=0; i<units; i++)); do bar+="█"; done
  [ "$half" -eq 1 ] && { bar+="▌"; i=$((i+1)); }
  for (( ; i<width; i++ )); do bar+="░"; done
  printf '%s' "$bar"
}

# usage: zone <percentage>  -> emoji + color
zone() {
  local pct=$1
  if   [ "$pct" -lt 0 ];  then printf '%s' "⚪ ${DIM}"
  elif [ "$pct" -ge 90 ]; then printf '%s' "🔴 ${RED}"
  elif [ "$pct" -ge 75 ]; then printf '%s' "🟠 ${YELLOW}"
  elif [ "$pct" -ge 50 ]; then printf '%s' "🟡 ${YELLOW}"
  else                         printf '%s' "🟢 ${GREEN}"
  fi
}

# usage: fmt_span <seconds>  -> "6d2h" / "1h30m" / "45m"
# The 7-day window is days away, so hours alone would render it as "143h20m".
fmt_span() {
  local diff=$1 d h m
  [ "$diff" -le 0 ] && { printf '%s' "0m"; return; }
  d=$(( diff / 86400 )); h=$(( diff % 86400 / 3600 )); m=$(( diff % 3600 / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd%dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"
  else                      printf '%dm' "$m"
  fi
}

# usage: fmt_reset <epoch>  -> time until reset, or "-" when unknown
fmt_reset() {
  local target=$1
  [ "$target" -le 0 ] && { printf '%s' "-"; return; }
  fmt_span $(( target - $(date +%s) ))
}

# usage: to_epoch <epoch-or-ISO8601>  -> epoch seconds, 0 when unparseable.
# jq's fromdateiso8601 rejects both the fractional seconds and the "+00:00"
# offset that ~/.claude.json writes, so the conversion happens out here.
to_epoch() {
  case "$1" in
    '' | 0 | null)  printf '0' ;;
    *[!0-9]*)       date -d "$1" +%s 2>/dev/null || printf '0' ;;
    *)              printf '%s' "$1" ;;
  esac
}

# --- Rate limits: fall back to the on-disk usage snapshot ---------------------
# Claude Code fills .rate_limits in the payload above only when it is talking to
# the API directly. With ANTHROPIC_BASE_URL pointed at a local proxy the field
# arrives null and both gauges go blank -- which is what happened here once
# headroom was configured. Claude Code still writes its own usage snapshot to
# ~/.claude.json, so read that instead.
#
# This must stay a local-file read. A status line runs on every prompt redraw,
# and calling an API to draw it is not acceptable: nothing below this line may
# touch the network.
RL_AGE=-1
if [ "$RL5_PCT" -lt 0 ] || [ "$RL7_PCT" -lt 0 ]; then
  CLAUDE_CONFIG="${CLAUDE_CONFIG_FILE:-$HOME/.claude.json}"
  if [ -r "$CLAUDE_CONFIG" ]; then
    IFS=$'\t' read -r C5_PCT C5_RESET C7_PCT C7_RESET RL_AGE < <(
      jq -r --argjson now "$(date +%s)" '
        (.cachedUsageUtilization // {}) as $c
        | ($c.utilization // {}) as $u
        | ($u.limits // []) as $l
        # Keyed on .group, not .kind, so one code path covers every plan: Pro
        # reports a "session" window plus "weekly_all", while Max adds a
        # "weekly_scoped" window per model. Whichever window within a group is
        # furthest along is the one that will actually stop you, so take the
        # max. Snapshots with no limits[] fall back to the named objects.
        | ($l | map(select(.group == "session")) | max_by(.percent)) as $s
        | ($l | map(select(.group == "weekly"))  | max_by(.percent)) as $w
        | (($c.fetchedAtMs // 0) / 1000 | floor) as $at
        | [ (($s.percent   // $u.five_hour.utilization // -1) | floor),
            ( $s.resets_at // $u.five_hour.resets_at   // ""),
            (($w.percent   // $u.seven_day.utilization // -1) | floor),
            ( $w.resets_at // $u.seven_day.resets_at   // ""),
            (if $at > 0 then $now - $at else -1 end)
          ] | @tsv' "$CLAUDE_CONFIG" 2>/dev/null
    )
    RL_AGE=${RL_AGE:--1}
    if [ "$RL5_PCT" -lt 0 ] && [ "${C5_PCT:--1}" -ge 0 ]; then
      RL5_PCT=$C5_PCT; RL5_RESET=$C5_RESET
    fi
    if [ "$RL7_PCT" -lt 0 ] && [ "${C7_PCT:--1}" -ge 0 ]; then
      RL7_PCT=$C7_PCT; RL7_RESET=$C7_RESET
    fi
  fi
fi
RL5_RESET=$(to_epoch "$RL5_RESET")
RL7_RESET=$(to_epoch "$RL7_RESET")

# A cached percentage whose window has already reset describes a window that no
# longer exists. Show it as last-known rather than as current.
NOW=$(date +%s)
RL5_MARK=""; RL7_MARK=""
[ "$RL_AGE" -ge 0 ] && [ "$RL5_RESET" -gt 0 ] && [ "$RL5_RESET" -le "$NOW" ] && RL5_MARK="~"
[ "$RL_AGE" -ge 0 ] && [ "$RL7_RESET" -gt 0 ] && [ "$RL7_RESET" -le "$NOW" ] && RL7_MARK="~"

# --- Compaction detection (per-session token-drop counter) --------------------
STATE_DIR="$HOME/.claude/statusline-state"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE_FILE="$STATE_DIR/${SESSION_ID}"
COMPACTS=0
PREV_PCT=0
if [ -f "$STATE_FILE" ]; then
  read -r PREV_PCT COMPACTS < "$STATE_FILE" 2>/dev/null
  PREV_PCT=${PREV_PCT:-0}; COMPACTS=${COMPACTS:-0}
fi
# A large drop in context usage during a live session indicates a /compact.
if [ "$PREV_PCT" -ge 30 ] && [ $(( PREV_PCT - CTX_USED )) -ge 25 ]; then
  COMPACTS=$(( COMPACTS + 1 ))
fi
printf '%s %s\n' "$CTX_USED" "$COMPACTS" > "$STATE_FILE"

# --- Line 2: model / context gauge / rate limits / compacts -------------------
CZONE=$(zone "$CTX_USED")
CBAR=$(gauge "$CTX_USED")

RL5_ZONE=$(zone "$RL5_PCT"); RL5_BAR=$(gauge "$RL5_PCT" 6)
RL7_ZONE=$(zone "$RL7_PCT"); RL7_BAR=$(gauge "$RL7_PCT" 6)
[ "$RL5_PCT" -lt 0 ] && RL5_TXT="?%" || RL5_TXT="${RL5_MARK}${RL5_PCT}%"
[ "$RL7_PCT" -lt 0 ] && RL7_TXT="?%" || RL7_TXT="${RL7_MARK}${RL7_PCT}%"

line2="${CYAN}🧠 ${MODEL}${RESET}"
[ -n "$EFFORT" ] && line2+=" ${DIM}·${RESET} ${YELLOW}⚡${EFFORT}${RESET}"
line2+="  ${CZONE}${CBAR} ${CTX_USED}%${RESET}"
line2+="  ${DIM}|${RESET} ${BOLD}5h${RESET} ${RL5_ZONE}${RL5_BAR} ${RL5_TXT}${RESET} ${DIM}↻$(fmt_reset "$RL5_RESET")${RESET}"
line2+="  ${DIM}|${RESET} ${BOLD}7d${RESET} ${RL7_ZONE}${RL7_BAR} ${RL7_TXT}${RESET} ${DIM}↻$(fmt_reset "$RL7_RESET")${RESET}"
# How old the snapshot is, shown only when the numbers came from it, because a
# stale reading that looks live is worse than no reading.
[ "$RL_AGE" -ge 0 ] && line2+=" ${DIM}⧗$(fmt_span "$RL_AGE")${RESET}"
[ "$COMPACTS" -gt 0 ] && line2+="  ${DIM}|${RESET} 🗜 ${COMPACTS}"

printf '%s\n%s\n' "$line1" "$line2"