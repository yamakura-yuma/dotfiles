#!/usr/bin/env bash
# worker-limit hook, by feeding it PreToolUse payloads against a throwaway HOME,
# a throwaway git repo and a stub `orca`. Nothing real is read or sent.
#
# What has to hold: no limits file means no opinion (exit 0, no output, nothing
# written); each of money, minutes and tool calls stops the worker with
# continue:false and a deny; the escalation goes out once, however many calls
# follow; and the relay is asked about the Dispatch only on the first call.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
hook="$pkg/.apm/hooks/scripts/worker-limit.sh"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || { echo "skip: no jq, not checking worker-limit"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "skip: no git, not checking worker-limit"; exit 0; }

[ -x "$hook" ] || { fail "$hook is not executable"; exit 1; }
bash -n "$hook" || fail "worker-limit.sh does not parse"

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
repo="$tmp/repo"
mkdir -p "$home/.claude/worker-reports" "$tmp/bin"
git -C "$tmp" init -q -b main repo
git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$repo" checkout -q -b w1
mkdir "$tmp/plain" # a directory in no repository

# The relay answers as orca does: a handshake line on stderr, JSON on stdout.
# STUB_LIST_RC / STUB_SEND_RC make a call fail; STUB_DISPATCHED_AT is what
# worker-show reports.
cat >"$tmp/bin/orca" <<'STUB'
#!/bin/sh
echo "$*" >>"$ORCA_LOG"
echo "[relay-connect] Handshake OK" >&2
case "$2" in
  worker-list)
    [ "${STUB_LIST_RC:-0}" = 0 ] || exit "$STUB_LIST_RC"
    printf '%s\n' '{"ok":true,"result":{"workers":[
      {"dispatchId":"ctx_other","taskId":"task_other","dispatchStatus":"dispatched","agentTerminalHandle":"term_other"},
      {"dispatchId":"ctx_test","taskId":"task_test","dispatchStatus":"dispatched","agentTerminalHandle":"term_test"}]}}' ;;
  worker-show)
    printf '{"ok":true,"result":{"dispatch":{"dispatchedAt":"%s"}}}\n' "$STUB_DISPATCHED_AT" ;;
  send) exit "${STUB_SEND_RC:-0}" ;;
esac
STUB
chmod +x "$tmp/bin/orca"

# Orca stamps UTC without saying so. The hook has to read it as UTC whatever the
# host's zone is, so every run below is in Tokyo time.
utc_ago() { date -u -d "-$1" '+%Y-%m-%d %H:%M:%S'; }

n=0
sid=""
new_session() { n=$((n + 1)); sid="s$n"; : >"$tmp/orca.log"; }
limits() { printf '%s' "$1" >"$home/.claude/worker-reports/w1.limits.json"; }
cost() { mkdir -p "$home/.claude/statusline-state"; printf '%s\n' "$1" >"$home/.claude/statusline-state/$sid.cost"; }
count() { grep -c -- "$1" "$tmp/orca.log" || true; }

# usage: call [cwd] -> $out, $rc. One tool call of session $sid.
call() {
  out="$(jq -nc --arg sid "$sid" --arg cwd "${1:-$repo}" \
      '{session_id:$sid, cwd:$cwd, tool_name:"Bash", tool_input:{command:"true"}}' |
    env HOME="$home" TZ=Asia/Tokyo PATH="$tmp/bin:$PATH" ORCA_LOG="$tmp/orca.log" \
      ORCA_TERMINAL_HANDLE="${HANDLE-term_test}" \
      STUB_DISPATCHED_AT="${DISPATCHED_AT:-$(utc_ago '5 minutes')}" \
      STUB_LIST_RC="${LIST_RC:-0}" STUB_SEND_RC="${SEND_RC:-0}" \
      "$hook" 2>"$tmp/err")"
  rc=$?
}

expect_pass() {
  [ "$rc" = 0 ] || fail "$1: exit $rc, want 0"
  [ -z "$out" ] || fail "$1: expected no output, got: $out"
}
# Stopped: continue:false, a deny, and a stopReason that begins "limit <axis>".
expect_stop() {
  local what="$1" axis="$2"
  [ "$rc" = 0 ] || fail "$what: exit $rc, want 0 (the stop is in the JSON)"
  jq -e --arg a "$axis" '.continue == false
      and (.stopReason | startswith("limit " + $a))
      and .hookSpecificOutput.hookEventName == "PreToolUse"
      and .hookSpecificOutput.permissionDecision == "deny"
      and (.hookSpecificOutput.permissionDecisionReason | startswith("limit " + $a))' <<<"$out" >/dev/null 2>&1 ||
    fail "$what: not a continue:false + deny for '$axis': $out"
}

