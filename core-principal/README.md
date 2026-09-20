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
| `core-tools` skill | The indexes: what `graphify` and `codegraph` each return, how to tell one is present, why a worktree inherits neither, and what the headroom proxy does to large output. |
| `core-communication` skill | Why long prose goes unread, and what to cut so that a reader can decide. |
| `core-harness` skill | How this harness is built: search the published ecosystem first, then decide whether a piece of knowledge is a check, a rule, a skill or nothing, and deploy it through apm. |
| `core-retro` skill | Reviews a session for what to change about the agent's *environment* — a check, a pointer, a rule worth deleting — and routes each finding to `make ci`, to an `.apm/`, or to the memory it should be promoted out of. Adapted from mattpocock's `retro`. |
| `/retro` command | Runs `core-retro` explicitly. Nothing else fires it, so this is what turns a lesson into something that survives the session. |
| `/worktree <task>` command | Hands a task to a Claude worker in a fresh Orca worktree, including the "write your report to `.agent/report.md`" instruction. |

### Skills pulled in from elsewhere

Declared as dependencies in `apm.yml` at pinned commits, so they travel to every
repo that depends on this package and move forward with `apm update`.

| | |
| --- | --- |
| `find-skills` | vercel-labs. Consulted **before** a skill or procedure is written here: borrow what exists, author only what does not. |
| `show-me` | humanlayer. Diagrams and standalone HTML explanations. |
| `writing-for-agents`, `grill-me`, `grilling`, `handoff`, `teach`, `to-questionnaire`, `wait-what` | mattpocock's `skills/productivity`. `writing-for-agents` is the one this package's own rule/skill split follows. |
| `ponytail`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`, `ponytail-review` | Simplest-thing-that-works discipline. Upstream ships as a plugin wiring up its own `PreToolUse` hooks; only `skills/ponytail*` is taken, so the opinion is available without a hook firing on every tool call. |
| `japanese-tech-writing`, `cognitive-rhythm-writing` | Japanese prose norms. The aliases are load-bearing: `cognitive-rhythm-writing` reads `../japanese-tech-writing/SKILL.md`, so the two only work deployed as siblings under exactly these names. |
| `orca-cli`, `orchestration`, `computer-use`, `linear-tickets`, `orca-linear`, `orca-emulator`, `orca-emulator-android`, `orca-per-workspace-env` | Orca's own skills, all of them. Each is a discovery stub that loads the version-matched guide out of the `orca` binary, so it cannot drift from the CLI that will run the command — which a summary maintained here would. |
| `genshijin`, `genshijin-commit`, `genshijin-compress`, `genshijin-crew`, `genshijin-help`, `genshijin-review`, `genshijin-stats` | Compressed Japanese responses and the commit/review/compress skills built on the same style. Upstream ships as a plugin with `SessionStart` and `UserPromptSubmit` hooks and a statusline; only the skills are taken, same policy as ponytail. |

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

## Tests

```bash
./core-principal/tests/guards.sh         # guard hooks, by feeding them payloads
./core-principal/tests/harness-check.sh  # invariants of the package itself
```

Both live outside `.apm/`, because apm deploys only `.apm/`: a consuming repo
gets the hooks and rules without the tests, while the tests stay next to what
they cover. dotfiles' `make ci` runs both.

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

Add the dependency to that repo's `apm.yml` and run `apm install` there:

```yaml
targets:
- claude
dependencies:
  apm:
  - git: https://github.com/yamakura-yuma/dotfiles.git
    path: core-principal
    ref: <commit>          # no tags upstream; bump with `apm update`
    alias: core-principal
```

In a repo with no `apm.yml` yet, one command writes it for you:

```bash
apm install 'https://github.com/yamakura-yuma/dotfiles.git#<commit>' --target claude
```

`--target claude` is not optional — without it apm scans for harness markers
and aborts with "No harness detected" in a repo that has no `.claude/` yet.

A local path (`- path: /home/you/k8s-workspace/dotfiles/core-principal`) works
too and picks up edits without a push, which is convenient while changing
something here. It bakes this host's checkout path into that repo's `apm.yml`,
though, so prefer the git form for anything you commit.

Everything deploys into the consuming repo's own `./.claude/`, never into
`~/.claude/`. Those files are generated, so gitignore `.claude/` and
`apm_modules/` there the way `dotfiles` does.

## The guardrail hooks

Both hooks exit 2, which blocks the tool call and hands their stderr back to
the agent as the reason. They are deliberately fail-open: exit 0 in Claude
Code's hook protocol means "no opinion", not "approved", so anything they
cannot evaluate confidently (no `jq`, not a repo, detached HEAD, unparseable
payload) falls through to exit 0.

There are only two of them, and that is on purpose. A blocking hook is
asymmetric — a false positive costs something every single time it fires,
while the thing it prevents may never have happened. So the bar is "frequent,
irreversible, and hard to mistake for ordinary work". Writing outside the repo
does not clear that bar despite there being a real incident behind it
(`~/.claude/settings.json.graphify-bak`), so it is a paragraph in the
`core-harness` skill rather than a third hook.

`guard-destructive-git` draws its line at *what cannot be recovered*, not at
what sounds alarming. `git reset --soft`, `git checkout <branch>` and
`git push --force-with-lease` all pass, because each either keeps the work or
refuses on its own when the remote has moved. Note that `--force` and
`--force-with-lease` share a prefix, so the match requires a separator after
`--force`; `core-principal/tests/guards.sh` pins that case specifically,
because it is the one a sloppier regex would break every day.

Two details worth knowing before editing it:

- It reads `cwd` from the hook payload rather than `${CLAUDE_PROJECT_DIR}`,
  which stays pinned to where the session started and does not follow Claude
  into a worktree.
- It resolves the default branch from the local `refs/remotes/origin/HEAD`
  ref, never `git remote show origin` — that would put a network round trip in
  front of every Bash call.

To lift them, export `MAKURA_ALLOW_MAIN=1` or `MAKURA_ALLOW_DESTRUCTIVE=1`
before starting Claude Code. They are environment variables and not marker
files on purpose: hooks inherit Claude Code's environment rather than the one a
Bash tool call builds, so an agent cannot grant itself either one by prefixing
a command.
