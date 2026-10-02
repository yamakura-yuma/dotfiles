#!/usr/bin/env bash
# Stage C check: fail when a changed path matches a pattern in CODEOWNERS.
#
# usage: gate-stage-c.sh <CODEOWNERS file> < NUL-separated changed paths
#
# CODEOWNERS is the one list of stage C paths (docs/gates.md); there is no second
# list to drift from it. The patterns are matched with git's own gitignore
# matcher -- GitHub documents CODEOWNERS as "gitignore-style" -- by writing them
# to a scratch repo's .git/info/exclude and asking `git check-ignore`.
#
# Where this differs from GitHub's CODEOWNERS (also in docs/gates.md):
#   - a line with a pattern but no owner is skipped (GitHub reads it as "no owner"
#     and un-owns the path; here it is never stage C);
#   - `!` negation is skipped (CODEOWNERS does not support it);
#   - `[...]` is a character class here (CODEOWNERS does not support it);
#   - matching is case-sensitive, as on GitHub.
#
# Exit: 0 no changed path matches, 1 at least one does (the paths are listed on
# stderr), 2 usage or tool error.
set -euo pipefail

if [ $# -ne 1 ] || [ ! -r "$1" ]; then
  echo "usage: ${0##*/} <CODEOWNERS file> < NUL-separated changed paths" >&2
  exit 2
fi

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
git init -q "$scratch"

# First field of every line that has an owner; blank and comment lines drop out.
awk 'NF >= 2 && $1 !~ /^#/ && $1 !~ /^!/ { print $1 }' "$1" >"$scratch/.git/info/exclude"

# core.excludesFile is pointed at /dev/null so the host's global ignore cannot
# add patterns; --no-index so the scratch repo's (empty) index is not consulted.
set +e
git -C "$scratch" -c core.excludesFile=/dev/null -c core.ignorecase=false \
  check-ignore --no-index -z --stdin >"$scratch/matched"
status=$?
set -e

case "$status" in
  0)
    echo "stage C: these changed paths match CODEOWNERS and need a human to merge:" >&2
    tr '\0' '\n' <"$scratch/matched" | sed 's/^/  /' >&2
    exit 1
    ;;
  1) exit 0 ;;
  *)
    echo "stage C: git check-ignore failed (exit $status)" >&2
    exit 2
    ;;
esac