# --- 1. No limits file: no opinion ---------------------------------------------
new_session
cost "99 1000"
call
expect_pass "no limits file"
[ ! -e "$home/.claude/statusline-state/$sid.limit" ] || fail "no limits file: wrote a state file"
[ ! -s "$tmp/orca.log" ] || fail "no limits file: called orca"
limits '{"usd":1,"minutes":1,"tool_calls":1}'
call "$tmp/plain"
expect_pass "not in a repository"
git -C "$repo" checkout -q -b other
call
expect_pass "a branch with no limits file of its own"
git -C "$repo" checkout -q w1
limits 'not json'
call
expect_pass "a limits file that is not JSON"
limits '{"usd":"lots","minutes":0,"tool_calls":null}'
call
expect_pass "a limits file with no usable number"
[ ! -s "$tmp/orca.log" ] || fail "limits with no usable number: called orca"

# --- 2. Inside the limits: still nothing ------------------------------------------
new_session
limits '{"zone":"green","usd":10,"minutes":60,"tool_calls":5}'
cost "1.5 1000"
call
expect_pass "inside the limits"
[ "$(count worker-list)" = 1 ] || fail "inside the limits: expected one worker-list on the first call"
[ "$(count ' send ')" = 0 ] || fail "inside the limits: sent an escalation"

# --- 3. Money -----------------------------------------------------------------------
new_session
limits '{"usd":1,"minutes":60,"tool_calls":100}'
cost "0.2 1000"
call
expect_pass "usd: under"
cost "2.5 90000"
call
expect_stop "usd: over" "usd"
[ "$(count ' send ')" = 1 ] || fail "usd: expected one escalation, got $(count ' send ')"
grep -q -- '--type escalation' "$tmp/orca.log" || fail "usd: not an escalation"
grep -q -- '--from term_test' "$tmp/orca.log" || fail "usd: not sent from the worker's own terminal"
grep -q -- '--task-id task_test --dispatch-id ctx_test' "$tmp/orca.log" || fail "usd: wrong task or dispatch (the stub has two workers)"
grep -q -- '--subject limit usd' "$tmp/orca.log" || fail "usd: escalation subject does not say limit usd"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("escalation has been sent")' <<<"$out" >/dev/null ||
  fail "usd: the worker is not told the escalation went out"
call
expect_stop "usd: still over" "usd"
call
expect_stop "usd: still over, third call" "usd"
[ "$(count ' send ')" = 1 ] || fail "usd: escalated more than once ($(count ' send ') sends)"
[ "$(count worker-list)" = 1 ] || fail "usd: asked the relay for the worker list $(count worker-list) times"
[ "$(count worker-show)" = 1 ] || fail "usd: asked the relay to show the worker $(count worker-show) times"

# Spent exactly the limit is spent: it stops there, not one call later.
new_session
limits '{"usd":1}'
cost "1 1000"
call
expect_stop "usd: exactly at the limit" "usd"
new_session
cost "0.9999 1000"
call
expect_pass "usd: just below the limit"

# --- 4. Wall-clock time (Dispatch time is UTC, the host is not) ---------------------
new_session
limits '{"minutes":30}'
DISPATCHED_AT="$(utc_ago '10 minutes')" call
expect_pass "minutes: dispatched 10 minutes ago, limit 30 (read as local time it would be 9 h)"
new_session
DISPATCHED_AT="$(utc_ago '2 hours')" call
expect_stop "minutes: dispatched 2 hours ago, limit 30" "minutes"
[ "$(count ' send ')" = 1 ] || fail "minutes: expected one escalation"
new_session
DISPATCHED_AT="not a time" call
expect_pass "minutes: an unreadable dispatchedAt starts the clock at the first call"
new_session
DISPATCHED_AT="$(date -u -d '+3 hours' '+%Y-%m-%d %H:%M:%S')" call
expect_pass "minutes: a dispatchedAt in the future starts the clock at the first call"

# --- 5. Tool calls -------------------------------------------------------------------
new_session
limits '{"tool_calls":2}'
call
expect_pass "tool_calls: first"
call
expect_pass "tool_calls: second, at the limit"
call
expect_stop "tool_calls: third, over" "tool_calls"
call
expect_stop "tool_calls: fourth" "tool_calls"
[ "$(count ' send ')" = 1 ] || fail "tool_calls: expected one escalation, got $(count ' send ')"
# Another session in the same worktree counts from zero.
sid="s-other"
call
expect_pass "tool_calls: a new session starts counting again"

