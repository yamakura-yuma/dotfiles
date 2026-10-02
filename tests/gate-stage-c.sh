#!/usr/bin/env bash
# Tests for bin/gate-stage-c.sh, the matcher behind the "stage C paths" job in
# .github/workflows/just-ci.yml.
#
# What matters: a path the CODEOWNERS file claims fails the job, a path it does
# not claim passes, and the gitignore-style rules GitHub documents for CODEOWNERS
# (anchoring, directory patterns, `*` not crossing `/`) hold. Offline: it needs
# only git.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../bin/gate-stage-c.sh"
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

cat >"$tmp/CODEOWNERS" <<'EOF'
# stage C
/.github/                @owner
/justfile                @owner @other
/clusters/kind/storage/  @owner
/just/*.Caddyfile        @owner
docs/gates.md            @owner
*.secret.yaml            @owner # trailing comment

/unowned/
!/negated.txt            @owner
EOF

# usage: check <name> <expected exit> <path>...
check() {
  local name="$1" want="$2" got
  shift 2
  printf '%s\0' "$@" | "$script" "$tmp/CODEOWNERS" >/dev/null 2>&1
  got=$?
  expect "$name" "$want" "$got"
}

check "path under a directory pattern" 1 .github/workflows/just-ci.yml
check "directory pattern, deep path" 1 clusters/kind/storage/a/b/pv.yaml
check "directory pattern is not a prefix" 0 clusters/kind/storage-extra/pv.yaml
check "file pattern anchored with /" 1 justfile
check "anchored pattern not matched in a subdirectory" 0 sub/justfile
check "glob matches within one directory" 1 just/share.Caddyfile
check "glob does not cross /" 0 just/sub/share.Caddyfile
check "unanchored glob matches at any depth" 1 a/b/token.secret.yaml
check "pattern with / is anchored to the root" 1 docs/gates.md
check "pattern with / not matched below the root" 0 sub/docs/gates.md
check "unrelated path" 0 README.md docs/other.md
check "one hit among many fails" 1 README.md docs/other.md clusters/kind/storage/pv.yaml
check "line with no owner is skipped" 0 unowned/x
check "negation line is skipped" 0 negated.txt
check "path with spaces" 1 "dir with space/token.secret.yaml"

# An empty diff is empty stdin (printf '%s\0' with no argument would emit one NUL).
: | "$script" "$tmp/CODEOWNERS" >/dev/null 2>&1
expect "no changed paths" 0 "$?"

# The failure message names the offending path and only that one.
msg="$(printf 'README.md\0justfile\0' | "$script" "$tmp/CODEOWNERS" 2>&1 >/dev/null)"
case "$msg" in *"  justfile"*) ;; *) fail "message lists the matched path: $msg" ;; esac
case "$msg" in *README.md*) fail "message lists an unmatched path: $msg" ;; esac

# A host-wide ignore file must not leak patterns into the match.
printf 'README.md\n' >"$tmp/global-ignore"
printf 'README.md\0' | GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile \
  GIT_CONFIG_VALUE_0="$tmp/global-ignore" "$script" "$tmp/CODEOWNERS" >/dev/null 2>&1
expect "global excludesFile is ignored" 0 "$?"

# Bad usage is exit 2, not a silent pass.
"$script" >/dev/null 2>&1
expect "no argument" 2 "$?"
"$script" "$tmp/missing" </dev/null >/dev/null 2>&1
expect "unreadable CODEOWNERS" 2 "$?"

# CODEOWNERS with no owned pattern claims nothing.
printf '# nothing here\n' >"$tmp/CODEOWNERS"
printf 'justfile\0' | "$script" "$tmp/CODEOWNERS" >/dev/null 2>&1
expect "CODEOWNERS with no patterns" 0 "$?"

if [ "$failures" -ne 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "gate-stage-c: ok"
