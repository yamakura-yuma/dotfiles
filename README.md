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
- `Justfile`:
  - `just nix-tools` — installs/upgrades the `flake.nix` bundle
    (`jq`/`just`/`uv`/`node`) via `nix profile`.
  - `just reload` — runs `nix-tools`, re-links the statusline symlink, and
    installs/upgrades `apm`, `codegraph` (npm), `graphifyy` and
    `headroom-ai` (uv tool) — the four tools with no nixpkgs package, each
    via its own installer. Safe to re-run any time, including after moving
    this repo to a new path.

## Bootstrap on a new host

```bash
git clone <this-repo> ~/dotfiles   # any path works; just reload is location-independent
cd ~/dotfiles

# Nix itself (one-time per host; needs sudo for the multi-user install)
./install-nix.sh
# open a new shell (or source the nix-daemon profile script) so `nix` is on PATH

# nix-packaged tools: jq, just, uv, node (gets you `just`, among others)
nix profile install path:.#agent-tools

# everything else: symlinks, apm/codegraph/graphifyy/headroom-ai installs
just reload
```

Then register the statusline and MCP servers in `~/.claude/settings.json` /
`~/.claude.json` (see the `statusLine` field and the `codegraph` / `headroom`
entries in `mcpServers` — not tracked here since they live in Claude Code's
own config files alongside unrelated settings).

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
