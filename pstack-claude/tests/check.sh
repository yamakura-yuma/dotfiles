#!/usr/bin/env bash
# Invariants of pstack-claude. Lives outside .apm/, so apm never deploys it.
#
#   1. What is copied from core-principal is still the same text: the
#      coordinator decision, core-tools, the two git guards, and the pins of
#      the published skills both packages depend on.
#   2. Each guard refuses what it exists to refuse and lets ordinary work
#      through -- the only behaviour this package adds to upstream.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Byte-for-byte copies.
for f in .apm/hooks/scripts/lib/coordinator-workspace.sh \
  .apm/hooks/scripts/guard-destructive-git.sh .apm/hooks/guard-destructive-git.json \
  .apm/hooks/guard-default-branch.json .apm/skills/core-tools/SKILL.md; do
  cmp -s "$pkg/$f" "$repo/core-principal/$f" || fail "$f differs from core-principal's copy"
done
# Copied with one word changed: the skill its refusal points at.
f=.apm/hooks/scripts/guard-default-branch.sh
sed 's/core-dispatch/orchestration/' "$repo/core-principal/$f" | cmp -s - "$pkg/$f" ||
  fail "$f differs from core-principal's copy beyond core-dispatch -> orchestration"

# Every dependency both packages declare is pinned to the same place.
python3 - "$pkg/apm.yml" "$repo/core-principal/apm.yml" <<'PY' || fail "a shared dependency drifted from core-principal/apm.yml"
import sys, yaml
ours, theirs = ({d["alias"]: (d["git"], d.get("path"), d["ref"])
                 for d in yaml.safe_load(open(p))["dependencies"]["apm"]} for p in sys.argv[1:])
bad = [a for a in ours.keys() & theirs.keys() if ours[a] != theirs[a]]
for a in bad:
    print(f"  {a}: {ours[a]} != {theirs[a]}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

scripts="$pkg/.apm/hooks/scripts"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b main origin-repo
git -C "$tmp/origin-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$tmp/origin-repo" worktree add -q -b feature "$tmp/child"

edit() {
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/x"}}' "$1" "$1" |
    env -u MAKURA_ALLOW_MAIN "$scripts/guard-coordinator-edit.sh" 2>/dev/null
}
bash_in() {
  jq -nc --arg cwd "$2" --arg cmd "$3" '{cwd:$cwd,tool_input:{command:$cmd}}' |
    env -u MAKURA_ALLOW_MAIN "$scripts/$1.sh" 2>/dev/null
}
expect() {
  local want="$1" what="$2"; shift 2
  "$@"; [ $? -eq "$want" ] || fail "$what"
}

expect 2 "coordinator-edit did not block an edit on main of an original checkout" edit "$tmp/origin-repo"
expect 0 "coordinator-edit blocked an edit in a child worktree" edit "$tmp/child"
expect 2 "default-branch did not block a commit on main" bash_in guard-default-branch "$tmp/origin-repo" "git commit -m x"
expect 0 "default-branch blocked a commit on a feature branch" bash_in guard-default-branch "$tmp/child" "git commit -m x"
expect 2 "destructive-git did not block reset --hard" bash_in guard-destructive-git "$tmp/child" "git reset --hard"
expect 0 "destructive-git blocked reset --soft" bash_in guard-destructive-git "$tmp/child" "git reset --soft HEAD~1"

[ "$failures" -eq 0 ] && echo "pstack-claude: ok"
exit "$failures"
