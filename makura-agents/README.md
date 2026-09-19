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
| `git-workflow` rule | Why that hook exists, so an agent reads it before being blocked rather than after. |
| `orca-orchestration` skill | A pointer at `orca skills get orchestration`, plus the conventions of this workspace. |
| `show-me` skill | Vendored from `humanlayer/skills` at a pinned commit: diagrams and standalone HTML explanations. |

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

## The default-branch guardrail

The hook exits 2, which blocks the tool call and hands its stderr back to the
agent as the reason. It is deliberately fail-open: exit 0 in Claude Code's
hook protocol means "no opinion", not "approved", so anything it cannot
evaluate confidently (no `jq`, not a repo, detached HEAD, unparseable payload)
falls through to exit 0.

Two details worth knowing before editing it:

- It reads `cwd` from the hook payload rather than `${CLAUDE_PROJECT_DIR}`,
  which stays pinned to where the session started and does not follow Claude
  into a worktree.
- It resolves the default branch from the local `refs/remotes/origin/HEAD`
  ref, never `git remote show origin` — that would put a network round trip in
  front of every Bash call.

To lift it, export `MAKURA_ALLOW_MAIN=1` before starting Claude Code. It is an
environment variable and not a marker file on purpose: hooks inherit Claude
Code's environment rather than the one a Bash tool call builds, so an agent
cannot grant it to itself by prefixing a command.
