# dotfiles

Declarative "agent environment" setup shared across repos and hosts (WSL,
ubuntu, ZCU104, ...). Project-specific toolchains do not belong here — those
live in each project's own `flake.nix` / `.devcontainer/`.

## Contents

- `flake.nix` — the nixpkgs-available subset of the tooling (`jq` for the
  statusline, `uv` + `node` as runtimes backing the other tools, `starship`
  for the shell prompt), bundled into one `agent-tools` package. `flake.lock`
  is committed, so every host resolves the same nixpkgs revision. Update
  versions with `nix flake update` (bumps that pinned revision, then
  `./setup.sh reload` picks up the new build) rather than an implicit
  "latest".
- `bin/install-nix.sh` — one-time, per-host: installs Nix itself (system/
  multi-user).
- `bin/install-apm.sh` — installs/upgrades `apm` from its GitHub release
  binaries (not in nixpkgs).
- `claude/statusline.sh` — the Claude Code statusline script.
- `starship.toml` — the shell prompt config. Enables the `kubernetes` module
  (off by default) and makes `git_status` report counts rather than bare
  symbols, so ahead/behind vs the remote and the number of
  modified/staged/untracked files are visible at a glance. The branch name
  itself and in-progress rebase/merge state come from starship's defaults.
  Symlinked to `~/.config/starship.toml` by `./setup.sh reload`.
- `shell/prompt.sh` — the interactive-shell side of the prompt: puts
  `~/.nix-profile/bin` on `PATH` and runs `starship init bash`. Sourced from
  `~/.bashrc` (see "Bootstrap on a new host"), and a no-op when `starship`
  isn't installed yet, so a half-set-up host still gets a working shell.
- `host-apm.yml` — the *host-wide* manifest, copied to `~/.apm/apm.yml` by
  `./setup.sh reload`. Declares the `codegraph` and `headroom` MCP servers
  (the source of truth for `mcpServers` in `~/.claude.json`; don't hand-edit
  that section there) and deliberately nothing else.
- `apm.yml` — the *project* manifest, applied to this repo only. Declares the
  `show-me` skill vendored from `humanlayer/skills`, pinned to a commit since
  upstream publishes no tags.
- `.apm/` — the agent behaviour this repo installs into Claude Code, authored
  as APM primitives and deployed into `./.claude/`. See "Agent harness" below.
- `AGENTS.md` — generated from `.apm/instructions/` by
  `apm compile --target agents`. Edit the sources, not this file.
- `setup.sh` — the only entry point; plain shell, no task runner. Subcommands:
  - `./setup.sh install-nix` — one-time: installs Nix itself.
  - `./setup.sh nix-tools` — installs/upgrades the `flake.nix` bundle
    (`jq`/`uv`/`node`) via `nix profile`.
  - `./setup.sh reload` — runs `nix-tools`, re-links the symlinks above,
    installs/upgrades `apm`, `codegraph` (npm), `graphifyy` and
    `headroom-ai` (uv tool) — the four tools with no nixpkgs package, each
    via its own installer — then `apm install -g` for `host-apm.yml`'s MCP
    servers and `apm install` inside this checkout for everything under
    `.apm/`. Safe to re-run any time, including after moving this repo to a
    new path.
  - `./setup.sh agents-init` — one-time per host: installs headroom's
    persistent proxy service and durable Claude Code routing hook, and
    graphify's durable Claude Code integration (see "Automatic agent
    tooling" below). Not part of `reload` since it starts long-lived
    background processes.
  - `./setup.sh` (no args, or `all`) — runs all of the above in order; this
    is the fresh-host bootstrap.

## Bootstrap on a new host

```bash
git clone <this-repo> ~/dotfiles   # any path works; setup.sh is location-independent
cd ~/dotfiles
./setup.sh   # needs sudo for the one-time, multi-user Nix install
```

That runs `bin/install-nix.sh`, `nix-tools`, `reload`, and `agents-init` in
order (see "Contents" above for what each does); run them individually only
if you need to debug one, e.g. `./setup.sh reload`.

The statusline and `starship.toml` are symlinked automatically by `reload`.
MCP servers (`codegraph`, `headroom`) are applied by `reload` via `apm
install -g` from `host-apm.yml` — no manual `~/.claude.json` editing needed
anymore.

The starship prompt is hooked into your shell by `reload` too. This repo
doesn't track `~/.bashrc` (it's yours, and full of host-specific lines), so
`reload` appends one marked block to it instead:

```bash
# >>> dotfiles >>>
[ -r "$HOME/.config/dotfiles/prompt.sh" ] && . "$HOME/.config/dotfiles/prompt.sh"
# <<< dotfiles <<<
```

That path is a symlink to `shell/prompt.sh` that `reload` re-points, so the
block is written exactly once and survives moving this repo. Re-running
`reload` won't duplicate it, and deleting the block uninstalls the prompt.
Open a new shell to pick it up. Only `bash` is wired up — change
`hook_bashrc` in `setup.sh` if this host ever switches to zsh.

## Agent harness

The agent behaviour this repo defines is authored once under `.apm/` and
deployed by `apm`, never by hand-editing Claude Code's files.

**It is scoped to this repo on purpose.** `./setup.sh reload` runs `apm
install` *inside this checkout*, not `apm install -g`, so every rule, skill
and hook below lands in `./.claude/` and applies only to a Claude Code
session whose project directory is this repo. Working in an unrelated repo is
unaffected by what is checked in here. The one exception is `host-apm.yml`'s
MCP servers, which are capabilities rather than behaviour and stay host-wide
in `~/.claude.json`.

