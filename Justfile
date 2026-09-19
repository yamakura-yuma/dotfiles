# Install/upgrade the nix-packaged subset of tools (jq, just, uv, node) onto
# the active profile. Handles both first install and re-runs.
nix-tools:
    nix profile upgrade agent-tools 2>/dev/null || nix profile install path:{{justfile_directory()}}#agent-tools

# Re-link dotfiles-managed config files and install/upgrade every agent tool:
# the nix-packaged ones above, plus apm/codegraph/graphifyy/headroom-ai via
# their own installers (GitHub release, npm, uv). Safe to re-run any time.
reload: nix-tools
    mkdir -p ~/.claude ~/.local/bin
    ln -sfn {{justfile_directory()}}/claude/statusline.sh ~/.claude/statusline.sh
    {{justfile_directory()}}/bin/install-apm.sh
    npm install -g @colbymchenry/codegraph@latest
    uv tool upgrade graphifyy || uv tool install graphifyy
    uv tool upgrade headroom-ai || uv tool install 'headroom-ai[mcp,proxy]'
