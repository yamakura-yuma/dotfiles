#!/usr/bin/env bash
# PreToolUse guardrail, no matcher: stop a worker that has used up its money,
# its wall-clock time or its tool calls. Registered by ../worker-limit.json.
#
# The limits come from ~/.claude/worker-reports/<branch>.limits.json, written by
# whoever starts the worker (the topic chat), keyed by the worktree's branch --
# worker-start's --name is the branch:
#
#   {"zone":"green","usd":15,"minutes":90,"tool_calls":300}
#
# No such file, no opinion: the coordinator, a topic chat and a human's own
# session have none, so this hook does nothing there. A field that is missing or
# not a number is no limit on that axis.
#
#   usd         the status line's cost.total_cost_usd, which only the status
#               line input carries; claude/statusline.sh leaves it in
#               ~/.claude/statusline-state/<session_id>.cost. It is the cost up
#               to the previous redraw, so it trails by about one tool call.
#   minutes     now - the Dispatch's dispatchedAt (orca orchestration
#               worker-show). Not total_duration_ms: that stops counting while
#               the session waits.
#   tool_calls  counted here, one per PreToolUse, in the state file below.
#
# Over a limit it returns continue:false -- the session stops -- and a deny, so the
# call that tripped it does not run either (continue:false alone lets that one
# through). The first time, it also sends the coordinator an `escalation`. To
# carry on, a human raises the numbers in the limits file and tells the worker
# to continue: the file is read again on every call, and the escalation re-arms
# once the worker is back under its limits.
#
# State, per session, in ~/.claude/statusline-state/<session_id>.limit:
#   <calls> <dispatch id> <task id> <dispatched epoch> <escalated 0|1>
# The Dispatch is looked up once, on the first call, because worker-list and
# worker-show cost seconds (measured 2.5 s and 3 s). When orca or
# ORCA_TERMINAL_HANDLE is missing, or the lookup fails, the clock starts at the
# first call and no escalation is sent; the stop still happens.
#
# Contract as in the other guards: exit 0, and `set -e` is absent. Anything that
# cannot be evaluated (no jq, no limits file, unreadable payload) is no opinion.
# This is a guard against a worker that drifts, not a sandbox: it can edit its
# own limits file, and the spec line telling it not to is what holds it.
set -uo pipefail

# Hooks inherit Claude Code's environment, which on some hosts has not picked up
# the Nix profile yet. jq and git both live there.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

