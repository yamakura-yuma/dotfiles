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
      (.rate_limits.five_hour.used_percentage // 0 | floor),
      (.rate_limits.five_hour.resets_at // 0),
      (.rate_limits.seven_day.used_percentage // 0 | floor),
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
  if   [ "$pct" -ge 90 ]; then printf '%s' "🔴 ${RED}"
  elif [ "$pct" -ge 75 ]; then printf '%s' "🟠 ${YELLOW}"
  elif [ "$pct" -ge 50 ]; then printf '%s' "🟡 ${YELLOW}"
  else                         printf '%s' "🟢 ${GREEN}"
  fi
}

# usage: fmt_reset <epoch>  -> "1h30m" / "45m" / "-" until reset
fmt_reset() {
  local target=$1 now diff h m
  [ "$target" -le 0 ] && { printf '%s' "-"; return; }
  now=$(date +%s)
  diff=$(( target - now ))
  [ "$diff" -le 0 ] && { printf '%s' "0m"; return; }
  h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then printf '%dh%dm' "$h" "$m"; else printf '%dm' "$m"; fi
}

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

line2="${CYAN}🧠 ${MODEL}${RESET}"
[ -n "$EFFORT" ] && line2+=" ${DIM}·${RESET} ${YELLOW}⚡${EFFORT}${RESET}"
line2+="  ${CZONE}${CBAR} ${CTX_USED}%${RESET}"
line2+="  ${DIM}|${RESET} ${BOLD}5h${RESET} ${RL5_ZONE}${RL5_BAR} ${RL5_PCT}%${RESET} ${DIM}↻$(fmt_reset "$RL5_RESET")${RESET}"
line2+="  ${DIM}|${RESET} ${BOLD}7d${RESET} ${RL7_ZONE}${RL7_BAR} ${RL7_PCT}%${RESET} ${DIM}↻$(fmt_reset "$RL7_RESET")${RESET}"
[ "$COMPACTS" -gt 0 ] && line2+="  ${DIM}|${RESET} 🗜 ${COMPACTS}"

printf '%s\n%s\n' "$line1" "$line2"