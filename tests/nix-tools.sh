#!/usr/bin/env bash
# Tests for `setup.sh nix-tools`, against a stub `nix` that keeps a fake
# profile in a file, so they run offline and never touch ~/.nix-profile.
#
# The case that matters is the one that broke (#19): reloading from another
# checkout left agent-tools, agent-tools-1, ... in the profile, and the name
# check then never matched again. Whatever the profile holds beforehand, one
# run has to leave exactly one agent-tools pointing at the checkout it ran
# from.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../setup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# The profile is one "name url" line per element; every call is logged. The
# listing bolds the names the way real nix does even into a pipe, which is
# what hid the old `^Name: agent-tools$` check.
mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "$1" = profile ] || exit 1
sub=$2; shift 2
[ "${1:-}" = --profile ] && shift 2
echo "$sub $*" >>"$STUB_LOG"
touch "$STUB_PROFILE"
case "$sub" in
  list)
    while read -r name url; do
      printf 'Name:               \033[1m%s\033[0m\n' "$name"
      printf 'Original flake URL: %s\n\n' "$url"
    done <"$STUB_PROFILE" ;;
  remove)
    for n in "$@"; do grep -v "^$n " "$STUB_PROFILE" >"$STUB_PROFILE.new" || true
      mv "$STUB_PROFILE.new" "$STUB_PROFILE"; done ;;
  install)
    name=agent-tools i=0
    while grep -q "^$name " "$STUB_PROFILE"; do i=$((i + 1)); name=agent-tools-$i; done
    echo "$name ${1%#*}" >>"$STUB_PROFILE" ;;
  upgrade) ;;
esac
EOF
chmod +x "$tmp/bin/nix"

# usage: run <profile-lines>  -> sets $ops (mutating calls) and $profile
run() {
  printf '%s' "$1" >"$tmp/profile"
  : >"$tmp/log"
  HOME="$tmp/home" PATH="$tmp/bin:$PATH" NIX_PROFILE="$tmp/p" \
    STUB_PROFILE="$tmp/profile" STUB_LOG="$tmp/log" \
    bash "$script" nix-tools >/dev/null 2>&1 || fail "nix-tools exited non-zero"
  ops="$(grep -v '^list' "$tmp/log")"
  profile="$(cat "$tmp/profile")"
}

# usage: expect <name> <expected> <actual>
expect() {
  [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

me="path:$(cd "$here/.." && pwd)"

run ""
expect "empty profile: installs" "install $me#agent-tools" "$ops"
expect "empty profile: one element" "agent-tools $me" "$profile"

run "agent-tools $me
"
expect "already this checkout: upgrades in place" "upgrade agent-tools" "$ops"
expect "already this checkout: unchanged" "agent-tools $me" "$profile"

run "agent-tools path:/old/dotfiles
"
expect "other checkout: replaced" "agent-tools $me" "$profile"

run "agent-tools path:/old/dotfiles
agent-tools-1 path:/wt/a
hello path:/elsewhere
agent-tools-2 $me
"
expect "duplicates: all copies removed at once" \
  "remove agent-tools agent-tools-1 agent-tools-2" "$(head -n 1 <<<"$ops")"
expect "duplicates: converge to one, others kept" "hello path:/elsewhere
agent-tools $me" "$profile"

# A lone agent-tools-1 is still ours, and must not be upgraded as if it were
# named agent-tools.
run "agent-tools-1 $me
"
expect "renamed copy: reinstalled under its name" "agent-tools $me" "$profile"

if [ "$failures" != 0 ]; then
  printf '\n%s nix-tools test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "nix-tools tests ok"
