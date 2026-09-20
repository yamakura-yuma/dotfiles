# makura-agents

Shared Claude Code agent config, packaged so that any repo can opt into it.

It lives inside `dotfiles` because that is where it is maintained, but it is a
standalone APM package: depending on it never drags in anything dotfiles-
specific. The rule for what may live here is simply that it has to be true of
*every* repo that installs it — anything phrased as "in this repo" belongs in
`../\.apm/` instead.

## What you get

Rules and skills are split by when they have to be in the agent's head. A rule
is loaded on every prompt, so it carries the instruction itself and nothing
more; the reasoning, the procedure and the caveats sit in a skill of the same
name, which is read only when it is needed. `language` is the exception — it
has to be in effect before there is any chance to open a skill.

| | |
| --- | --- |
| `language` rule | Respond in Japanese, except where an existing file's language should win (commit messages, READMEs, code comments). The one rule that carries its whole content. |
| `guard-default-branch` hook | Refuses `git commit` / `git push` while HEAD is on the default branch, pointing you at a worktree instead. See below. |
| `guard-destructive-git` hook | Refuses the four git commands that destroy work which exists nowhere else: `reset --hard`, `clean -f`, whole-tree `checkout --` / `restore`, and `push --force`. `--force-with-lease` and `reset --soft` stay allowed. |
| `git-workflow` rule + skill | Rule: work on a branch, and the safe substitute for each refused command. Skill: how the hooks decide, where the line falls, how a human lifts one. |
| `testing` rule + skill | Rule: ship the test with the change, run `.agent/verify.sh`, report only what was verified. Skill: how to place tests, how to cover what must *not* trip, why self-verification drifts green. |
| `workspace-scope` rule + skill | Rule: stay inside the repo, edit `.apm/` sources rather than generated `.claude/`, leave `~/.claude/settings.json` alone. Skill: the overwrite incident behind it, and why this is a rule and not a third hook. |
| `code-navigation` rule + skill | Rule: query the index first — `graphify` for where to look, `codegraph` for verbatim source and call paths — with `Read`/`Grep` as the fallback. Skill: what each returns, the worktree gap, and what the headroom proxy does to large output. |
| `communication` rule + skill | Rule: lead with a diagram or table and cut to the decision. Skill: why long prose goes unread, and what to remove. |
| `verifier` subagent | Runs the repo's verification and reports the raw result. It is given `Bash, Read, Grep, Glob` and **no `Edit` or `Write`**, so it has no way to turn a failure green. |
| `/verify` command | Runs the repo's verification through that subagent. |
| `/worktree <task>` command | Hands a task to a Claude worker in a fresh Orca worktree, including the "write your report to `.agent/report.md`" instruction. |
| `/retro` command | Runs `session-retro` explicitly. Nothing else fires it, so this is what turns a lesson into something that survives the session. |
| `orca-orchestration` skill | A pointer at `orca skills get orchestration`, plus the conventions of this workspace. |
| `session-retro` skill | At the end of a session or after a correction, decide whether a durable lesson was learned and which `.apm/` it belongs in — then delete the memory it was promoted from. |
| `skill-authoring` skill | How to add or improve a skill through apm, and whether a given piece of knowledge is a skill, an instruction, or a CLAUDE.md line. |

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

Only the *name* `.agent/verify.sh` is shared. What it runs is always local — build
and test look different in every language — so the package defines the calling
convention and each repo supplies the contents.

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
`session-retro` decides whether a lesson is real and which `.apm/` it belongs
in, `/retro` is what invokes it, and the memory it came from gets deleted so
that only one copy can go stale.

No hook drives this. A reminder that fires on every tool call gets tuned out —
that has been observed directly here — while the thing that actually changes
behavior next session is the rule being in git.

## Tests

```bash
./makura-agents/tests/guards.sh         # guard hooks, by feeding them payloads
./makura-agents/tests/harness-check.sh  # invariants of the package itself
```

Both live outside `.apm/`, because apm deploys only `.apm/`: a consuming repo
gets the hooks and rules without the tests, while the tests stay next to what
they cover. dotfiles' own `.agent/verify.sh` runs both.

`tests/eval/` asks the other question — whether installing this changes what an
agent does — by running one prompt in two fixture repos, with and without the
package, and requiring the behavior to appear only in the first. It costs real
money per case, so it is not part of `verify.sh`; see `makura-agents/tests/eval/README.md`.

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
    path: makura-agents
    ref: <commit>          # no tags upstream; bump with `apm update`
    alias: makura-agents
```

In a repo with no `apm.yml` yet, one command writes it for you:

```bash
apm install 'https://github.com/yamakura-yuma/dotfiles.git#<commit>' --target claude
```

`--target claude` is not optional — without it apm scans for harness markers
and aborts with "No harness detected" in a repo that has no `.claude/` yet.

A local path (`- path: /home/you/k8s-workspace/dotfiles/makura-agents`) works
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
(`~/.claude/settings.json.graphify-bak`), so it is a rule in
`workspace-scope.instructions.md` rather than a third hook.

`guard-destructive-git` draws its line at *what cannot be recovered*, not at
what sounds alarming. `git reset --soft`, `git checkout <branch>` and
`git push --force-with-lease` all pass, because each either keeps the work or
refuses on its own when the remote has moved. Note that `--force` and
`--force-with-lease` share a prefix, so the match requires a separator after
`--force`; `makura-agents/tests/guards.sh` pins that case specifically,
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
