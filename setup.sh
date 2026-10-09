#!/usr/bin/env bash
# Bootstrap / maintenance entry point for a host running the Claude Code
# agent environment. Subcommands mirror what used to be Justfile recipes;
# dotfiles is plain shell scripts end to end, no task runner required.
#
# Usage: ./setup.sh [install-nix|nix-tools|reload|claude-settings|headroom-init|agents-init|all]
#   install-nix   one-time: installs Nix itself (system/multi-user)
#   nix-tools     installs/upgrades jq/uv/node via `nix profile`
#   claude-settings  only the OpenTelemetry env and advisor model merge into
#                 ~/.claude/settings.json (the part of reload the tests run)
#   reload        symlinks, the ~/.bashrc starship prompt hook, apm and the
#                 codegraph/graphifyy/headroom-ai versions pinned in
#                 versions.env, host-apm.yml's MCP servers and this repo's own
#                 .apm/ primitives, and the OpenTelemetry env and advisor
#                 model in ~/.claude/settings.json. Safe to re-run any time.
#   headroom-init the headroom proxy as the cache-mode service on 8787, and
#                 retire the token-mode init-user profile (part of agents-init)
#   agents-init   one-time per host: durable headroom + graphify integrations
#   all (default) install-nix + reload + agents-init
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ensure_nix_on_path() {
  if ! command -v nix >/dev/null 2>&1; then
    # A fresh install's daemon profile script needs sourcing explicitly in
    # this process; a new shell would pick it up automatically otherwise.
    # shellcheck disable=SC1091
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true
  fi
  export PATH="$HOME/.nix-profile/bin:$PATH"
}

cmd_install_nix() {
  "$DIR/bin/install-nix.sh"
}

# NIX_PROFILE points `nix profile` at another profile than ~/.nix-profile, so
# cmd_nix_tools can be exercised against a throwaway one.
nix_profile() {
  local sub="$1"
  shift
  nix profile "$sub" ${NIX_PROFILE:+--profile "$NIX_PROFILE"} "$@"
}