# --- 6. More than one axis over, and back under ---------------------------------------
new_session
limits '{"usd":1,"tool_calls":1}'
cost "0.1 1000"
call
expect_pass "two axes: first call is inside both"
cost "3 1000"
call
jq -e '.stopReason | test("^limit usd .*, tool_calls ")' <<<"$out" >/dev/null || fail "two axes: stopReason does not name both: $out"
[ "$(count ' send ')" = 1 ] || fail "two axes: one escalation for the call, not one per axis"
# A human raises the numbers; the very next call goes through.
limits '{"usd":100,"tool_calls":100}'
call
expect_pass "raised limits: the worker carries on"
# Going over again is a new event.
limits '{"usd":1,"tool_calls":100}'
call
expect_stop "over again after a raise" "usd"
[ "$(count ' send ')" = 2 ] || fail "over again: expected a second escalation, got $(count ' send ')"

# --- 7. Without Orca: stop, send nothing ------------------------------------------------
new_session
limits '{"tool_calls":1}'
HANDLE='' call
expect_pass "no handle: first call is within the limit"
HANDLE='' call
expect_stop "no ORCA_TERMINAL_HANDLE" "tool_calls"
[ ! -s "$tmp/orca.log" ] || fail "no ORCA_TERMINAL_HANDLE: called orca"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("No escalation could be sent")' <<<"$out" >/dev/null ||
  fail "no ORCA_TERMINAL_HANDLE: the worker is told an escalation went out"

# orca not on PATH at all: a PATH holding only what the hook needs.
mkdir "$tmp/tools"
for t in bash env cat jq git mkdir mv awk date timeout flock; do
  p="$(command -v "$t")" && ln -s "$p" "$tmp/tools/$t"
done
new_session
out="$(for i in 1 2; do
  jq -nc --arg sid "$sid" --arg cwd "$repo" '{session_id:$sid, cwd:$cwd}' |
    env -i HOME="$home" PATH="$tmp/tools" ORCA_TERMINAL_HANDLE=term_test "$hook" 2>/dev/null
done)"
jq -e '.continue == false and (.stopReason | startswith("limit tool_calls"))' <<<"$out" >/dev/null ||
  fail "no orca on PATH: did not stop: $out"

# --- 8. The relay is unreliable -----------------------------------------------------------
new_session
limits '{"tool_calls":1}'
LIST_RC=1 call
expect_pass "relay down: first call"
LIST_RC=1 call
expect_stop "relay down: second call" "tool_calls"
[ "$(count ' send ')" = 0 ] || fail "relay down: sent an escalation with no Dispatch to name"
[ "$(count worker-list)" = 1 ] || fail "relay down: asked the relay again after it failed once"

# A send that fails is not recorded as sent, so the next call tries again, once it works.
new_session
SEND_RC=1 call
SEND_RC=1 call
expect_stop "send fails" "tool_calls"
jq -e '.hookSpecificOutput.permissionDecisionReason | contains("No escalation could be sent")' <<<"$out" >/dev/null ||
  fail "send fails: the worker is told an escalation went out"
call
expect_stop "send works again" "tool_calls"
call
[ "$(count ' send ')" = 2 ] || fail "send retried: expected 2 sends (one failed, one worked), got $(count ' send ')"

# --- 9. Parallel tool calls ---------------------------------------------------------------
new_session
limits '{"tool_calls":1000}'
for i in $(seq 1 12); do
  ( jq -nc --arg sid "$sid" --arg cwd "$repo" '{session_id:$sid, cwd:$cwd}' |
      env HOME="$home" PATH="$tmp/bin:$PATH" ORCA_LOG="$tmp/orca.log" ORCA_TERMINAL_HANDLE=term_test \
        STUB_DISPATCHED_AT="$(utc_ago '1 minute')" "$hook" >/dev/null 2>&1 ) &
done
wait
read -r calls _ <"$home/.claude/statusline-state/$sid.limit"
[ "$calls" = 12 ] || fail "parallel: 12 calls counted as $calls"
[ "$(count worker-list)" = 1 ] || fail "parallel: asked the relay $(count worker-list) times, not once"

# --- 10. Registration ------------------------------------------------------------------------
reg="$pkg/.apm/hooks/worker-limit.json"
jq -e '.hooks.PreToolUse | length == 1 and (.[0] | has("matcher") | not)' "$reg" >/dev/null ||
  fail "worker-limit.json: must be one PreToolUse entry with no matcher"
jq -e '.hooks.PreToolUse[0].hooks[0] | (.command | endswith("/scripts/worker-limit.sh")) and .timeout > 45' "$reg" >/dev/null ||
  fail "worker-limit.json: must run scripts/worker-limit.sh with a timeout past the relay's 3 x 15 s"

# No state file or stray temp file is left behind by a normal call.
[ -z "$(find "$home/.claude/statusline-state" -name '*.limit.[0-9]*')" ] || fail "a temp state file was left behind"

if [ "$failures" != 0 ]; then
  printf '\n%s worker-limit test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "worker-limit ok"