| Source | Lands at |
| --- | --- |
| `.apm/instructions/*.instructions.md` | `./.claude/rules/` |
| `.apm/skills/<name>/SKILL.md` | `./.claude/skills/<name>/` |
| `apm.yml` `dependencies.apm` | `./.claude/skills/` (+ `./apm_modules/`) |
| `.apm/hooks/*.json` | merged into `./.claude/settings.json` |
| `host-apm.yml` `dependencies.mcp` | `~/.claude.json` (host-wide) |

`./.claude/` and `./apm_modules/` are generated, and therefore gitignored —
`.apm/` is the thing to edit and review. A fresh clone has no `.claude/`
until `./setup.sh reload` (or a bare `apm install`) runs in it; until then
the guardrail below simply isn't installed.

This goes through apm rather than a Claude Code plugin because a plugin can't
express the rest of it (`AGENTS.md` generation, the pinned upstream skill),
and because apm *merges* hook entries into `settings.json` rather than
overwriting the file, recording ownership in a sibling `apm-hooks.json` so a
re-install replaces only its own entries. That property is what keeps
`~/.claude/settings.json` — shared with four other writers (Orca, headroom,
graphify, codegraph) — safe on the rare occasion something does need to go
host-wide.

### The default-branch guardrail

`.apm/hooks/guard-default-branch.json` registers a `PreToolUse` hook on
`Bash` that refuses `git commit` and `git push` while HEAD is on the
repository's default branch. It exits 2, which blocks the call and hands its
stderr back to the agent as the reason — pointing it at `orca worktree
create` or `git worktree add -b` instead.

Being project-scoped, it protects this repo's `main` and nothing else; a
session opened in another repo gets no such protection. Note also that
`apm` rewrites the hook command to `${CLAUDE_PROJECT_DIR}/.claude/hooks/...`,
which resolves against the directory the session started in — a worktree of
this repo needs its own `apm install` to carry the hook.

The script (`.apm/hooks/scripts/guard-default-branch.sh`) is deliberately
fail-open: exit 0 in Claude Code's hook protocol means "no opinion", not
"approved", so anything it can't evaluate confidently (no `jq`, not a repo,
detached HEAD, unparseable payload) falls through to exit 0. It reads `cwd`
from the hook payload rather than `${CLAUDE_PROJECT_DIR}`, which stays
pinned to where the session started and doesn't follow Claude into a
worktree, and it resolves the default branch from the local
`refs/remotes/origin/HEAD` ref — never `git remote show origin`, which would
put a network round trip in front of every Bash call.

To lift it, export `DOTFILES_ALLOW_MAIN=1` before starting Claude Code.
It's an environment variable and not a marker file on purpose: hooks inherit
Claude Code's environment rather than the one a Bash tool call builds, so an
agent can't grant it to itself by prefixing a command.

## Automatic agent tooling

The goal is that `codegraph`, `graphify`, and `headroom` all work without
being consciously invoked:

- **codegraph** fires on every prompt via a `UserPromptSubmit` hook
  (`codegraph prompt-hook`) that Claude Code registers once the MCP server
  from `apm.yml` is installed — nothing else to set up.
- **headroom** needs `./setup.sh agents-init` once per host: `headroom install
  apply --target claude` installs the optimization proxy as a persistent
  background service (systemd/launchd), and `headroom init --global claude`
  installs a durable hook so a plain `claude` invocation always routes
  through it — no `headroom wrap claude` needed, and it also covers
  non-interactive launches (e.g. Orca starting `claude` directly in a
  worktree terminal, which wouldn't see a `.bashrc` shell-function wrapper).
  Verify with `headroom doctor`.
- **graphify** also needs `./setup.sh agents-init` once per host: `graphify install
  --platform claude` installs the `/graphify` skill globally
  (`~/.claude/skills/graphify/SKILL.md`) and a short pointer in
  `~/.claude/CLAUDE.md`. `graphify claude install` then adds the automatic
  part — a detailed CLAUDE.md section plus a `.claude/settings.json`
  `PreToolUse` hook, so Claude consults the graph without anyone typing
  `/graphify`. That second command writes relative to whatever directory
  it's run in, so `agents-init` runs it from `$HOME` (`~/CLAUDE.md` +
  `~/.claude/settings.json`) to make it apply globally rather than scoping
  it to whatever project happens to be the current directory.

## Multi-host orchestration (Orca)

This workspace uses Orca to orchestrate Claude Code across machines: the
primary Orca app (the Windows workstation) is the Orchestrator, and it
dispatches work to SSH targets — this WSL host, `ubuntu`, and `ZCU104` — via
`orca worktree create --host ...` / `orca terminal create`. Orca injects its
own hooks into `~/.claude/settings.json` on each target host so sessions
there are observable from the primary.

There is deliberately no orchestration layer in this repo. Orca already has
one (`orca orchestration run-create` / `worker-start --worktree new-child` /
`check --wait`), and `orca skills get orchestration` returns the full
supervisor playbook on demand. Copying that here would only produce a stale
duplicate, so `.apm/skills/orca-orchestration/` is a thin pointer: it says to
go read the real playbook, and records the conventions specific to this
workspace. Like the rest of `.apm/`, it is installed at project scope, so it
shows up in a session opened here — the place you'd start an orchestration
run from — and not in the worktrees the workers get dispatched into.

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
`~/.bashrc`, silently missing non-interactive automation paths. The prompt
is the one deliberate exception: `shell/prompt.sh` is sourced from
`~/.bashrc` and returns early for non-interactive shells, because a prompt
is meaningless there and its escape sequences would corrupt captured output.
`codegraph`
and `headroom` are registered in `~/.claude.json` as bare commands, which
also fall back to any same-named binary already on `PATH` — keep that in
mind before removing a tool's original install.
