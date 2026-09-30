#!/usr/bin/env bash
# Invariants of pstack-claude. Lives outside .apm/, so apm never deploys it.
#
#   1. What is copied from core-principal is still the same text: the
#      coordinator decision, core-tools, the two git guards, and the pins of
#      the published skills both packages depend on.
#   2. Each guard refuses what it exists to refuse and lets ordinary work
#      through -- the only behaviour this package adds to upstream.
#   3. japanese-guard is still upstream's script, and blocks an English
#      final answer but not a Japanese one.
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
  .apm/hooks/guard-default-branch.json .apm/skills/core-tools/SKILL.md \
  .apm/agents/completion-reviewer.agent.md; do
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

# A dependency whose `targets` is narrower than the package's is silently left
# out of the other agents' directories.
python3 - "$pkg/apm.yml" <<'PY' || fail "a dependency's targets differ from the package's"
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
bad = [d["alias"] for d in y["dependencies"]["apm"] if d.get("targets", y["targets"]) != y["targets"]]
for a in bad:
    print(f"  {a}", file=sys.stderr)
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
expect 0 "default-branch judged cd <child> by the session's cwd" bash_in guard-default-branch "$tmp/origin-repo" "cd $tmp/child && git push"
expect 0 "default-branch blocked deleting a remote branch" bash_in guard-default-branch "$tmp/origin-repo" "git push origin --delete feature"
expect 0 "default-branch fired on words inside a quoted argument" bash_in guard-default-branch "$tmp/origin-repo" 'orca x --spec "git push origin main"'
expect 2 "destructive-git did not block reset --hard" bash_in guard-destructive-git "$tmp/child" "git reset --hard"
expect 0 "destructive-git blocked reset --soft" bash_in guard-destructive-git "$tmp/child" "git reset --soft HEAD~1"

# dispatch-by-topic: UserPromptSubmit is read for its stdout (exit 2 would cancel
# the prompt), so check what it printed. The coordinator gets the rule; a child
# worktree and a payload with no cwd get nothing.
topic() {
  jq -nc --arg cwd "$1" '{hook_event_name:"UserPromptSubmit", prompt:"x", cwd:$cwd}' |
    env -u MAKURA_ALLOW_MAIN "$scripts/dispatch-by-topic.sh" 2>/dev/null
}
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("worker-start")' >/dev/null ||
  fail "dispatch-by-topic printed no routing rule in the coordinator workspace"
[ -z "$(topic "$tmp/child")" ] || fail "dispatch-by-topic printed in a child worktree"
[ -z "$(printf '{}' | "$scripts/dispatch-by-topic.sh" 2>/dev/null)" ] || fail "dispatch-by-topic printed for a payload with no cwd"
jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | endswith("/scripts/dispatch-by-topic.sh")' \
  "$pkg/.apm/hooks/dispatch-by-topic.json" >/dev/null || fail "dispatch-by-topic.json does not run the script on UserPromptSubmit"

# japanese-guard is vendored from minorun365/claude-code-japanese-guard at
# e68864a (docs/japanese-guard.md): script and test are upstream's bytes.
jg="$scripts/japanese-guard.py"
echo "42a77c34a47a88fcfa2106252c7007f479539eef786c6cab91c0330f0e915547  $jg" | sha256sum -c --quiet - ||
  fail "japanese-guard.py differs from upstream e68864a"
echo "caa1cea475429ee3169447792ab6d622766240c233fe54ee55c1996cb2c126d3  $here/japanese-guard/test_japanese_guard.py" |
  sha256sum -c --quiet - || fail "test_japanese_guard.py differs from upstream e68864a"
jq -e '.hooks.Stop[0].hooks[0].command | endswith("/scripts/japanese-guard.py")' \
  "$pkg/.apm/hooks/japanese-guard.json" >/dev/null || fail "japanese-guard.json does not run the script on Stop"
[ -x "$jg" ] || fail "japanese-guard.py is not executable"

stop() { printf '%s' "$1" | "$jg" 2>/dev/null; }
en='{"last_assistant_message":"I have updated the configuration and all the tests pass now."}'
[ "$(stop '{}')" = "" ] || fail "japanese-guard printed something for an empty input"
stop "$en" | jq -e '.decision == "block"' >/dev/null || fail "japanese-guard let an English final answer through"
[ "$(stop '{"last_assistant_message":"設定を更新し、テストがすべて通りました。"}')" = "" ] ||
  fail "japanese-guard blocked a Japanese final answer"
[ "$(stop "$(jq -c '.stop_hook_active = true' <<<"$en")")" = "" ] ||
  fail "japanese-guard blocked twice in one turn"

# Upstream's own tests, in upstream's layout: they find the hook at ../hooks/.
mkdir -p "$tmp/jg/hooks" "$tmp/jg/tests"
cp "$jg" "$tmp/jg/hooks/" && cp "$here/japanese-guard/test_japanese_guard.py" "$tmp/jg/tests/"
python3 "$tmp/jg/tests/test_japanese_guard.py" >/dev/null || fail "upstream test_japanese_guard.py failed"

[ "$failures" -eq 0 ] && echo "pstack-claude: ok"
exit "$failures"
