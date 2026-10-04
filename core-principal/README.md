# core-principal

Shared Claude Code agent config, packaged so that any repo can opt into it.

It lives inside `dotfiles` because that is where it is maintained, but it is a
standalone APM package: depending on it never drags in anything dotfiles-
specific. The rule for what may live here is simply that it has to be true of
*every* repo that installs it — anything phrased as "in this repo" belongs in
`../\.apm/` instead.

## What you get

There is **one** rule. `core-principal.instructions.md` is loaded on every
prompt, so it is allowed to hold only two kinds of thing: a norm short enough
to state in a few lines, and a pointer saying which skill or tool to reach for
in a given situation. Everything with bulk lives in a `core-*` skill and is
read when it is needed.

The response language is the one norm that carries its own content, and it
marks where the line falls: by the time a skill could be opened, the answer is
already in the wrong language.

Two things are deliberately absent. There is no rule restating what the guard
hooks already refuse — enforcement belongs to the hook, and a prose copy of it
is read every prompt to no effect. And there is no summary of Orca, because
Orca publishes its own skills.

| | |
| --- | --- |
| `core-principal` rule | The only always-loaded file: response language, then which skill or tool applies to navigating, explaining, verifying, changing the harness, retrospecting, and Orca. |
| `guard-default-branch` hook | Refuses `git commit` / `git push` while HEAD is on the default branch, pointing you at a worktree instead. See below. |
| `guard-destructive-git` hook | Refuses the four git commands that destroy work which exists nowhere else: `reset --hard`, `clean -f`, whole-tree `checkout --` / `restore`, and `push --force`. `--force-with-lease` and `reset --soft` stay allowed. |
| `guard-coordinator-edit` hook | Refuses `Edit` / `Write` / `NotebookEdit` while the session is the coordinator -- the original checkout on its default branch, or a directory in no repository at all, naming `core-dispatch` as the way out. Same `MAKURA_ALLOW_MAIN=1` switch as `guard-default-branch`. |
| `dispatch-in-coordinator` hook | Not a guard: on every prompt in the coordinator it appends the dispatch norm to the message, so the layer holds without a human typing a command. Silent everywhere else. |
| `core-tools` skill | The indexes: what `graphify` and `codegraph` each return, how to tell one is present, why a worktree inherits neither, and what the headroom proxy does to large output. |
| `core-communication` skill | Why long prose goes unread, and what to cut so that a reader can decide. |
| `core-harness` skill | How this harness is built: search the published ecosystem first, then decide whether a piece of knowledge is a check, a rule, a skill or nothing, and deploy it through apm. |
| `core-retro` skill | Reviews a session for what to change about the agent's *environment* — a check, a pointer, a rule worth deleting — and routes each finding to `make ci`, to an `.apm/`, or to the memory it should be promoted out of. Adapted from mattpocock's `retro`. |
| `core-dispatch` skill | What the coordinator does instead of implementing: classify the message, write the spec, dispatch to a worktree, and pick the results back up. Reporting follows Orca's own contract -- per Task an outcome, the evidence behind it, and any unresolved blocker -- rather than a shape invented here. `references/orca.md` carries the `orca` cheat sheet and the pitfalls measured on this host. |
| `worker-limit` hook | Stops a worker that has used up its money, wall-clock time or tool calls: `continue:false` plus a deny, and one `escalation` to the coordinator the first time. It acts only when `~/.claude/worker-reports/<branch>.limits.json` exists, so the coordinator, a topic chat and a human's own session are untouched. See below. |
| `completion-reviewer` subagent | Opus, read-only. An implementation worker calls it before opening a PR and again after fixing required findings, up to the re-review limit written once in `core-dispatch`. The advisor covers the first half of the work; this covers completion. |
| `/retro` command | Runs `core-retro` explicitly. Nothing else fires it, so this is what turns a lesson into something that survives the session. |
| `/worktree <task>` command | Hands a task to a Claude worker in a fresh Orca worktree, including the "write your report to `~/.claude/worker-reports/<worktree-name>.md`" instruction. |
| `/workers` command | Formats `worktree ps` and the `worker-list` projection -- attention categories and the literal `nextAction` -- into one table. Completion is polled here rather than waited on, so this is also the recovery entry point. |
| `lib/worker-deny.settings.json` | The one copy of the `permissions.deny` every worker worktree gets: secrets (`~/.ssh`, `~/.claude/.credentials.json`) and the human's environment (`~/.bashrc`, `~/.claude/settings.json`). Workers start in bypass mode and deny still holds. apm drops `permissions` from a hook file but ships the file, so a consuming repo's `orca.yaml` setup must `cp .claude/hooks/core-principal/.apm/hooks/scripts/lib/worker-deny.settings.json .claude/settings.local.json` after `apm install`. |

