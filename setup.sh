#!/usr/bin/env bash
# Bootstrap / maintenance entry point for a host running the Claude Code
# agent environment. Subcommands mirror what used to be Justfile recipes;
# dotfiles is plain shell scripts end to end, no task runner required.
#
# Usage: ./setup.sh [install-nix|nix-tools|reload|agents-init|all]
#   install-nix   one-time: installs Nix itself (system/multi-user)
#   nix-tools     installs/upgrades jq/uv/node via `nix profile`
#   reload        symlinks, the ~/.bashrc starship prompt hook, apm and the
#                 codegraph/graphifyy/headroom-ai versions pinned in
#                 versions.env, host-apm.yml's MCP servers and this repo's own
#                 .apm/ primitives, and the OpenTelemetry env in
#                 ~/.claude/settings.json. Safe to re-run any time.
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

cmd_nix_tools() {
  ensure_nix_on_path
  if ! command -v nix >/dev/null 2>&1; then
    echo "setup.sh: nix not on PATH; run './setup.sh install-nix' first" >&2
    return 1
  fi
  # `nix profile upgrade` warns and exits 0 when nothing matches, so an
  # `upgrade || install` chain silently installs nothing on a fresh profile.
  # Check first instead, and let real errors surface rather than hiding them.
  if nix profile list | grep -qE '^Name:[[:space:]]+agent-tools$'; then
    nix profile upgrade agent-tools
  else
    nix profile install "path:$DIR#agent-tools"
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
merge_telemetry_env() {
  local settings="$HOME/.claude/settings.json" tmp
  [ -e "$settings" ] || echo '{}' >"$settings"
  tmp="$(mktemp "$settings.XXXXXX")"
  jq --slurpfile t "$DIR/claude/telemetry-env.json" '.env = ((.env // {}) + $t[0])' \
    "$settings" >"$tmp"
  # Write back through the existing file rather than `mv` so its mode stays.
  cat "$tmp" >"$settings"
  rm -f "$tmp"
}

cmd_reload() {
  cmd_nix_tools
  mkdir -p ~/.claude ~/.local/bin ~/.apm ~/.config ~/.config/dotfiles
  ln -sfn "$DIR/claude/statusline.sh" ~/.claude/statusline.sh
  merge_telemetry_env
  install_host_apm_manifest
  ln -sfn "$DIR/starship.toml" ~/.config/starship.toml
  ln -sfn "$DIR/shell/prompt.sh" ~/.config/dotfiles/prompt.sh
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

cmd_agents_init() {
  headroom install apply --target claude
  headroom init --global claude
  graphify install --platform claude
  ( cd ~ && graphify claude install )
}

case "${1:-all}" in
  install-nix) cmd_install_nix ;;
  nix-tools) cmd_nix_tools ;;
  reload) cmd_reload ;;
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
    echo "usage: $0 [install-nix|nix-tools|reload|agents-init|all]" >&2
    exit 1
    ;;
esac
