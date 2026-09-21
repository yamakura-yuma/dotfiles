#!/usr/bin/env bash
# Feeds hand-built PreToolUse payloads to the guard hooks and checks the exit
# code. 2 means blocked, 0 means "no opinion".
#
# This lives outside .apm/ on purpose: apm only deploys .apm/, so a consuming
# repo gets the hooks without the tests, while the tests stay next to the code
# they cover. Run it directly, or as part of `make ci`.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts="$here/../.apm/hooks/scripts"

failures=0

# Runs one case: expected exit code, hook script, and the command the agent
# supposedly asked for. cwd points at this repo so branch lookups have something
# real to read.
check() {
  local want="$1" script="$2" cmd="$3"
  local payload got
  payload="$(jq -nc --arg cmd "$cmd" --arg cwd "$here" \
    '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}')"
  printf '%s' "$payload" | "$scripts/$script" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$want" ]; then
    printf 'FAIL want=%s got=%s  %s\n' "$want" "$got" "$cmd" >&2
    failures=$((failures + 1))
  fi
}

command -v jq >/dev/null 2>&1 || { echo "tests need jq" >&2; exit 1; }

for f in "$scripts"/*.sh; do
  bash -n "$f" || failures=$((failures + 1))
done

# --- guard-destructive-git: blocked -----------------------------------------
g=guard-destructive-git.sh
check 2 $g 'git reset --hard'
check 2 $g 'git reset --hard HEAD~1'
check 2 $g 'git reset HEAD~1 --hard'
check 2 $g 'git -C /tmp/x reset --hard'
check 2 $g 'make build && git reset --hard'
check 2 $g 'git clean -f'
check 2 $g 'git clean -fd'
check 2 $g 'git clean -fdx'
check 2 $g 'git checkout -- .'
check 2 $g 'git checkout .'
check 2 $g 'git restore .'
check 2 $g 'git restore --staged --worktree .'
check 2 $g 'git push --force'
check 2 $g 'git push -f origin main'

# --- guard-destructive-git: allowed -----------------------------------------
# --force-with-lease is the recoverable spelling, so it has to keep working;
# it is the one case where a too-eager regex would bite every day.
check 0 $g 'git push --force-with-lease'
check 0 $g 'git push --force-with-lease=main:abc123'
check 0 $g 'git push origin HEAD --force-with-lease'
check 0 $g 'git reset --soft HEAD~1'
check 0 $g 'git reset HEAD~1'
check 0 $g 'git clean -nd'
check 0 $g 'git checkout main'
check 0 $g 'git checkout -b feature/x'
check 0 $g 'git restore src/main.go'
check 0 $g 'git checkout -- src/main.go'
check 0 $g 'git status'
check 0 $g 'echo "git reset --hard"'
check 0 $g 'git commit -m "undo the reset --hard"'

# --- guard-default-branch ----------------------------------------------------
# Branch-dependent cases are covered by the hook running for real; here we only
# pin the fail-open paths, which are the ones a refactor is likely to break.
b=guard-default-branch.sh
check 0 $b 'ls -la'
check 0 $b 'echo "git commit"'

# --- fixture: an coordinator checkout, a child worktree, and neither --------------
# The remaining hooks turn on *where the session is*, not on what it asked for,
# so they need real directories. `git init` plus `git worktree add` produces
# the two shapes the detection distinguishes: an original checkout whose .git
# is a directory, and a linked worktree whose .git is a file. A third directory
# belongs to no repository at all, which is the shape $HOME has.
fixture="$(mktemp -d)"
coordinator="$fixture/coordinator"
child="$fixture/child"
outside="$fixture/outside"
mkdir -p "$coordinator" "$outside"
git init -q "$coordinator" >/dev/null 2>&1
git -C "$coordinator" symbolic-ref HEAD refs/heads/main
git -C "$coordinator" -c user.email=t@example.invalid -c user.name=t \
  commit -q --allow-empty -m init
git -C "$coordinator" worktree add -q "$child" -b feature/x >/dev/null 2>&1

# Runs one Edit case: expected exit code, the directory the session is in, and
# the file it wants to write. Any remaining arguments are NAME=VALUE pairs put
# into the hook's environment, which is how MAKURA_ALLOW_MAIN gets tested --
# the hook reads its own environment, never the payload.
check_edit() {
  local want="$1" cwd="$2" file="$3"
  shift 3
  local payload got
  payload="$(jq -nc --arg f "$file" --arg cwd "$cwd" \
    '{tool_name:"Edit", tool_input:{file_path:$f}, cwd:$cwd}')"
  printf '%s' "$payload" | env "$@" "$scripts/guard-coordinator-edit.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" != "$want" ]; then
    printf 'FAIL want=%s got=%s  edit %s (cwd %s)\n' "$want" "$got" "$file" "$cwd" >&2
    failures=$((failures + 1))
  fi
}

# --- guard-coordinator-edit ------------------------------------------------------
check_edit 2 "$coordinator" "$coordinator/notes.md"          # default branch, original checkout
check_edit 0 "$child" "$child/notes.md"              # where dispatched work belongs
check_edit 2 "$outside" "$outside/notes.md"          # no repository at all, like $HOME
check_edit 0 "$coordinator" "$coordinator/notes.md" MAKURA_ALLOW_MAIN=1
check_edit 0 "$coordinator" "/tmp/claude-1000/session/scratchpad/plan.md"
check_edit 0 "$coordinator" "$HOME/.claude/plans/some-plan.md"
# The memory a coordinator session saves about what the human just told it.
# Which paths are exempt is harness-check.sh's business; this one case is here
# because it is the one the hook was actually losing.
check_edit 0 "$coordinator" "$HOME/.claude/projects/-home-u-repo/memory/lesson.md"
# A notebook names its target differently; the exemptions still have to apply.
printf '%s' "$(jq -nc --arg cwd "$coordinator" \
  '{tool_name:"NotebookEdit", tool_input:{notebook_path:"/x/y.ipynb"}, cwd:$cwd}')" |
  "$scripts/guard-coordinator-edit.sh" >/dev/null 2>&1
[ $? = 2 ] || { echo "FAIL guard-coordinator-edit should read notebook_path" >&2; failures=$((failures + 1)); }

# --- dispatch-in-coordinator -----------------------------------------------------
# UserPromptSubmit is read for its stdout, not its exit code -- exit 2 there
# cancels the human's prompt -- so these cases check what it printed.
emitted() {
  jq -nc --arg cwd "$1" '{hook_event_name:"UserPromptSubmit", prompt:"do a thing", cwd:$cwd}' |
    "$scripts/dispatch-in-coordinator.sh" 2>/dev/null
}
out="$(emitted "$coordinator")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1 ||
  { echo "FAIL dispatch-in-coordinator emitted no additionalContext in the coordinator workspace" >&2; failures=$((failures + 1)); }
printf '%s' "$out" | grep -q 'core-dispatch' ||
  { echo "FAIL dispatch-in-coordinator should point at the core-dispatch skill" >&2; failures=$((failures + 1)); }
[ -z "$(emitted "$child")" ] ||
  { echo "FAIL dispatch-in-coordinator should stay silent in a child worktree" >&2; failures=$((failures + 1)); }

git -C "$coordinator" worktree remove --force "$child" >/dev/null 2>&1
rm -rf "$fixture"

# --- fail-open ---------------------------------------------------------------
# A payload with no command, and one that is not JSON at all. Both must fall
# through rather than error: exit 1 would surface as a hook failure.
p=guard-coordinator-edit.sh
d=dispatch-in-coordinator.sh
for s in $g $b $p $d; do
  printf '%s' '{}' | "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore an empty payload" >&2; failures=$((failures + 1)); }
  printf '%s' 'not json' | "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore a non-JSON payload" >&2; failures=$((failures + 1)); }
done

# Without jq the hooks cannot read the payload, so they must have no opinion
# rather than guess. HOME has to move too, not just PATH: the hooks repair PATH
# by prepending $HOME/.nix-profile/bin, which is exactly where jq lives here --
# so pointing PATH at a jq-less directory alone would not simulate anything.
nohome="$(mktemp -d)"
for s in $g $b $p $d; do
  printf '%s' '{"tool_input":{"command":"git reset --hard"}}' |
    env -i HOME="$nohome" PATH=/usr/bin:/bin bash "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore a missing jq" >&2; failures=$((failures + 1)); }
done
rmdir "$nohome"

if [ "$failures" != 0 ]; then
  printf '\n%s guard test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "guard hooks OK"
