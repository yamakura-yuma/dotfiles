# dotfiles

Declarative "agent environment" setup shared across repos and hosts (WSL,
ubuntu, ZCU104, ...). Project-specific toolchains do not belong here — those
live in each project's own `flake.nix` / `.devcontainer/`.

## Contents

- `mise.toml` — tool versions for the Claude Code harness tooling: `apm`
  (skill package manager), `jq` (statusline), `uv` + `node` (runtimes backing
  the other tools), and the code-intelligence/context tools `codegraph`,
  `graphify`, `headroom`.
- `claude/statusline.sh` — the Claude Code statusline script.

## Bootstrap on a new host

```bash
git clone <this-repo> ~/dotfiles

# mise itself
curl -fsSL https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# wire up the symlinks
mkdir -p ~/.config/mise ~/.claude
ln -s ~/dotfiles/mise.toml ~/.config/mise/config.toml
ln -s ~/dotfiles/claude/statusline.sh ~/.claude/statusline.sh

# install the declared tools
~/.local/bin/mise install
```

Then register the statusline and MCP servers in `~/.claude/settings.json` /
`~/.claude.json` (see the `statusLine` field and the `codegraph` / `headroom`
entries in `mcpServers` — not tracked here since they live in Claude Code's
own config files alongside unrelated settings).

## Note on shell activation

`mise activate` only takes effect in shells that source `~/.bashrc` (normal
interactive shells). A process spawned without sourcing it (e.g. some
non-interactive automation paths) won't see mise's tool paths. `codegraph`
and `headroom` are registered in `~/.claude.json` as bare commands, which
also fall back to any same-named binary already on `PATH` — keep that in mind
before removing a tool's original (non-mise) install.
