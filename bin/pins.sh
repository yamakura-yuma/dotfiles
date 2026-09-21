#!/usr/bin/env bash
# Keeps the upstream pins honest.
#
# core-principal/apm.yml pins every dependency to a commit, and versions.env
# pins the three globally installed tools. Pinning is the easy half: the hard
# half is noticing, six months later, that nothing has moved. `apm update` does
# not touch an explicit ref, so nothing ever tells you a pin went stale.
#
# pins.tsv is the answer: a committed snapshot of each pin's commit date, so
# `check` can report staleness without going near the network. Only `refresh`
# and `latest` need network, and neither is wired into `make ci` -- ci stays
# offline and must not change the machine it runs on.
#
#   ./bin/pins.sh check     offline; apm.yml <-> pins.tsv parity, then age
#   ./bin/pins.sh refresh   network; rewrite pins.tsv from the commit dates
#   ./bin/pins.sh latest    network; what is available upstream right now
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
manifest="$root/core-principal/apm.yml"
snapshot="$root/pins.tsv"
versions="$root/versions.env"

# Warn above this age. Not a failure: a pin being old is a judgement call, and
# ci refusing to pass over it would only teach us to raise the number.
max_age_days="${PIN_MAX_AGE_DAYS:-90}"

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# apm.yml -> "repo<TAB>ref<TAB>alias", one line per dependency, in file order.
# repo is the github "owner/name", or "gist:<owner>/<id>" for the two gists.
parse_manifest() {
  awk '
    /^[[:space:]]*- git:[[:space:]]*/ {
      url = $3
      sub(/\.git$/, "", url)
      if (url ~ /gist\.github\.com/) {
        sub(/^https?:\/\/gist\.github\.com\//, "gist:", url)
      } else {
        sub(/^https?:\/\/github\.com\//, "", url)
      }
      repo = url; ref = ""; next
    }
    /^[[:space:]]*ref:[[:space:]]*/ { ref = $2; next }
    /^[[:space:]]*alias:[[:space:]]*/ {
      if (repo != "" && ref != "") printf "%s\t%s\t%s\n", repo, ref, $2
      next
    }
  ' "$manifest"
}

# pins.tsv -> same shape, comments and blank lines dropped.
parse_snapshot() {
  grep -v '^[[:space:]]*#' "$snapshot" | grep -v '^[[:space:]]*$' \
    | awk -F'\t' '{ printf "%s\t%s\t%s\n", $1, $2, $4 }'
}

cmd_check() {
  [ -r "$manifest" ] || { fail "no $manifest"; return; }
  [ -r "$snapshot" ] || { fail "no $snapshot -- run ./bin/pins.sh refresh"; return; }
  [ -r "$versions" ] || { fail "no $versions"; return; }

  # 1. every pinned tool version is set and looks like a version
  # shellcheck source=../versions.env
  . "$versions"
  local name value
  for name in GRAPHIFYY_VERSION HEADROOM_VERSION CODEGRAPH_VERSION; do
    value="${!name:-}"
    case "$value" in
      '') fail "$name is empty in versions.env" ;;
      *[!0-9.]*) fail "$name is not a plain version: $value" ;;
    esac
  done

  # 2. apm.yml and pins.tsv describe the same pins. A ref bumped by hand
  #    without refreshing the snapshot would otherwise age invisibly.
  local diff_out
  diff_out="$(diff <(parse_manifest | sort) <(parse_snapshot | sort) 2>&1)"
  if [ -n "$diff_out" ]; then
    fail "pins.tsv does not match core-principal/apm.yml -- run ./bin/pins.sh refresh"
    printf '%s\n' "$diff_out" | sed 's/^/    /' >&2
  fi

  # 3. age, reported only
  local now stale total
  now="$(date +%s)"
  stale=0
  total=0
  while IFS=$'\t' read -r repo ref date alias; do
    [ -n "${repo:-}" ] || continue
    case "$repo" in '#'*) continue ;; esac
    total=$((total + 1))
    local then_s age
    then_s="$(date -d "$date" +%s 2>/dev/null)" || {
      fail "unreadable date for $alias: $date"
      continue
    }
    age=$(((now - then_s) / 86400))
    if [ "$age" -gt "$max_age_days" ]; then
      printf 'stale: %-28s %s  %s days  %.7s\n' "$alias" "$date" "$age" "$ref"
      stale=$((stale + 1))
    fi
  done < <(grep -v '^[[:space:]]*$' "$snapshot")

  if [ "$stale" != 0 ]; then
    printf '%s of %s pins are older than %s days (warning only)\n' \
      "$stale" "$total" "$max_age_days"
  fi
}

