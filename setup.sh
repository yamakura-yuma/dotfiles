#!/usr/bin/env bash
# One-shot bootstrap for a fresh host: installs Nix, the nix-packaged tools
# (jq/just/uv/node), everything else via `just reload` (apm/codegraph/
# graphifyy/headroom-ai installs + MCP servers), and the one-time durable
# headroom/graphify integrations via `just agents-init`. Safe to re-run.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Nix itself (no-op if already installed).
"$DIR/install-nix.sh"

# This script runs in a single process, so a fresh Nix install's daemon
# profile script needs to be sourced explicitly rather than relying on a new
# shell to pick it up.
if ! command -v nix >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
export PATH="$HOME/.nix-profile/bin:$PATH"

# 2. Nix-packaged tools: jq, just, uv, node (gets `just` onto PATH for step 3).
nix profile upgrade agent-tools 2>/dev/null || nix profile install "path:$DIR#agent-tools"

cd "$DIR"

# 3. Symlinks, apm/codegraph/graphifyy/headroom-ai installs, MCP servers.
just reload

# 4. One-time durable headroom + graphify integrations.
just agents-init

cat <<'EOF'

Setup complete. Open a new shell (or re-source your profile) so nix/jq/just/
uv/node are on PATH for future sessions.
EOF
