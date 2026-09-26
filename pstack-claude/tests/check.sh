#!/usr/bin/env bash
# Invariants of pstack-claude. Lives outside .apm/, so apm never deploys it.
#
#   1. The coordinator decision is the same code in both harnesses.
#   2. The guard refuses an edit in a coordinator workspace and allows one in
#      a child worktree -- the only behaviour this package adds to upstream.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

lib=.apm/hooks/scripts/lib/coordinator-workspace.sh
cmp -s "$pkg/$lib" "$repo/core-principal/$lib" ||
  fail "$lib differs from core-principal's copy"

guard="$pkg/.apm/hooks/scripts/guard-coordinator-edit.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b main origin-repo
git -C "$tmp/origin-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$tmp/origin-repo" worktree add -q -b feature "$tmp/child"

run() {
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/x"}}' "$1" "$1" |
    env -u MAKURA_ALLOW_MAIN "$guard" 2>/dev/null
}

run "$tmp/origin-repo"
[ $? -eq 2 ] || fail "guard did not block an edit on main of an original checkout"
run "$tmp/child"
[ $? -eq 0 ] || fail "guard blocked an edit in a child worktree"

[ "$failures" -eq 0 ] && echo "pstack-claude: ok"
exit "$failures"
