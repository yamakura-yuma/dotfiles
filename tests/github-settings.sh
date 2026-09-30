#!/usr/bin/env bash
# Tests for bin/github-settings.sh, against a stub `gh` that serves canned JSON
# from files and logs every mutating call, so they run offline and never touch
# GitHub.
#
# What matters: a dry-run must make no mutating call at all; --apply must make
# exactly the calls that fix the drift and sweep the candidates; and a branch
# is a candidate only when its tip is still its merged PR's head -- never on the
# name alone.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../bin/github-settings.sh"
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

# Fixtures live in $STUB_DIR/<repo>/{repo,branches,merged,open}.json. Reads are
# served through jq so `--jq` behaves as in gh; PATCH and DELETE are only logged
# (and fail when the call matches $STUB_FAIL).
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -eu
echo "$*" >>"$STUB_LOG"
serve() {
  local file="$STUB_DIR/$1/$2.json" filter=.
  shift 2
  while [ $# -gt 0 ]; do
    [ "$1" = --jq ] && filter="$2"
    shift
  done
  [ -f "$file" ] || exit 1
  jq -r "$filter" "$file"
}
case "$1" in
  api)
    shift
    if [ "$1" = -X ]; then
      if [ -n "${STUB_FAIL:-}" ] && [[ "$*" == *"$STUB_FAIL"* ]]; then exit 1; fi
      exit 0
    fi
    path="${1#repos/*/}"
    repo="${path%%/*}"
    case "$path" in
      */branches) serve "$repo" branches ;;
      *) serve "$repo" repo "${@:2}" ;;
    esac ;;
  pr)
    repo="${4#*/}"
    [ "$5" = --state ] && serve "$repo" "$6" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"

# usage: run <args...>  -> sets $out (stdout+stderr), $code, $mutations
run() {
  : >"$tmp/log"
  out="$(STUB_DIR="$tmp/repos" STUB_LOG="$tmp/log" PATH="$tmp/bin:$PATH" \
    bash "$script" "$@" 2>&1)"
  code=$?
  mutations="$(grep '^api -X' "$tmp/log" || true)"
}

# usage: mkrepo <repo> <delete_branch_on_merge> [default_branch]
mkrepo() {
  mkdir -p "$tmp/repos/$1"
  printf '{"default_branch":"%s","delete_branch_on_merge":%s}\n' "${3:-main}" "$2" \
    >"$tmp/repos/$1/repo.json"
  echo '[]' >"$tmp/repos/$1/branches.json"
  echo '[]' >"$tmp/repos/$1/merged.json"
  echo '[]' >"$tmp/repos/$1/open.json"
}

for r in dotfiles coordinator knowledge-base temporal-workflow-kit home-k8s; do
  mkrepo "$r" false
done

# -- settings ------------------------------------------------------------------

run settings
expect "settings dry-run: differing repos exit 1" 1 "$code"
expect "settings dry-run: every repo reported" 5 "$(grep -c 'delete_branch_on_merge  false -> true' <<<"$out")"
expect "settings dry-run: no mutating call" "" "$mutations"

mkrepo coordinator true
mkrepo home-k8s true
run settings --apply
expect "settings --apply: exit 0" 0 "$code"
expect "settings --apply: PATCH only the drifted repos" \
  "api -X PATCH repos/yamakura-yuma/dotfiles -F delete_branch_on_merge=true
api -X PATCH repos/yamakura-yuma/knowledge-base -F delete_branch_on_merge=true
api -X PATCH repos/yamakura-yuma/temporal-workflow-kit -F delete_branch_on_merge=true" "$mutations"

for r in dotfiles knowledge-base temporal-workflow-kit; do mkrepo "$r" true; done
run settings
expect "settings aligned: exit 0" 0 "$code"
expect "settings aligned: no mutating call" "" "$mutations"

run settings dotfiles
expect "settings one repo: only that repo is read" "api repos/yamakura-yuma/dotfiles" "$(cat "$tmp/log")"

# A token without admin gets no such field; that is an error, not "false".
echo '{"default_branch":"main"}' >"$tmp/repos/dotfiles/repo.json"
run settings --apply dotfiles
expect "settings unreadable field: exit 3" 3 "$code"
expect "settings unreadable field: not patched" "" "$mutations"

mkrepo dotfiles false
STUB_FAIL=PATCH run settings --apply dotfiles
expect "settings PATCH fails: exit 3" 3 "$code"

mv "$tmp/repos/dotfiles" "$tmp/repos/dotfiles.gone"
run settings dotfiles
expect "settings unreadable repo: exit 3" 3 "$code"
mv "$tmp/repos/dotfiles.gone" "$tmp/repos/dotfiles"

# -- branches ------------------------------------------------------------------

