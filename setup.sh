#!/usr/bin/env bash
# Bootstrap / maintenance entry point for a host running the Claude Code
# agent environment. Subcommands mirror what used to be Justfile recipes;
# dotfiles is plain shell scripts end to end, no task runner required.
#
# Usage: ./setup.sh [install-nix|nix-tools|reload|agents-init|all]
#   install-nix   one-time: installs Nix itself (system/multi-user)
#   nix-tools     installs/upgrades jq/uv/node via `nix profile`
#   reload        symlinks, apm/codegraph/graphifyy/headroom-ai installs,
#                 apply apm.yml's MCP servers. Safe to re-run any time.
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
  "$DIR/install-nix.sh"
}

cmd_nix_tools() {
  ensure_nix_on_path
  nix profile upgrade agent-tools 2>/dev/null || nix profile install "path:$DIR#agent-tools"
}

cmd_reload() {
  cmd_nix_tools
  mkdir -p ~/.claude ~/.local/bin ~/.apm
  ln -sfn "$DIR/claude/statusline.sh" ~/.claude/statusline.sh
  ln -sfn "$DIR/apm.yml" ~/.apm/apm.yml
  "$DIR/bin/install-apm.sh"
  npm install -g @colbymchenry/codegraph@latest
  uv tool upgrade graphifyy || uv tool install graphifyy
  uv tool upgrade headroom-ai || uv tool install 'headroom-ai[mcp,proxy]'
  apm install -g
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
