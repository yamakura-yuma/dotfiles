# dotfiles

Declarative "agent environment" setup shared across repos and hosts (WSL,
ubuntu, ZCU104, ...). Project-specific toolchains do not belong here — those
live in each project's own `flake.nix` / `.devcontainer/`.

## Contents

- `mise.toml` — tool versions for the Claude Code harness tooling: `apm`
  (agent/MCP package manager), `jq` (statusline), `just` (task runner for
  this repo), `uv` + `node` (runtimes backing the other tools), and the
  code-intelligence/context tools `codegraph`, `graphify`, `headroom`.
- `claude/statusline.sh` — the Claude Code statusline script.
- `apm.yml` — declares the `codegraph` and `headroom` MCP servers. This is
  the source of truth for `mcpServers` in `~/.claude.json`; don't hand-edit
  that section there, edit this file and re-run `just reload` instead.
- `Justfile`:
  - `just reload` — re-links the symlinks below (relative to wherever this
    repo currently lives), runs `mise install`, then `apm install -g` to
    apply `apm.yml`'s MCP servers. Safe to re-run any time, including after
    moving this repo to a new path.
  - `just agents-init` — one-time per host: installs headroom's persistent
    proxy service and durable Claude Code routing hook, and graphify's
    durable Claude Code integration (see "Automatic agent tooling" below).
    Not part of `reload` since it starts long-lived background processes.

## Bootstrap on a new host

```bash
git clone <this-repo> ~/dotfiles   # any path works; just reload is location-independent

# mise itself
curl -fsSL https://mise.run | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc

# install the declared tools (gets you `just`, among others)
~/.local/bin/mise install

# wire up the symlinks, sync tool versions, apply apm.yml's MCP servers
just reload

# one-time: durable headroom + graphify integrations (see below)
just agents-init
```

The statusline is symlinked automatically by `reload`. MCP servers
(`codegraph`, `headroom`) are applied by `reload` via `apm install -g` from
`apm.yml` — no manual `~/.claude.json` editing needed anymore.

## Automatic agent tooling

The goal is that `codegraph`, `graphify`, and `headroom` all work without
being consciously invoked:

- **codegraph** fires on every prompt via a `UserPromptSubmit` hook
  (`codegraph prompt-hook`) that Claude Code registers once the MCP server
  from `apm.yml` is installed — nothing else to set up.
- **headroom** needs `just agents-init` once per host: `headroom install
  apply --target claude` installs the optimization proxy as a persistent
  background service (systemd/launchd), and `headroom init claude --global`
  installs a durable hook so a plain `claude` invocation always routes
  through it — no `headroom wrap claude` needed, and it also covers
  non-interactive launches (e.g. Orca starting `claude` directly in a
  worktree terminal, which wouldn't see a `.bashrc` shell-function wrapper).
  Verify with `headroom doctor`.
- **graphify** also needs `just agents-init` once per host: `graphify claude
  install` writes a managed section into `~/.claude/CLAUDE.md` and adds a
  `PreToolUse` hook, so Claude consults the knowledge graph automatically
  instead of requiring an explicit `/graphify` invocation.

## Multi-host orchestration (Orca)

This workspace uses Orca to orchestrate Claude Code across machines: the
primary Orca app (the Windows workstation) is the Orchestrator, and it
dispatches work to SSH targets — this WSL host, `ubuntu`, and `ZCU104` — via
`orca worktree create --host ...` / `orca terminal create`. Orca injects its
own hooks into `~/.claude/settings.json` on each target host so sessions
there are observable from the primary.

Orca's host list and pairing state live entirely in the Orca app's own data
(paired via its GUI/CLI, e.g. `orca environment add`), not in files this
repo can track — there's nothing to symlink or declare here for it. Use
`orca host list` on the primary to see current targets and connection
status.

## Note on shell activation

`mise activate` only takes effect in shells that source `~/.bashrc` (normal
interactive shells). A process spawned without sourcing it (e.g. some
non-interactive automation paths) won't see mise's tool paths. `codegraph`
and `headroom` are registered in `~/.claude.json` as bare commands, which
also fall back to any same-named binary already on `PATH` — keep that in mind
before removing a tool's original (non-mise) install.
