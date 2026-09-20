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

# --- fail-open ---------------------------------------------------------------
# A payload with no command, and one that is not JSON at all. Both must fall
# through rather than error: exit 1 would surface as a hook failure.
for s in $g $b; do
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
for s in $g $b; do
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
