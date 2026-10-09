#!/usr/bin/env bash
# Tests for bin/claude-haiku-direct.sh against a stub `claude` that records its
# arguments, so no API call is made. What matters: Haiku 5.5 is asked for, the
# base URL goes in through --settings (an exported ANTHROPIC_BASE_URL loses to
# the `env` in ~/.claude/settings.json), and extra arguments are passed on.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../bin/claude-haiku-direct.sh"
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

mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@"\n' >"$tmp/bin/claude"
chmod +x "$tmp/bin/claude"

args="$(PATH="$tmp/bin:$PATH" bash "$script" -p "hi there" --resume x)"

expect "model" "claude-haiku-5-5" "$(printf '%s\n' "$args" | sed -n '/^--model$/{n;p}')"
settings="$(printf '%s\n' "$args" | sed -n '/^--settings$/{n;p}')"
expect "settings is valid json with the direct URL" "https://api.anthropic.com" \
  "$(printf '%s' "$settings" | jq -r '.env.ANTHROPIC_BASE_URL')"
expect "extra args: -p" "hi there" "$(printf '%s\n' "$args" | sed -n '/^-p$/{n;p}')"
expect "extra args: --resume" "x" "$(printf '%s\n' "$args" | sed -n '/^--resume$/{n;p}')"

[ "$failures" -eq 0 ] || exit 1
echo "haiku-direct tests ok"