# Commit date of one pinned ref. Gists need a different endpoint and only
# expose dates through their commit list.
commit_date() {
  local repo="$1" ref="$2"
  case "$repo" in
    gist:*)
      local id="${repo##*/}"
      gh api "gists/$id/commits" --jq \
        ".[] | select(.version == \"$ref\") | .committed_at" 2>/dev/null | head -1
      ;;
    *)
      gh api "repos/$repo/commits/$ref" --jq '.commit.committer.date' 2>/dev/null
      ;;
  esac
}

cmd_refresh() {
  command -v gh >/dev/null 2>&1 || { fail "refresh needs gh"; return; }
  local tmp
  tmp="$(mktemp)"
  {
    printf '# Commit dates of the pins in core-principal/apm.yml, so that\n'
    printf '# `./bin/pins.sh check` can report staleness offline.\n'
    printf '# Regenerate with `./bin/pins.sh refresh` after bumping any ref.\n'
    printf '#\n'
    printf '# repo\tref\tdate\talias\n'
  } >"$tmp"

  local repo ref alias date
  while IFS=$'\t' read -r repo ref alias; do
    date="$(commit_date "$repo" "$ref")"
    if [ -z "$date" ]; then
      fail "no commit date for $alias ($repo $ref)"
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$repo" "$ref" "${date%%T*}" "$alias" >>"$tmp"
  done < <(parse_manifest)

  if [ "$failures" = 0 ]; then
    mv "$tmp" "$snapshot"
    printf 'wrote %s\n' "$snapshot"
  else
    rm -f "$tmp"
  fi
}

cmd_latest() {
  command -v gh >/dev/null 2>&1 || { fail "latest needs gh"; return; }
  # shellcheck source=../versions.env
  . "$versions"

  printf '== tools (versions.env) ==\n'
  local pypi
  for pypi in graphifyy:"$GRAPHIFYY_VERSION" headroom-ai:"$HEADROOM_VERSION"; do
    local pkg="${pypi%%:*}" have="${pypi##*:}" newest
    newest="$(curl -fsSL "https://pypi.org/pypi/$pkg/json" | jq -r '.info.version')"
    printf '%-26s pinned %-10s latest %s\n' "$pkg" "$have" "${newest:-?}"
  done
  local npm_newest
  npm_newest="$(curl -fsSL 'https://registry.npmjs.org/@colbymchenry/codegraph/latest' \
    | jq -r '.version')"
  printf '%-26s pinned %-10s latest %s\n' \
    '@colbymchenry/codegraph' "$CODEGRAPH_VERSION" "${npm_newest:-?}"

  printf '\n== pins (core-principal/apm.yml) ==\n'
  local repo ref alias head
  while IFS=$'\t' read -r repo ref alias; do
    case "$repo" in
      gist:*) head="$(gh api "gists/${repo##*/}/commits" --jq '.[0].version' 2>/dev/null)" ;;
      *) head="$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].sha' 2>/dev/null)" ;;
    esac
    if [ "$head" = "$ref" ]; then
      printf '%-28s up to date\n' "$alias"
    else
      printf '%-28s %.7s -> %.7s\n' "$alias" "$ref" "${head:-???????}"
    fi
  done < <(parse_manifest)
}

case "${1:-check}" in
  check) cmd_check ;;
  refresh) cmd_refresh ;;
  latest) cmd_latest ;;
  *)
    echo "usage: $0 [check|refresh|latest]" >&2
    exit 2
    ;;
esac

if [ "$failures" != 0 ]; then
  printf '%s pin check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'pins ok\n'
