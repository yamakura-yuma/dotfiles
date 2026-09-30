#!/usr/bin/env bash
# Keeps the settings of the GitHub repositories under yamakura-yuma aligned, and
# sweeps the merged branches that pile up when nothing deletes them.
#
# Both halves are a dry-run unless --apply is given, and `make ci` never calls
# this script: it talks to GitHub, and the --apply paths change it.
#
#   ./bin/github-settings.sh settings [--apply] [repo...]
#       compare each repo with `declared` below; exit 1 if any differs
#   ./bin/github-settings.sh branches [--apply] [repo...]
#       list (or, with --apply, delete) branches whose pull request is merged
#
# Why a script and not OpenTofu: five repos and one setting. A declaration plus
# a comparison is all the tool there is to maintain, it reuses the `gh` login
# this host already has, and nothing else holds state. If the list of settings
# outgrows this, that is the moment to move to a real provider.

set -uo pipefail

# --- declaration -------------------------------------------------------------
# To manage another repo, add a line to `repos`. To manage another setting, add
# a `key=value` to `declared`: the key is a field of `gh api repos/{owner}/{repo}`
# that PATCH accepts, and the value is true or false.
owner=yamakura-yuma
repos=(
  dotfiles
  coordinator
  knowledge-base
  temporal-workflow-kit
  home-k8s
)
declared=(
  delete_branch_on_merge=true
)
# -----------------------------------------------------------------------------

# `gh pr list` returns at most this many; a repo that reaches it is reported,
# because the PRs past the limit are then invisible and their branches are kept.
pr_limit=1000

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

usage() {
  echo "usage: $0 {settings|branches} [--apply] [repo...]" >&2
  exit 2
}

is_declared_repo() {
  local r
  for r in "${repos[@]}"; do [ "$r" = "$1" ] && return 0; done
  return 1
}

# settings: declared value vs. the repo's current one.
cmd_settings() {
  local repo json pair key want have drift=0 differing=0 patch_args
  for repo in "${targets[@]}"; do
    if ! json="$(gh api "repos/$owner/$repo")"; then
      fail "cannot read $owner/$repo"
      continue
    fi
    patch_args=()
    for pair in "${declared[@]}"; do
      key="${pair%%=*}"
      want="${pair#*=}"
      # A token without admin on the repo gets no such field at all; calling
      # that "false" would report a drift that --apply then cannot fix.
      have="$(jq -r --arg k "$key" '.[$k] | if . == null then "?" else tostring end' <<<"$json")"
      if [ "$have" = "?" ]; then
        fail "$owner/$repo: $key is not readable (needs admin on the repo)"
      elif [ "$have" != "$want" ]; then
        printf '%s/%s: %s  %s -> %s\n' "$owner" "$repo" "$key" "$have" "$want"
        patch_args+=(-F "$pair")
        drift=1
      fi
    done
    [ "${#patch_args[@]}" -gt 0 ] || continue
    differing=$((differing + 1))
    if [ "$apply" = 1 ]; then
      if gh api -X PATCH "repos/$owner/$repo" "${patch_args[@]}" >/dev/null; then
        printf '%s/%s: applied\n' "$owner" "$repo"
      else
        fail "PATCH $owner/$repo"
      fi
    fi
  done

  printf '%s of %s repos differ\n' "$differing" "${#targets[@]}"
  [ "$failures" = 0 ] || return 3
  if [ "$apply" != 1 ] && [ "$drift" = 1 ]; then
    echo "dry-run: nothing written. Re-run with --apply."
    return 1
  fi
  return 0
}

# branches: merged-PR head branches that are safe to delete.
#
# A branch is a candidate only if a merged PR in this repo had it as its head
# *and* its tip is still that PR's headRefOid. Matching on the name alone would
# delete a branch that was reused after the merge and holds new commits. The
# default branch, protected branches, and any branch that is the head or the base
# of an open PR are never candidates: deleting the base closes the open PR.
cmd_branches() {
  local repo default merged open branches rows count name sha which total=0
  for repo in "${targets[@]}"; do
    if ! default="$(gh api "repos/$owner/$repo" --jq .default_branch)" \
      || ! merged="$(gh pr list -R "$owner/$repo" --state merged --limit "$pr_limit" \
        --json headRefName,headRefOid,isCrossRepository)" \
      || ! open="$(gh pr list -R "$owner/$repo" --state open --limit "$pr_limit" \
        --json headRefName,baseRefName)" \
      || ! branches="$(gh api "repos/$owner/$repo/branches" --paginate)"; then
      fail "cannot read $owner/$repo"
      continue
    fi
    for which in merged open; do
      if [ "$(jq length <<<"${!which}")" -ge "$pr_limit" ]; then
        printf '%s/%s: warning: %s PR list reached --limit %s; older ones are not considered\n' \
          "$owner" "$repo" "$which" "$pr_limit" >&2
      fi
    done

    # A fork's PR may share a branch name with ours without being our branch.
    rows="$(jq -r --arg def "$default" --argjson merged "$merged" --argjson open "$open" '
      ($merged | map(select(.isCrossRepository | not) | "\(.headRefName) \(.headRefOid)")) as $m
      | ($open | map(.headRefName, .baseRefName)) as $o
      | .[]
      | select(.name != $def and (.protected | not))
      | select((.name | IN($o[])) | not)
      | select("\(.name) \(.commit.sha)" | IN($m[]))
      | [.name, .commit.sha] | @tsv' <<<"$branches")"

    count=0
    while IFS=$'\t' read -r name sha; do
      [ -n "$name" ] || continue
      # The name goes into a URL path. Refuse anything that would need
      # escaping rather than guess at it; the branch is simply left alone.
      case "$name" in
        *[!A-Za-z0-9._/-]*)
          printf '%s/%s: %s  skipped (unusual characters in name)\n' "$owner" "$repo" "$name"
          continue ;;
      esac
      count=$((count + 1))
      if [ "$apply" = 1 ]; then
        if gh api -X DELETE "repos/$owner/$repo/git/refs/heads/$name" >/dev/null; then
          printf '%s/%s: deleted %s (was %.7s)\n' "$owner" "$repo" "$name" "$sha"
        else
          fail "DELETE $owner/$repo $name"
        fi
      else
        printf '%s/%s: %s  %.7s\n' "$owner" "$repo" "$name" "$sha"
      fi
    done <<<"$rows"
    printf '%s/%s: %s merged branch(es)\n' "$owner" "$repo" "$count"
    total=$((total + count))
  done

  printf 'total: %s\n' "$total"
  [ "$failures" = 0 ] || return 3
  [ "$apply" = 1 ] || echo "dry-run: nothing deleted. Re-run with --apply."
  return 0
}

mode="${1:-}"
[ -n "$mode" ] || usage
shift
apply=0
targets=()
for arg in "$@"; do
  case "$arg" in
    --apply) apply=1 ;;
    -*) usage ;;
    *)
      is_declared_repo "$arg" || { echo "not a declared repo: $arg" >&2; exit 2; }
      targets+=("$arg")
      ;;
  esac
done
[ "${#targets[@]}" -gt 0 ] || targets=("${repos[@]}")

command -v gh >/dev/null 2>&1 || { echo "needs gh" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "needs jq" >&2; exit 3; }

case "$mode" in
  settings) cmd_settings ;;
  branches) cmd_branches ;;
  *) usage ;;
esac