### Skills pulled in from elsewhere

Declared as dependencies in `apm.yml` at pinned commits, so they travel to every
repo that depends on this package and move forward with `apm update`.

| | |
| --- | --- |
| `find-skills` | vercel-labs. Consulted **before** a skill or procedure is written here: borrow what exists, author only what does not. |
| `show-me` | humanlayer. Diagrams and standalone HTML explanations. |
| `drawio-skill` | Agents365-ai. Editable `.drawio` architecture diagrams, kept and updated rather than thrown away like `show-me`'s HTML. Exports need the draw.io desktop CLI ([setup](../docs/setup.md)). |
| `writing-for-agents`, `grill-me`, `grilling`, `handoff`, `teach`, `to-questionnaire`, `wait-what` | mattpocock's `skills/productivity`. `writing-for-agents` is the one this package's own rule/skill split follows. |
| `ponytail`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`, `ponytail-review` | Simplest-thing-that-works discipline. Upstream ships as a plugin wiring up its own `PreToolUse` hooks; only `skills/ponytail*` is taken, so the opinion is available without a hook firing on every tool call. |
| `japanese-tech-writing`, `cognitive-rhythm-writing` | Japanese prose norms. The aliases are load-bearing: `cognitive-rhythm-writing` reads `../japanese-tech-writing/SKILL.md`, so the two only work deployed as siblings under exactly these names. |
| `orca-cli`, `orchestration`, `computer-use`, `linear-tickets`, `orca-linear`, `orca-emulator`, `orca-emulator-android`, `orca-per-workspace-env` | Orca's own skills, all of them. Each is a discovery stub that loads the version-matched guide out of the `orca` binary, so it cannot drift from the CLI that will run the command — which a summary maintained here would. |

There is no shared verification convention. Each repo already has an entry
point a human uses — `make ci` here — and an agent finds it by looking; the
eval that tried to prove otherwise is written up in `core-principal/tests/eval/README.md`.

## Growing it

Claude Code already accumulates lessons on its own, under
`~/.claude/projects/<slugified-absolute-path>/memory/`. Capture is not the
problem; *keeping* is. That store is keyed by absolute path, so a lesson in it
does not survive the repo being moved, does not reach a worktree, never leaves
the host, and is never reviewed by anyone. Repos that moved out of `~` into a
workspace directory left their memories stranded at keys nothing reads anymore.

Everything under `.apm/` has none of those problems, because it moves with the
repo, is copied into every worktree, is pushed to every host, and shows up in a
diff. So the division is: **capture is automatic, promotion is deliberate.**
`core-retro` decides whether a lesson is real and where it belongs — often as
a check under `make ci` rather than as prose — `/retro` is what invokes it, and
the memory it came from gets deleted so that only one copy can go stale.

No hook drives this. A reminder that fires on every tool call gets tuned out —
that has been observed directly here — while the thing that actually changes
behavior next session is the rule being in git.

## Editing this package from inside dotfiles

`apm` copies a path dependency into `apm_modules/_local/`, and `apm install`
reads the transitive dependency list from that copy rather than from the source
next to it. So adding a skill to `core-principal/apm.yml` here appears to do
nothing: the install reports success, the new skill is absent from
`.claude/skills/` and from `apm.lock.yaml`, and no error is printed. Bumping
the package `version` does not dislodge it either.

Delete the stale copy and install again:

```sh
rm -rf apm_modules/_local/core-principal
apm install
```

A consuming repo is unaffected, because it depends on this package by git ref
rather than by path.

## Tests

```bash
./core-principal/tests/guards.sh         # guard hooks, by feeding them payloads
./core-principal/tests/harness-check.sh  # invariants of the package itself
./core-principal/tests/worker-limit.sh   # the worker-limit hook, against a stub orca
```

All live outside `.apm/`, because apm deploys only `.apm/`: a consuming repo
gets the hooks and rules without the tests, while the tests stay next to what
they cover. dotfiles' `make ci` runs all of them.

`tests/eval/` asks the other question — whether installing this changes what an
agent does — by running one prompt in two fixture repos, with and without the
package, and requiring the behavior to appear only in the first. It costs real
money per case, so it has its own `make eval` instead of belonging to
`make ci`; see `core-principal/tests/eval/README.md`.

`harness-check.sh` is about drift rather than behavior — AGENTS.md matching what
the instructions compile to, quoted paths existing, flags quoted for
`orca`/`graphify`/`codegraph`/`apm` still existing according to the tool itself,
sources and deployed output staying one-to-one, and no repo keeping a private
fork of a skill it also receives. The flag check exists because three places
once documented `orca worktree create` without its required `--name`, and
nothing noticed until an agent ran it.

## Installing it in another repo

Add the dependency to that repo's `apm.yml` and run `apm install` there. This is
your own package, so follow `main`; pin only third-party packages to a commit:

```yaml
targets:
- claude
dependencies:
  apm:
  - git: https://github.com/yamakura-yuma/dotfiles.git
    path: core-principal
    ref: main              # no tags upstream; `apm update core-principal` moves it
    alias: core-principal
