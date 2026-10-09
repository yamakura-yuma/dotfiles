#!/usr/bin/env bash
# 話題チャットの allow の正本（lib/topic-chat.settings.json）と autoMode の正本
# （claude/auto-mode.json）の形を確かめる。広すぎる allow が混ざると、auto に入るときに
# 外されるか、外されずに分類器を素通りするかのどちらかになる。
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
src="$repo/pstack-claude/.apm/hooks/scripts/lib/topic-chat.settings.json"
auto="$repo/claude/auto-mode.json"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || { echo "skip: no jq, not checking topic chat allow"; exit 0; }

[ -f "$src" ] || { fail "missing $src"; exit 1; }
[ -f "$auto" ] || { fail "missing $auto"; exit 1; }

[ "$(jq -c '.permissions | keys' "$src")" = '["allow"]' ] || fail "permissions は allow だけ（deny は worker-deny が持つ）"
for rule in 'Bash(orca orchestration:*)' 'Bash(.claude/skills/pstack-on-claude-code/scripts/*)'; do
  jq -e --arg r "$rule" '.permissions.allow | index($r)' "$src" >/dev/null || fail "allow に $rule が無い"
done
# auto に入るときに外される広い規則や、何でも通す規則を入れない。
jq -e '.permissions.allow | map(select(. == "Bash" or . == "Bash(*)" or test("^Bash\\((bash|sh|python|node)[ :*]") or startswith("Agent") or startswith("Monitor"))) | length == 0' "$src" >/dev/null \
  || fail "allow に広すぎる規則がある（Bash(*)・インタプリタ・Agent・Monitor）"

# autoMode.allow は既定を残す。
[ "$(jq -r '.autoMode.allow[0]' "$auto")" = '$defaults' ] || fail 'autoMode.allow の先頭は "$defaults"'
[ "$(jq -c '.autoMode | keys' "$auto")" = '["allow"]' ] || fail "autoMode は allow だけ（soft_deny は触らない）"

[ "$failures" = 0 ] && echo "topic chat allow ok"
exit "$failures"