# One repo that has each case the candidate rule must tell apart.
d="$tmp/repos/home-k8s"
cat >"$d/branches.json" <<'EOF'
[
  {"name":"main","protected":true,"commit":{"sha":"aaa0000"}},
  {"name":"merged-clean","protected":false,"commit":{"sha":"bbb1111"}},
  {"name":"feat/slash","protected":false,"commit":{"sha":"ccc2222"}},
  {"name":"reused-name","protected":false,"commit":{"sha":"ddd3333-newer"}},
  {"name":"never-had-pr","protected":false,"commit":{"sha":"eee4444"}},
  {"name":"open-head","protected":false,"commit":{"sha":"fff5555"}},
  {"name":"open-base","protected":false,"commit":{"sha":"ggg6666"}},
  {"name":"protected-merged","protected":true,"commit":{"sha":"hhh7777"}},
  {"name":"fork-only","protected":false,"commit":{"sha":"iii8888"}},
  {"name":"weird#name","protected":false,"commit":{"sha":"jjj9999"}},
  {"name":"rerun","protected":false,"commit":{"sha":"kkk0001"}}
]
EOF
cat >"$d/merged.json" <<'EOF'
[
  {"headRefName":"merged-clean","headRefOid":"bbb1111","isCrossRepository":false},
  {"headRefName":"feat/slash","headRefOid":"ccc2222","isCrossRepository":false},
  {"headRefName":"reused-name","headRefOid":"ddd3333","isCrossRepository":false},
  {"headRefName":"open-head","headRefOid":"fff5555","isCrossRepository":false},
  {"headRefName":"open-base","headRefOid":"ggg6666","isCrossRepository":false},
  {"headRefName":"protected-merged","headRefOid":"hhh7777","isCrossRepository":false},
  {"headRefName":"fork-only","headRefOid":"iii8888","isCrossRepository":true},
  {"headRefName":"weird#name","headRefOid":"jjj9999","isCrossRepository":false},
  {"headRefName":"rerun","headRefOid":"kkk0000","isCrossRepository":false},
  {"headRefName":"rerun","headRefOid":"kkk0001","isCrossRepository":false},
  {"headRefName":"main","headRefOid":"aaa0000","isCrossRepository":false}
]
EOF
cat >"$d/open.json" <<'EOF'
[
  {"headRefName":"open-head","baseRefName":"main"},
  {"headRefName":"stacked-on-top","baseRefName":"open-base"}
]
EOF

run branches home-k8s
expect "branches dry-run: exit 0" 0 "$code"
expect "branches dry-run: exactly the safe ones" \
  "yamakura-yuma/home-k8s: feat/slash  ccc2222
yamakura-yuma/home-k8s: merged-clean  bbb1111
yamakura-yuma/home-k8s: rerun  kkk0001" \
  "$(grep -E '^yamakura-yuma/home-k8s: [^ ]+  [0-9a-z]{7}$' <<<"$out" | sort)"
expect "branches dry-run: the unusual name is reported, not listed as a candidate" 1 \
  "$(grep -c 'weird#name  skipped' <<<"$out")"
expect "branches dry-run: count" "total: 3" "$(grep '^total' <<<"$out")"
expect "branches dry-run: no mutating call" "" "$mutations"

run branches --apply home-k8s
expect "branches --apply: exit 0" 0 "$code"
expect "branches --apply: DELETE exactly the candidates" \
  "api -X DELETE repos/yamakura-yuma/home-k8s/git/refs/heads/feat/slash
api -X DELETE repos/yamakura-yuma/home-k8s/git/refs/heads/merged-clean
api -X DELETE repos/yamakura-yuma/home-k8s/git/refs/heads/rerun" \
  "$(sort <<<"$mutations")"

# One failed DELETE does not stop the others, but the run is not a success.
STUB_FAIL=merged-clean run branches --apply home-k8s
expect "branches DELETE fails: exit 3" 3 "$code"
expect "branches DELETE fails: the rest still deleted" 3 "$(grep -c '^api -X DELETE' "$tmp/log")"

run branches dotfiles
expect "branches empty repo: exit 0" 0 "$code"
expect "branches empty repo: total 0" "total: 0" "$(grep '^total' <<<"$out")"

run branches
expect "branches all repos: exit 0" 0 "$code"
expect "branches all repos: every repo summarised" 5 "$(grep -c 'merged branch(es)' <<<"$out")"

# -- usage ---------------------------------------------------------------------

run
expect "no subcommand: exit 2" 2 "$code"
run settings not-a-declared-repo
expect "undeclared repo: exit 2" 2 "$code"
expect "undeclared repo: nothing called" "" "$(cat "$tmp/log")"
run settings --force
expect "unknown flag: exit 2" 2 "$code"
run frobnicate
expect "unknown subcommand: exit 2" 2 "$code"

if [ "$failures" != 0 ]; then
  printf '\n%s github-settings test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "github-settings tests ok"