cmd_nix_tools() {
  ensure_nix_on_path
  if ! command -v nix >/dev/null 2>&1; then
    echo "setup.sh: nix not on PATH; run './setup.sh install-nix' first" >&2
    return 1
  fi
  # `nix profile upgrade` warns and exits 0 when nothing matches, so an
  # `upgrade || install` chain silently installs nothing on a fresh profile.
  # Check first instead, and let real errors surface rather than hiding them.
  #
  # Installing from another checkout (a worktree, an old path) does not
  # replace the element: nix adds it again as agent-tools-1, -2, ... and the
  # next install fails on the priority clash. So upgrade only when the one
  # element is exactly this checkout's; otherwise drop every copy and install
  # afresh, which converges the profile back to one agent-tools. The listing
  # bolds each name even into a pipe, so strip the escapes before matching.
  # (`remove --regex` matches the flake reference, not the name, so the
  # copies are removed by the names read here.)
  local elems names
  elems="$(nix_profile list | awk '
    { gsub(/\033\[[0-9;]*m/, "") }
    /^Name:/ { name = $2 }
    /^Original flake URL:/ && name ~ /^agent-tools(-[0-9]+)?$/ { print name, $4 }
  ')"
  if [[ "$elems" == "agent-tools path:$DIR" ]]; then
    nix_profile upgrade agent-tools
  else
    names="$(cut -d' ' -f1 <<<"$elems")"
    # shellcheck disable=SC2086 # one word per name, split on purpose
    [[ -z "$names" ]] || nix_profile remove $names
    nix_profile install "path:$DIR#agent-tools"
  fi
  command -v starship >/dev/null 2>&1 ||
    echo "setup.sh: warning: starship still not on PATH after nix profile install" >&2
}

RC_MARK_BEGIN="# >>> dotfiles >>>"
RC_MARK_END="# <<< dotfiles <<<"

# Append a marked block to ~/.bashrc sourcing shell/prompt.sh. The block
# points at a fixed path under ~/.config that cmd_reload symlinks, so moving
# this repo only re-points the symlink and never rewrites ~/.bashrc. Deleting
# the block between the markers uninstalls it cleanly.
hook_bashrc() {
  local rc="$HOME/.bashrc"
  [ -e "$rc" ] || return 0
  # Plain `grep -q ... && return 0` as the last statement would return 1 on no
  # match and kill the script under `set -e`.
  if grep -qF "$RC_MARK_BEGIN" "$rc"; then
    return 0
  fi
  # Single quotes keep $HOME literal in ~/.bashrc instead of baking in a path.
  {
    printf '\n%s\n' "$RC_MARK_BEGIN"
    printf '%s\n' '[ -r "$HOME/.config/dotfiles/prompt.sh" ] && . "$HOME/.config/dotfiles/prompt.sh"'
    printf '%s\n' "$RC_MARK_END"
  } >>"$rc"
  echo "setup.sh: hooked the starship prompt into $rc (open a new shell to pick it up)" >&2
}

# Put host-apm.yml in place as ~/.apm/apm.yml, the manifest `apm install -g`
# reads. That manifest declares MCP servers and nothing else; the rules, skills
# and hooks under .apm/ are installed at project scope into this repo's own
# .claude/ so they never apply to an unrelated repo.
#
# Copied rather than symlinked because apm rejects an apm.yml that is a symlink
# ("apm.yml must be a regular, non-symlink file"), which silently breaks
# `apm install -g`.
install_host_apm_manifest() {
  # `rm` first: `cp` onto the symlink older hosts still have would write
  # *through* it and clobber the repo's own file.
  rm -f ~/.apm/apm.yml
  cp "$DIR/host-apm.yml" ~/.apm/apm.yml
}

# Merge claude/telemetry-env.json into the `env` of ~/.claude/settings.json so
# every Claude Code on the host exports OpenTelemetry traces. An exception to
# "nothing host-wide but MCP servers" (host-apm.yml), allowed on the same
# grounds: it adds observation, not behaviour. Only these keys are written;
# the rest of the file (headroom's ANTHROPIC_BASE_URL, graphify's hooks) is
# left as it is. See docs/configuration.md#トレース for what is sent.
#
# claude/advisor.json is merged at the top level the same way: a trial of a
# Fable advisor for every session. See docs/configuration.md#advisor.
merge_claude_settings() {
  local settings="$HOME/.claude/settings.json" tmp
  [ -e "$settings" ] || echo '{}' >"$settings"
  tmp="$(mktemp "$settings.XXXXXX")"
  jq --slurpfile t "$DIR/claude/telemetry-env.json" --slurpfile a "$DIR/claude/advisor.json" \
    '.env = ((.env // {}) + $t[0]) | . + $a[0]' "$settings" >"$tmp"
  # Write back through the existing file rather than `mv` so its mode stays.
  cat "$tmp" >"$settings"
  rm -f "$tmp"
}

# Keep the coordinator section of ~/CLAUDE.md in step with claude/home-CLAUDE.md.
# Only the block between the markers is ours: `graphify claude install`
# (agents-init) appends its own section to the same file, so the file cannot be
# a symlink into this repo. The block is replaced in place, or appended on the
# first run, dropping the unmarked copy that predates the markers.
sync_home_claude_md() {
  local f="$HOME/CLAUDE.md" b="<!-- >>> dotfiles >>> -->" e="<!-- <<< dotfiles <<< -->" tmp
  [ -e "$f" ] || : >"$f"
  tmp="$(mktemp "$f.XXXXXX")"
  if grep -qF "$b" "$f"; then
    awk -v b="$b" -v e="$e" -v src="$DIR/claude/home-CLAUDE.md" '
      index($0, b) { print; while ((getline l < src) > 0) print l; skip = 1; next }
      index($0, e) { skip = 0 }
      !skip
    ' "$f" >"$tmp"
  else
    { printf '%s\n' "$b"; cat "$DIR/claude/home-CLAUDE.md"; printf '%s\n\n' "$e"
      awk '/^## /{skip = /^## ここは coordinator/} !skip' "$f"; } >"$tmp"
  fi
  cat "$tmp" >"$f"
  rm -f "$tmp"
}

cmd_reload() {
  cmd_nix_tools
  mkdir -p ~/.claude ~/.local/bin ~/.apm ~/.config ~/.config/dotfiles
  ln -sfn "$DIR/claude/statusline.sh" ~/.claude/statusline.sh
  merge_claude_settings
  sync_home_claude_md
  install_host_apm_manifest
  ln -sfn "$DIR/starship.toml" ~/.config/starship.toml
  ln -sfn "$DIR/shell/prompt.sh" ~/.config/dotfiles/prompt.sh
  ln -sfn "$DIR/bin/claude-haiku-direct.sh" ~/.local/bin/claude-haiku-direct
  hook_bashrc
  "$DIR/bin/install-apm.sh"
  # Versions come from versions.env so that `reload` is not a silent upgrade;
  # see the comment there for how to bump one.
  # shellcheck source=versions.env
  . "$DIR/versions.env"
  # nixpkgs' npm defaults its global prefix to its own read-only /nix/store
  # path, so -g needs an explicit writable prefix. ~/.local/bin is on PATH
  # already and is where install-apm.sh puts its binary too.
  npm install -g --prefix "$HOME/.local" "@colbymchenry/codegraph@$CODEGRAPH_VERSION"
  uv tool install "graphifyy==$GRAPHIFYY_VERSION"
  uv tool install "headroom-ai[mcp,proxy]==$HEADROOM_VERSION"
  # Host scope: MCP servers only (host-apm.yml).
  apm install -g
  # Project scope: deploy .apm/ and apm.yml's dependencies into $DIR/.claude/.
  # Both of those are generated and gitignored, so this rewrites nothing that
  # is tracked; AGENTS.md stays a deliberate `apm compile --target agents`.
  ( cd "$DIR" && apm install )
}

# Run the headroom proxy as the cache-mode service, and only that.
#
# Why not `headroom init --global claude`: it writes an `init-user` profile
# whose manifest is hard-coded to `proxy_mode: token`, plus hooks (and the
# headroom@headroom-marketplace plugin) that run `headroom init hook ensure`
# before every session and Bash call. That runner took 8787 first, so the
# cache-mode service never served a request. Token mode re-compresses earlier
# turns differently from one request to the next, which rewrites the prompt
# prefix and turns each prompt-cache read into a fresh cache write.
#
# Order matters on a host that has init-user: the manifest goes first, because
# while it exists any session's hook restarts the runner we are stopping.
#
# PATH puts ~/.local/bin first because `install apply` bakes the first
# `headroom` on PATH into run-headroom.sh; a mise shim there has no version set
# outside a mise project, so systemd restarted the service forever.
cmd_headroom_init() {
  local d="$HOME/.headroom/deploy/init-user" settings="$HOME/.claude/settings.json" tmp pid
  if [ -d "$d" ]; then
    rm -f "$d/manifest.json"
    pid="$(cat "$d/runner.pid" 2>/dev/null || true)"
    [ -z "$pid" ] || pkill -TERM -P "$pid" 2>/dev/null || true
    [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
    rm -rf "$d"
  fi
  mkdir -p ~/.claude
  [ -e "$settings" ] || echo '{}' >"$settings"
  tmp="$(mktemp "$settings.XXXXXX")"
  # Routing used to be written by `headroom init`; keep it here so `claude`
  # started outside a login shell still goes through the proxy.
  # ENABLE_TOOL_SEARCH: with a custom base URL Claude Code otherwise inlines
  # every deferred tool schema (headroom GH #746).
  jq '.env = ((.env // {}) + {ANTHROPIC_BASE_URL: "http://127.0.0.1:8787"})
      | .env.ENABLE_TOOL_SEARCH //= "true"
      | if .hooks then .hooks |= with_entries(.value |= map(select(
          ([.hooks[]?.command // ""] | any(contains("headroom-init-claude"))) | not)))
        else . end
      | .enabledPlugins["headroom@headroom-marketplace"] = false' "$settings" >"$tmp"
  cat "$tmp" >"$settings"
  rm -f "$tmp"
  PATH="$HOME/.local/bin:$PATH" headroom install apply --target claude --mode cache
  if grep -q 'mise/shims' "$HOME/.headroom/deploy/default/run-headroom.sh"; then
    echo "setup.sh: run-headroom.sh still execs a mise shim" >&2
    return 1
  fi
}

cmd_agents_init() {
  cmd_headroom_init
  graphify install --platform claude
  ( cd ~ && graphify claude install )
}

case "${1:-all}" in
  install-nix) cmd_install_nix ;;
  nix-tools) cmd_nix_tools ;;
  reload) cmd_reload ;;
  claude-settings) mkdir -p ~/.claude && merge_claude_settings ;;
  headroom-init) cmd_headroom_init ;;
  agents-init) cmd_agents_init ;;
  all)
    cmd_install_nix
    cmd_reload
    cmd_agents_init
    cat <<'EOF'

Setup complete. Open a new shell (or re-source your profile) so nix/jq/
uv/node are on PATH for future sessions.
EOF
    ;;
  *)
    echo "usage: $0 [install-nix|nix-tools|reload|claude-settings|headroom-init|agents-init|all]" >&2
    exit 1
    ;;
esac
