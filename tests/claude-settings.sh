#!/usr/bin/env bash
# Tests for `setup.sh claude-settings`, which merges claude/telemetry-env.json
# into the `env` of ~/.claude/settings.json. They run against a throwaway HOME,
# so the real settings.json is never touched.
#
# The case that matters is the merge overwriting a value the file already has:
# the merge only adds keys, so a stale "false" survives unless the repo's own
# value says "true" outright.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# usage: expect <name> <expected> <actual>
expect() {
  [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

# usage: merge <settings-json|""> -> sets $settings to the resulting file
# An empty argument starts from no settings.json at all.
merge() {
  rm -rf "$tmp/home"
  mkdir -p "$tmp/home/.claude"
  [ -z "$1" ] || printf '%s' "$1" >"$tmp/home/.claude/settings.json"
  HOME="$tmp/home" bash "$script" claude-settings >/dev/null 2>&1 || fail "claude-settings exited non-zero"
  settings="$tmp/home/.claude/settings.json"
}

sid='.env.OTEL_METRICS_INCLUDE_SESSION_ID'

merge '{"env":{"OTEL_METRICS_INCLUDE_SESSION_ID":"false","KEEP":"x"},"model":"opus"}'
expect "stale false: overwritten with true" "true" "$(jq -r "$sid" "$settings")"
expect "stale false: other env keys kept" "x" "$(jq -r '.env.KEEP' "$settings")"
expect "stale false: other top-level keys kept" "opus" "$(jq -r '.model' "$settings")"

merge ""
expect "no settings.json: created with true" "true" "$(jq -r "$sid" "$settings")"

merge '{}'
expect "empty settings: env added" "true" "$(jq -r "$sid" "$settings")"

if [ "$failures" != 0 ]; then
  printf '\n%s claude-settings test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "claude-settings tests ok"
