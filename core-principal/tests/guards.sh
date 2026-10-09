#!/usr/bin/env bash
# Feeds a hand-built UserPromptSubmit payload to the dispatch-in-coordinator
# hook and checks what it printed. The blocking guards (guard-coordinator-edit,
# guard-default-branch, guard-destructive-git) were removed on purpose; see
# README.md "Removed guards".
#
# This lives outside .apm/ on purpose: apm only deploys .apm/, so a consuming
# repo gets the hooks without the tests, while the tests stay next to the code
# they cover. Run it directly, or as part of `make ci`.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts="$here/../.apm/hooks/scripts"

failures=0

command -v jq >/dev/null 2>&1 || { echo "tests need jq" >&2; exit 1; }

for f in "$scripts"/*.sh; do
  bash -n "$f" || failures=$((failures + 1))
done

# --- fixture: a coordinator checkout, a child worktree ------------------------
# The hook turns on *where the session is*, not on what it asked for, so it
# needs real directories. `git init` plus `git worktree add` produces the two
# shapes the detection distinguishes: an original checkout whose .git is a
# directory, and a linked worktree whose .git is a file.
fixture="$(mktemp -d)"
coordinator="$fixture/coordinator"
child="$fixture/child"
mkdir -p "$coordinator"
git init -q "$coordinator" >/dev/null 2>&1
git -C "$coordinator" symbolic-ref HEAD refs/heads/main
git -C "$coordinator" -c user.email=t@example.invalid -c user.name=t \
  commit -q --allow-empty -m init
git -C "$coordinator" worktree add -q "$child" -b feature/x >/dev/null 2>&1

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
d=dispatch-in-coordinator.sh
for s in $d; do
  printf '%s' '{}' | "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore an empty payload" >&2; failures=$((failures + 1)); }
  printf '%s' 'not json' | "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore a non-JSON payload" >&2; failures=$((failures + 1)); }
done

# Without jq the hook cannot read the payload, so it must have no opinion
# rather than guess. HOME has to move too, not just PATH: the hook repairs PATH
# by prepending $HOME/.nix-profile/bin, which is exactly where jq lives here --
# so pointing PATH at a jq-less directory alone would not simulate anything.
# PATH holds only what the hook needs before it looks for jq (not /usr/bin:/bin,
# which has a jq on hosts that install one, e.g. the GitHub Actions runner).
nohome="$(mktemp -d)"
mkdir "$nohome/bin"
ln -s "$(command -v cat)" "$nohome/bin/cat"
for s in $d; do
  printf '%s' '{"tool_input":{"command":"git reset --hard"}}' |
    env -i HOME="$nohome" PATH="$nohome/bin" "$(command -v bash)" "$scripts/$s" >/dev/null 2>&1
  [ $? = 0 ] || { echo "FAIL $s should ignore a missing jq" >&2; failures=$((failures + 1)); }
done
rm -rf "$nohome"

if [ "$failures" != 0 ]; then
  printf '\n%s guard test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "guard hooks OK"