IFS=$'\t' read -r sid cwd < <(printf '%s' "$payload" | jq -r '[.session_id // "", .cwd // ""] | @tsv' 2>/dev/null)
case "$sid" in '' | */* | .*) exit 0 ;; esac
[ -n "${cwd:-}" ] || exit 0

name="$(git -C "$cwd" branch --show-current 2>/dev/null)"
[ -n "$name" ] || exit 0
limits="$HOME/.claude/worker-reports/$name.limits.json"
[ -r "$limits" ] || exit 0

IFS=$'\t' read -r max_usd max_min max_calls < <(
  jq -r 'def lim: if type == "number" and . > 0 then . else "-" end;
         [(.usd | lim), (.minutes | lim), (.tool_calls | lim)] | @tsv' "$limits" 2>/dev/null
)
[ -n "${max_calls:-}" ] || exit 0
# Not one usable number is no limit at all: nothing to count, nothing to look up.
[ "$max_usd$max_min$max_calls" != "---" ] || exit 0

dir="$HOME/.claude/statusline-state"
mkdir -p "$dir" 2>/dev/null || exit 0
state="$dir/$sid.limit"

# Parallel tool calls run their hooks side by side; without the lock they would
# lose counts and each send its own escalation.
if command -v flock >/dev/null 2>&1; then
  exec 9>"$state.lock" || exit 0
  flock -w 60 9 || exit 0
fi

# Orca puts its CLI on PATH inside its terminals; a remote one may only have it
# under ORCA_REMOTE_CLI_BIN_DIR.
if ! command -v orca >/dev/null 2>&1 && [ -x "${ORCA_REMOTE_CLI_BIN_DIR:-}/orca" ]; then
  PATH="$ORCA_REMOTE_CLI_BIN_DIR:$PATH"
fi
handle="${ORCA_TERMINAL_HANDLE:-}"
can_orca=0
[ -n "$handle" ] && command -v orca >/dev/null 2>&1 && can_orca=1

now="$(date +%s)"
calls=0 disp=- task=- start="$now" escalated=0

# The first call only: which Dispatch is this terminal, and since when.
lookup_dispatch() {
  [ "$can_orca" = 1 ] || return 0
  local row out at epoch
  out="$(timeout 15 orca orchestration worker-list --json 2>/dev/null)" || return 0
  row="$(printf '%s' "$out" | jq -r --arg h "$handle" '
    [.result.workers[]? | select(.agentTerminalHandle == $h)]
    | (map(select(.dispatchStatus == "dispatched"))[0] // .[0] // empty)
    | [.dispatchId, .taskId] | @tsv' 2>/dev/null)"
  [ -n "$row" ] || return 0
  IFS=$'\t' read -r disp task <<<"$row"
  out="$(timeout 15 orca orchestration worker-show --dispatch "$disp" --json 2>/dev/null)" || return 0
  at="$(printf '%s' "$out" | jq -r '.result.dispatch.dispatchedAt // empty' 2>/dev/null)"
  # Orca stamps UTC without saying so: "2026-10-04 00:14:29".
  case "$at" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ [0-9:]*) at="$at UTC" ;; esac
  epoch="$(date -d "$at" +%s 2>/dev/null)" || return 0
  [ "$epoch" -le "$now" ] && start="$epoch"
}

if [ -r "$state" ]; then
  read -r calls disp task start escalated <"$state" 2>/dev/null
  case "$calls$start$escalated" in *[!0-9]*) calls=0 start="$now" escalated=0 ;; esac
else
  lookup_dispatch
fi
calls=$((calls + 1))

usd=""
[ -r "$dir/$sid.cost" ] && read -r usd _ <"$dir/$sid.cost" 2>/dev/null

over="$(awk -v usd="$usd" -v max_usd="$max_usd" \
  -v mins="$(((now - start) * 10 / 60))" -v max_min="$max_min" \
  -v calls="$calls" -v max_calls="$max_calls" '
  function add(s) { o = o (o == "" ? "" : ", ") s }
  BEGIN {
    if (max_usd != "-" && usd ~ /^[0-9.eE+-]+$/ && usd + 0 >= max_usd + 0) add(sprintf("usd %.4g/%s", usd, max_usd))
    if (max_min != "-" && mins / 10 >= max_min + 0) add(sprintf("minutes %.1f/%s", mins / 10, max_min))
    if (max_calls != "-" && calls + 0 > max_calls + 0) add(sprintf("tool_calls %d/%s", calls, max_calls))
    print o
  }' 2>/dev/null)"

sent=0
if [ -z "$over" ]; then
  escalated=0
elif [ "$escalated" != 1 ] && [ "$can_orca" = 1 ] && [ "$disp" != - ] && [ "$task" != - ]; then
  timeout 15 orca orchestration send --from "$handle" --type escalation \
    --subject "limit $over" \
    --body "上限（$limits）を超えたので止めた: $over。続けるなら、人に見せて同意を得てから上限の値を上げ、ワーカーに続きを打つ。" \
    --task-id "$task" --dispatch-id "$disp" >/dev/null 2>&1 && escalated=1
fi
[ "$escalated" = 1 ] && sent=1

printf '%s %s %s %s %s\n' "$calls" "$disp" "$task" "$start" "$escalated" >"$state.$$" 2>/dev/null &&
  mv -f "$state.$$" "$state" 2>/dev/null

[ -n "$over" ] || exit 0

if [ "$sent" = 1 ]; then
  note="The escalation has been sent to the coordinator."
else
  note="No escalation could be sent from here; say so in one line."
fi
jq -nc --arg over "$over" --arg note "$note" '
  { continue: false,
    stopReason: ("limit " + $over),
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("limit " + $over + ": the worker-limit hook stopped this worker. Do not work around it. " + $note + " Wait for the coordinator.") } }'
exit 0
