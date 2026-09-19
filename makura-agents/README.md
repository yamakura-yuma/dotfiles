# makura-agents

Shared Claude Code agent config, packaged so that any repo can opt into it.

It lives inside `dotfiles` because that is where it is maintained, but it is a
standalone APM package: depending on it never drags in anything dotfiles-
specific. The rule for what may live here is simply that it has to be true of
*every* repo that installs it — anything phrased as "in this repo" belongs in
`../\.apm/` instead.

## What you get

| | |
| --- | --- |
| `language` rule | Respond in Japanese, except where an existing file's language should win (commit messages, READMEs, code comments). |
| `guard-default-branch` hook | Refuses `git commit` / `git push` while HEAD is on the default branch, pointing you at a worktree instead. See below. |
| `guard-destructive-git` hook | Refuses the four git commands that destroy work which exists nowhere else: `reset --hard`, `clean -f`, whole-tree `checkout --` / `restore`, and `push --force`. `--force-with-lease` and `reset --soft` stay allowed. |
| `git-workflow` rule | Why those hooks exist, so an agent reads it before being blocked rather than after. |
| `testing` rule | Changes come with tests; don't report something as working that no test exercised; `.agent/verify.sh` is how a repo is verified. |
| `workspace-scope` rule | Keep edits inside the repo, and never hand-edit `~/.claude/settings.json` — five tools write to it. |
| `verifier` subagent | Runs the repo's verification and reports the raw result. It is given `Bash, Read, Grep, Glob` and **no `Edit` or `Write`**, so it has no way to turn a failure green. |
| `/verify` command | Runs the repo's verification through that subagent. |
| `/worktree <task>` command | Hands a task to a Claude worker in a fresh Orca worktree, including the "write your report to `.agent/report.md`" instruction. |
| `orca-orchestration` skill | A pointer at `orca skills get orchestration`, plus the conventions of this workspace. |
| `session-retro` skill | At the end of a session or after a correction, decide whether a durable lesson was learned and which `.apm/` it belongs in. |
| `skill-authoring` skill | How to add or improve a skill through apm, and whether a given piece of knowledge is a skill, an instruction, or a CLAUDE.md line. |
| `show-me` skill | Vendored from `humanlayer/skills` at a pinned commit: diagrams and standalone HTML explanations. |

Only the *name* `.agent/verify.sh` is shared. What it runs is always local — build
and test look different in every language — so the package defines the calling
convention and each repo supplies the contents.

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

Run those tests with `./makura-agents/tests/guards.sh`. They live outside
`.apm/` because apm deploys only `.apm/`, so a consuming repo gets the hooks
without the tests while the tests stay next to what they cover.

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
