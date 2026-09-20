#!/usr/bin/env bash
# Tests for claude/statusline.sh, by feeding it the session JSON Claude Code
# sends on stdin and reading the two lines it prints.
#
# The case that matters is the one that broke: .rate_limits arrives null when
# ANTHROPIC_BASE_URL points at a local proxy, and the 5h/7d gauges have to come
# from ~/.claude.json instead. Both plan shapes are pinned here because the
# snapshot does not look the same on Pro and on Max.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../statusline.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Reset times relative to now, so the rendered countdowns are deterministic
# without freezing the clock.
in_5h="$(date -u -d '+4 hours 30 minutes' +%Y-%m-%dT%H:%M:%S.000000+00:00)"
in_7d="$(date -u -d '+6 days 2 hours' +%Y-%m-%dT%H:%M:%S.000000+00:00)"
past="$(date -u -d '-20 minutes' +%Y-%m-%dT%H:%M:%S.000000+00:00)"
now_ms="$(( $(date +%s) * 1000 ))"

# usage: run <config-file-or-empty> <stdin-json>  -> line 2, ANSI stripped
run() {
  local cfg=$1 payload=$2
  HOME="$tmp/home" CLAUDE_CONFIG_FILE="$cfg" bash "$script" <<<"$payload" |
    sed -e 's/\x1b\[[0-9;]*m//g' | tail -n 1
}

# usage: expect <name> <needle> <actual>
expect() {
  case "$3" in
    *"$2"*) ;;
    *) fail "$1: expected to find '$2' in: $3" ;;
  esac
}
refute() {
  case "$3" in
    *"$2"*) fail "$1: did not expect '$2' in: $3" ;;
  esac
}

mkdir -p "$tmp/home"

base_payload() {
  local rl=$1
  cat <<EOF
{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"$tmp"},
 "context_window":{"used_percentage":40},"session_id":"test",
 "rate_limits":$rl}
EOF
}

# --- 1. The payload wins when it actually carries the numbers ----------------
cat >"$tmp/decoy.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$now_ms,
 "utilization":{"limits":[{"group":"session","percent":99,"resets_at":"$in_5h"}]}}}
EOF
out=$(run "$tmp/decoy.json" "$(base_payload '{"five_hour":{"used_percentage":12,"resets_at":0},"seven_day":{"used_percentage":34,"resets_at":0}}')")
expect "live payload" "5h" "$out"
expect "live payload" "12%" "$out"
expect "live payload" "34%" "$out"
refute "live payload must not read the cache" "99%" "$out"
refute "live payload is not stale" "⧗" "$out"

# --- 2. Max shape: limits[] with a scoped weekly window ahead of weekly_all --
# The binding weekly limit here is weekly_scoped at 8%, not weekly_all at 7%.
cat >"$tmp/max.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$now_ms,"utilization":{
  "five_hour":{"utilization":29,"resets_at":"$in_5h"},
  "seven_day":{"utilization":7,"resets_at":"$in_7d"},
  "limits":[
    {"kind":"session","group":"session","percent":29,"resets_at":"$in_5h","is_active":true},
    {"kind":"weekly_all","group":"weekly","percent":7,"resets_at":"$in_7d","is_active":false},
    {"kind":"weekly_scoped","group":"weekly","percent":8,"resets_at":"$in_7d",
     "scope":{"model":{"display_name":"Fable"}},"is_active":false}]}}}
EOF
out=$(run "$tmp/max.json" "$(base_payload 'null')")
expect "max fallback 5h" "29%" "$out"
expect "max fallback 7d picks the binding window" "8%" "$out"
expect "max fallback marks the source" "⧗" "$out"
expect "max fallback 5h countdown" "↻4h" "$out"
expect "max fallback 7d countdown in days" "↻6d" "$out"

# --- 3. Pro shape: a session window and weekly_all, no scoped window ---------
cat >"$tmp/pro.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$now_ms,"utilization":{
  "five_hour":{"utilization":61,"resets_at":"$in_5h"},
  "seven_day":{"utilization":44,"resets_at":"$in_7d"},
  "limits":[
    {"kind":"session","group":"session","percent":61,"resets_at":"$in_5h","is_active":true},
    {"kind":"weekly_all","group":"weekly","percent":44,"resets_at":"$in_7d","is_active":false}]}}}
EOF
out=$(run "$tmp/pro.json" "$(base_payload 'null')")
expect "pro fallback 5h" "61%" "$out"
expect "pro fallback 7d" "44%" "$out"

# --- 4. Older shape: named objects only, no limits[] -------------------------
cat >"$tmp/legacy.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$now_ms,"utilization":{
  "five_hour":{"utilization":5,"resets_at":"$in_5h"},
  "seven_day":{"utilization":6,"resets_at":"$in_7d"}}}}
EOF
out=$(run "$tmp/legacy.json" "$(base_payload 'null')")
expect "legacy fallback 5h" "5%" "$out"
expect "legacy fallback 7d" "6%" "$out"

# --- 5. A cached window that has already reset is last-known, not current ----
cat >"$tmp/rolled.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$now_ms,"utilization":{
  "limits":[
    {"kind":"session","group":"session","percent":77,"resets_at":"$past"},
    {"kind":"weekly_all","group":"weekly","percent":3,"resets_at":"$in_7d"}]}}}
EOF
out=$(run "$tmp/rolled.json" "$(base_payload 'null')")
expect "rolled-over window is marked" "~77%" "$out"
refute "live weekly window is not marked" "~3%" "$out"

# --- 6. Nothing to read: say so, do not print a confident 0% ----------------
out=$(run "$tmp/does-not-exist.json" "$(base_payload 'null')")
expect "no source at all" "?%" "$out"
refute "no source must not claim 0%" " 0%" "$out"

out=$(run /dev/null "$(base_payload 'null')")
expect "unparseable config" "?%" "$out"

cat >"$tmp/empty.json" <<<'{}'
out=$(run "$tmp/empty.json" "$(base_payload 'null')")
expect "config without a usage snapshot" "?%" "$out"

# --- 7. No network, ever -----------------------------------------------------
# The whole point of the fallback is that the numbers come off local disk. A
# future edit reaching for the API would be a regression, so shadow every way
# out of the box with a stub that fails, and require the output to be unchanged.
mkdir -p "$tmp/bin"
for cmd in curl wget nc ssh claude python3 node; do
  printf '#!/bin/sh\necho "statusline made a network call via %s" >&2\nexit 97\n' "$cmd" \
    >"$tmp/bin/$cmd"
  chmod +x "$tmp/bin/$cmd"
done
out=$(PATH="$tmp/bin:$PATH" run "$tmp/max.json" "$(base_payload 'null')")
expect "works with no network tools available" "29%" "$out"
expect "works with no network tools available" "8%" "$out"

# And statically, because a stub only catches what the test happens to trigger.
# Comments are stripped first: the script explains in prose why it makes no
# network call, and naming the tools there should not trip this.
if grep -vE '^\s*#' "$script" | grep -nE '\b(curl|wget|nc|ssh|https?://)'; then
  fail "statusline.sh references a network tool or URL"
fi

if [ "$failures" != 0 ]; then
  printf '\n%s statusline test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "statusline tests ok"
