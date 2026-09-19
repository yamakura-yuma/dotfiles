# dotfiles

Declarative "agent environment" setup shared across repos and hosts (WSL,
ubuntu, ZCU104, ...). Project-specific toolchains do not belong here — those
live in each project's own `flake.nix` / `.devcontainer/`.

## Contents

- `flake.nix` — the nixpkgs-available subset of the tooling (`jq` for the
  statusline, `just` for this repo's task runner, `uv` + `node` as runtimes
  backing the other tools), bundled into one `agent-tools` package. Update
  versions with `nix flake update` (bumps the pinned nixpkgs revision, then
  `just reload` picks up the new build) rather than an implicit "latest".
- `install-nix.sh` — one-time, per-host: installs Nix itself (system/
  multi-user). Not a `just` recipe — `just` itself comes from Nix.
- `bin/install-apm.sh` — installs/upgrades `apm` from its GitHub release
  binaries (not in nixpkgs).
- `claude/statusline.sh` — the Claude Code statusline script.
- `apm.yml` — declares the `codegraph` and `headroom` MCP servers. This is
  the source of truth for `mcpServers` in `~/.claude.json`; don't hand-edit
  that section there, edit this file and re-run `just reload` instead.
- `setup.sh` — one-shot bootstrap for a fresh host: chains
  `install-nix.sh` → `nix profile install` → `just reload` → `just
  agents-init`. Safe to re-run.
- `Justfile`:
  - `just nix-tools` — installs/upgrades the `flake.nix` bundle
    (`jq`/`just`/`uv`/`node`) via `nix profile`.
  - `just reload` — runs `nix-tools`, re-links the symlinks below, installs/
    upgrades `apm`, `codegraph` (npm), `graphifyy` and `headroom-ai` (uv
    tool) — the four tools with no nixpkgs package, each via its own
    installer — then `apm install -g` to apply `apm.yml`'s MCP servers.
    Safe to re-run any time, including after moving this repo to a new path.
  - `just agents-init` — one-time per host: installs headroom's persistent
    proxy service and durable Claude Code routing hook, and graphify's
    durable Claude Code integration (see "Automatic agent tooling" below).
    Not part of `reload` since it starts long-lived background processes.

## Bootstrap on a new host

```bash
git clone <this-repo> ~/dotfiles   # any path works; just reload is location-independent
cd ~/dotfiles
./setup.sh   # needs sudo for the one-time, multi-user Nix install
```

`setup.sh` chains everything below in order; run the steps individually only
if you need to debug one:

```bash
# Nix itself (one-time per host; needs sudo for the multi-user install)
./install-nix.sh
# open a new shell (or source the nix-daemon profile script) so `nix` is on PATH

# nix-packaged tools: jq, just, uv, node (gets you `just`, among others)
nix profile install path:.#agent-tools

# everything else: symlinks, apm/codegraph/graphifyy/headroom-ai installs,
# apply apm.yml's MCP servers
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
  background service (systemd/launchd), and `headroom init --global claude`
  installs a durable hook so a plain `claude` invocation always routes
  through it — no `headroom wrap claude` needed, and it also covers
  non-interactive launches (e.g. Orca starting `claude` directly in a
  worktree terminal, which wouldn't see a `.bashrc` shell-function wrapper).
  Verify with `headroom doctor`.
- **graphify** also needs `just agents-init` once per host: `graphify install
  --platform claude` installs the `/graphify` skill globally
  (`~/.claude/skills/graphify/SKILL.md`) and a short pointer in
  `~/.claude/CLAUDE.md`. `graphify claude install` then adds the automatic
  part — a detailed CLAUDE.md section plus a `.claude/settings.json`
  `PreToolUse` hook, so Claude consults the graph without anyone typing
  `/graphify`. That second command writes relative to whatever directory
  it's run in, so the recipe runs it from `$HOME` (`~/CLAUDE.md` +
  `~/.claude/settings.json`) to make it apply globally rather than scoping
  it to whatever project happens to be the current directory.

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

Nix's system install adds `~/.nix-profile/bin` (via `/etc/bashrc` or
equivalent profile.d hook) to `PATH` for every shell, interactive or not —
`nix profile install` binaries are plain symlinks there, not shims requiring
an `activate` step. This is unlike the tool this repo previously used
(mise), whose `mise activate` only took effect in shells that source
`~/.bashrc`, silently missing non-interactive automation paths. `codegraph`
and `headroom` are registered in `~/.claude.json` as bare commands, which
also fall back to any same-named binary already on `PATH` — keep that in
mind before removing a tool's original install.
