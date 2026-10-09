#!/usr/bin/env bash
# Tests for `setup.sh headroom-init`, which retires headroom's token-mode
# init-user profile and installs the cache-mode service. They run against a
# throwaway HOME with a stub `headroom` on PATH, so neither the real proxy nor
# systemd is touched.
#
# The cases that matter: `headroom init` (which writes a token-mode manifest)
# is never called, the hooks and plugin that would restart init-user are gone,
# ANTHROPIC_BASE_URL survives, and a run-headroom.sh that execs a mise shim
# fails the run instead of leaving systemd restarting it forever.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../setup.sh"
tmp="$(mktemp -d)"
trap 'kill "$runner" 2>/dev/null; rm -rf "$tmp"' EXIT

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# usage: expect <name> <expected> <actual>
expect() {
  [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

# The stub records its arguments and, for `install apply`, writes the runner
# script the way headroom does: exec'ing the first `headroom` on PATH.
stub() {
  mkdir -p "$1"
  cat >"$1/headroom" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$HOME/headroom.calls"
if [ "$1 $2" = "install apply" ]; then
  mkdir -p "$HOME/.headroom/deploy/default"
  printf 'exec %s install agent run --profile default\n' "$(command -v headroom)" \
    >"$HOME/.headroom/deploy/default/run-headroom.sh"
fi
EOF
  chmod +x "$1/headroom"
}

# usage: run <settings-json> [extra PATH dir first] [no-local] -> sets $rc and $home
run() {
  home="$tmp/home"
  rm -rf "$home"
  mkdir -p "$home/.claude" "$home/.headroom/deploy/init-user"
  printf '%s' "$1" >"$home/.claude/settings.json"
  echo '{"profile":"init-user","proxy_mode":"token"}' >"$home/.headroom/deploy/init-user/manifest.json"
  sleep 300 &
  runner=$!
  echo "$runner" >"$home/.headroom/deploy/init-user/runner.pid"
  [ -n "${3:-}" ] || stub "$home/.local/bin"
  HOME="$home" PATH="${2:+$2:}$PATH" bash "$script" headroom-init >/dev/null 2>&1
  rc=$?
}

settings='{"env":{"KEEP":"x"},"hooks":{"PreToolUse":[
  {"matcher":"Bash","hooks":[{"type":"command","command":"headroom init hook ensure --profile init-user --marker headroom-init-claude"}]},
  {"matcher":"Bash","hooks":[{"type":"command","command":"other-hook"}]}]},
  "enabledPlugins":{"headroom@headroom-marketplace":true}}'

run "$settings"
s="$home/.claude/settings.json"
expect "exit status" 0 "$rc"
expect "init never called" "" "$(grep '^init' "$home/headroom.calls")"
expect "install apply in cache mode" "install apply --target claude --mode cache" "$(cat "$home/headroom.calls")"
expect "init-user profile removed" "no" "$([ -e "$home/.headroom/deploy/init-user" ] && echo yes || echo no)"
expect "init-user runner stopped" "no" "$(kill -0 "$runner" 2>/dev/null && echo yes || echo no)"
expect "init-user hook removed" "other-hook" "$(jq -r '[.hooks.PreToolUse[].hooks[].command] | join(",")' "$s")"
expect "plugin disabled" "false" "$(jq -r '.enabledPlugins["headroom@headroom-marketplace"]' "$s")"
expect "base URL set" "http://127.0.0.1:8787" "$(jq -r '.env.ANTHROPIC_BASE_URL' "$s")"
expect "tool search kept on" "true" "$(jq -r '.env.ENABLE_TOOL_SEARCH' "$s")"
expect "other env kept" "x" "$(jq -r '.env.KEEP' "$s")"
expect "runner execs ~/.local/bin" "exec $home/.local/bin/headroom install agent run --profile default" \
  "$(cat "$home/.headroom/deploy/default/run-headroom.sh")"

# A user-set ENABLE_TOOL_SEARCH is respected, and no hooks key is fine.
run '{"env":{"ENABLE_TOOL_SEARCH":"false"}}'
expect "no hooks: exit status" 0 "$rc"
expect "user tool search kept" "false" "$(jq -r '.env.ENABLE_TOOL_SEARCH' "$home/.claude/settings.json")"

# Even with a shim earlier on PATH, ~/.local/bin wins; if it did not, the run fails.
stub "$tmp/mise/shims"
run '{}' "$tmp/mise/shims"
expect "shim on PATH: exit status" 0 "$rc"
expect "shim on PATH: runner execs ~/.local/bin" "exec $home/.local/bin/headroom install agent run --profile default" \
  "$(cat "$home/.headroom/deploy/default/run-headroom.sh")"

# Without a headroom in ~/.local/bin the shim is what gets baked in: fail loudly.
run '{}' "$tmp/mise/shims" no-local
expect "only a shim: exit status" 1 "$rc"

if [ "$failures" != 0 ]; then
  printf '\n%s headroom-init test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "headroom-init tests ok"
