# Re-link dotfiles-managed config files, sync mise-managed tool versions, and
# apply the declared MCP servers. Safe to re-run any time.
reload:
    mkdir -p ~/.config/mise ~/.claude ~/.apm
    ln -sfn {{justfile_directory()}}/mise.toml ~/.config/mise/config.toml
    ln -sfn {{justfile_directory()}}/claude/statusline.sh ~/.claude/statusline.sh
    ln -sfn {{justfile_directory()}}/apm.yml ~/.apm/apm.yml
    mise install
    apm install -g

# One-time per-host wiring for durable MCP tool integrations that install
# background services / hooks rather than just config files. Idempotent, but
# not part of `reload` since it starts long-lived processes.
agents-init:
    headroom install apply --target claude
    headroom init --global claude
    graphify install --platform claude
    cd ~ && graphify claude install
