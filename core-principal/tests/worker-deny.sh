#!/usr/bin/env bash
# ワーカーの worktree に入る deny の正本（lib/worker-deny.settings.json）と、それを
# .claude/settings.local.json へ運ぶ orca.yaml の setup を確かめる。
#
# apm は hook ファイルに書いた permissions を捨てる。だから正本は apm に plain
# file として運ばせ、setup が複写する。ここが崩れると、ワーカーは deny なしで
# bypass 起動したまま誰にも気づかれない。
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"
src="$pkg/.apm/hooks/scripts/lib/worker-deny.settings.json"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || { echo "skip: no jq, not checking worker deny"; exit 0; }

[ -f "$src" ] || { fail "missing $src"; exit 1; }

# 正本は 1 か所だけ。
n="$(find "$repo" -name 'worker-deny*.json' -not -path '*/apm_modules/*' -not -path '*/.claude/*' -not -path '*/.git/*' | wc -l)"
[ "$n" = 1 ] || fail "worker-deny*.json は 1 か所だけのはず（$n 件）"

# permissions.deny だけを持つ（allow は bypass では意味がなく、書くと効いて見える）。
[ "$(jq -c 'keys' "$src")" = '["permissions"]' ] || fail "トップレベルは permissions だけ"
[ "$(jq -c '.permissions | keys' "$src")" = '["deny"]' ] || fail "permissions は deny だけ"

# 秘密の読み取りと人の環境の編集を含む。
for rule in 'Read(~/.ssh/**)' 'Read(~/.claude/.credentials.json)' \
  'Edit(~/.bashrc)' 'Edit(~/.claude/settings.json)'; do
  jq -e --arg r "$rule" '.permissions.deny | index($r)' "$src" >/dev/null || fail "deny に $rule が無い"
done

# ワーカーの仕事を止めない: Bash の規則は書かず、worktree と worker-reports への書き込みを塞がない。
jq -e '.permissions.deny | map(select(startswith("Bash("))) | length == 0' "$src" >/dev/null \
  || fail "deny に Bash(...) がある（git push / gh pr create を止めうる）"
jq -e '.permissions.deny | map(select(test("worker-reports|^Write|^Edit\\(\\*\\*"))) | length == 0' "$src" >/dev/null \
  || fail "deny が worker-reports や worktree 内の編集を塞ぐ"

# orca.yaml の setup が apm の運んだ正本を settings.local.json に複写する。
grep -q 'cp \.claude/hooks/core-principal/\.apm/hooks/scripts/lib/worker-deny\.settings\.json \.claude/settings\.local\.json' "$repo/orca.yaml" \
  || fail "orca.yaml の setup が正本を .claude/settings.local.json に複写していない"

[ "$failures" = 0 ] && echo "worker deny ok"
exit "$failures"