```

In a repo with no `apm.yml` yet, one command writes it for you:

```bash
apm install 'https://github.com/yamakura-yuma/dotfiles.git#main' --target claude
```

`--target claude` is not optional — without it apm scans for harness markers
and aborts with "No harness detected" in a repo that has no `.claude/` yet.

A local path (`- path: /home/you/k8s-workspace/dotfiles/core-principal`) works
too and picks up edits without a push, which is convenient while changing
something here. It bakes this host's checkout path into that repo's `apm.yml`,
though, so prefer the git form for anything you commit.

`.claude/` and `apm_modules/` are gitignored, so a worktree Orca creates for a
worker starts without them. Put an `orca.yaml` in the consuming repo and Orca's
setup deploys the harness there before the agent starts:

```yaml
scripts:
  setup: |
    apm install
    apm update core-principal --yes   # `apm install` alone stays on the locked commit
    git checkout -- apm.lock.yaml     # keep the lock bump out of the worker's PR
setupAgentStartupPolicy: wait-for-setup
```

Everything deploys into the consuming repo's own `./.claude/`, never into
`~/.claude/`. Those files are generated, so gitignore `.claude/` and
`apm_modules/` there the way `dotfiles` does.

## The worker-limit hook

An interactive worker has no way to be given a budget. `--max-budget-usd` and
`--max-turns` are print-mode only (the CLI reference says so, and a TUI session
ignored both), `worker-start` passes neither, and `worker-start --timeout-ms` is
the launch wait. So the limit is a `PreToolUse` hook, which can stop a session
(`continue:false`) from the inside:

| Limit | Measured by |
| --- | --- |
| `usd` | the status line's `cost.total_cost_usd`. A hook's input does not carry it, so `claude/statusline.sh` leaves it in `~/.claude/statusline-state/<session_id>.cost`; it trails by about one tool call |
| `minutes` | now minus the Dispatch's `dispatchedAt` (UTC), asked of `orca orchestration worker-show` once, on the first call |
| `tool_calls` | the hook's own count, one per call |

The numbers come from `~/.claude/worker-reports/<branch>.limits.json`, which
whoever starts the worker writes first (`{"zone","usd","minutes","tool_calls"}`;
pstack-claude's `worker-limits <role>` prints it). Over a limit, the hook sends an
`escalation` once and stops the session; a human raises the numbers and tells the
worker to continue, and the escalation re-arms when the worker is back under.
Without `orca` or `ORCA_TERMINAL_HANDLE` it only stops.

What it does not do: it cannot stop a worker that edits its own limits file (the
spec line "do not work around it" holds that), and it protects only repos that
install this package, which is why the cost lives in `statusline.sh` rather than
in the repo. `tests/worker-limit.sh` pins the behaviour against a stub `orca`.

## The guardrail hooks

The three blocking hooks exit 2, which blocks the tool call and hands their
stderr back to the agent as the reason. They are deliberately fail-open: exit 0 in Claude
Code's hook protocol means "no opinion", not "approved", so anything they
cannot evaluate confidently (no `jq`, not a repo, detached HEAD, unparseable
payload) falls through to exit 0.

There are only three of them, and that is on purpose. A blocking hook is
asymmetric — a false positive costs something every single time it fires,
while the thing it prevents may never have happened. So the bar is "frequent,
irreversible, and hard to mistake for ordinary work". Writing outside the repo
does not clear that bar despite there being a real incident behind it
(`~/.claude/settings.json.graphify-bak`), so it is a paragraph in the
`core-harness` skill rather than a fourth hook of this kind.

`worker-limit` is the exception that clears the bar a different way, which is
why it is described above and not here. It stops by JSON rather than exit 2, and
its false positives cannot reach ordinary work: with no limits file it does
nothing, and only whoever starts a worker writes one. What it prevents is not
rare — a worker nobody is watching has no other stop.

`guard-coordinator-edit` is the one that was added deliberately rather than
reluctantly, because the layer it protects does not exist without it. An
coordinator that merely *advises* against implementing gets talked out
of it by the next small-looking request, and the damage shows up in the first
tool call rather than eventually. Its false positives are cheap in a way the
others' are not: the work is not refused, only relocated to a worktree, which
is where it was supposed to happen anyway.

`guard-destructive-git` draws its line at *what cannot be recovered*, not at
what sounds alarming. `git reset --soft`, `git checkout <branch>` and
`git push --force-with-lease` all pass, because each either keeps the work or
refuses on its own when the remote has moved. Note that `--force` and
`--force-with-lease` share a prefix, so the match requires a separator after
`--force`; `core-principal/tests/guards.sh` pins that case specifically,
because it is the one a sloppier regex would break every day.

Two details worth knowing before editing it:

- It judges the repository the command targets: it starts from `cwd` in the
  hook payload rather than `${CLAUDE_PROJECT_DIR}`, which stays pinned to where
  the session started and does not follow Claude into a worktree, then follows
  `cd` and `git -C`. A directory or refspec it cannot read (`cd "$dir"`) gets
  no opinion.
- It splits the command roughly as a shell would, so a heredoc body or a quoted
  argument that mentions `git push` does not trip it, and a push that names
  only other branches (`--delete b`, `:b`, `HEAD:feature`) passes.
- It resolves the default branch from the local `refs/remotes/origin/HEAD`
  ref, never `git remote show origin` — that would put a network round trip in
  front of every Bash call.

To lift them, export `MAKURA_ALLOW_MAIN=1` or `MAKURA_ALLOW_DESTRUCTIVE=1`
before starting Claude Code. They are environment variables and not marker
files on purpose: hooks inherit Claude Code's environment rather than the one a
Bash tool call builds, so an agent cannot grant itself either one by prefixing
a command.
