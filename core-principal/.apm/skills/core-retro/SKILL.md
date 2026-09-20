---
name: core-retro
description: >-
  Use at the end of a session, after a user correction, or after resolving a
  tricky bug, to improve the agent's environment for next time. Finds what
  slowed the agent down or let a mistake through, then routes each finding to
  an automated check, a skill, a rule, or the memory it should be promoted out
  of.
---

# Retrospective

A retrospective is not a summary of what happened. It proposes changes to the
agent's **environment** so the next run goes better: a check that would have
caught the mistake, a pointer that would have found the file sooner, a rule
that should never have been written.

Adapted from `mattpocock/skills`' `retro`. The categories are theirs; where
they assume a single `CODING_STANDARDS.md`, this harness spreads conventions
across several rules and skills, so the routing step is different.

## Steps

1. Load the `writing-for-agents` skill. Everything this retro proposes is
   text an agent has to read, so it is written under that style guide.

2. Read the primary sources for the session being reviewed — the transcript
   under `~/.claude/projects/<slugified-path>/*.jsonl` if it is not the
   current one, plus the diff. Default to the current session.

3. Look for candidates in the categories below.

4. Present them to the user in order of severity, and say plainly when a
   category turned up nothing. A retro that invents a finding per category is
   worse than a short one.

## Categories

- **Navigation** — how long did it take to find the right file? Would a
  pointer in a rule, a README or `CLAUDE.md` have shortened it? Remember that
  this harness's answer to navigation is an *index* (`graphify`, `codegraph`),
  so "the agent grepped for twenty minutes" may mean the index was missing or
  the rule telling it to use one did not fire. *Use when* the session spent
  real time locating something.

- **Automated checks** — could a check have caught the mistake? Read the
  repo's own entry point first: `make ci` here, and whatever the equivalent
  is elsewhere (`npm run check`, `just ci`, the CI workflow). A check that
  already exists but is unwired or silently broken is the finding, not a
  reinvention. A repo with no guardrail at all is itself a finding. *Use when*
  the agent made a mistake a check could have caught.

- **Conventions** — should a rule be added, clarified, or removed? Classify
  the violation first. A **mechanical** one — a fixed syntactic pattern, a
  banned API, a file-location rule — gets a deterministic check, full stop:
  a target under `make ci`, a linter rule, a hook. Default to building the
  check over writing the prose. Reserve a rule or skill for **judgement
  calls**: cross-file consistency, "matches the surrounding style," anything
  no check could substitute for. *Use when* a convention was violated and
  nothing caught it.

- **Rules and `AGENTS.md`** — the instructions in `.apm/instructions/` are
  loaded on every prompt, so they earn hard pruning. Is something there that
  belongs in a skill, or in a check? *Use when* the always-loaded set has
  grown.

- **Tool economy** — expensive or repeated tool calls that a different tool,
  a script, or a single command would have replaced. *Use when* the session
  burned context on mechanical work.

- **No-ops** — instructions that did not change behaviour. The honest test is
  the transcript: an instruction the agent visibly ignored is a no-op no
  matter how well written, and deleting it is the finding. *Use when* the
  rules have grown without evidence they bite.

- **Information access** — something the agent needed and could not reach:
  logs, a read-only credential, a schema, the output of a command it was not
  allowed to run. *Use when* the session guessed at something knowable.

## Routing a finding

Conventions here are not in one file. Where a finding lands decides whether it
is ever read:

| The finding is… | Goes to |
| --- | --- |
| Mechanical, decidable by a script | A target under `make ci` |
| A judgement call, true of every repo | `core-principal/.apm/` — a rule if violating it is always wrong, a skill if it is a procedure |
| A judgement call, true of this repo only | This repo's own `.apm/` |
| About how a specific tool is driven | The skill for that tool, or the tool's own published skill |
| Not yet articulable, or one-off | Leave it in memory; stop here |

Use the `core-harness` skill for anything that becomes a new rule or skill,
including the question of which of the two it is.

Getting the shared-versus-local call wrong in the shared direction is the
expensive mistake: it pushes a rule onto repos it does not fit. `core-principal`
is depended on by other repos, and apm cannot deploy part of a package.

## Memory is the draft; git is the record

Claude Code accumulates lessons on its own under
`~/.claude/projects/<slugified-absolute-path>/memory/`. That capture is
automatic and worth keeping — but the store is keyed by **absolute path**, and
that makes it the wrong place for a lesson to stay:

- **It does not survive a move.** Repos that moved from `~/<repo>` to
  `~/k8s-workspace/<repo>` left their memories behind at the old key. Those
  files still exist and are read by nothing.
- **A worktree is a different path**, so work done in one starts from an empty
  memory even though it is the same project.
- **It never leaves the host.** Anything orchestrated onto another machine
  starts without it.
- **Nobody else ever sees it.** It is not in any repo, so it is not reviewable
  and not shared.

Everything in a repo's `.apm/` has none of those problems: it moves with the
repo, is copied into every worktree, is pushed to every host, and shows up in
a diff. So let memory collect the draft, and promote from it.

Having promoted something, **delete the memory file it came from.** Leaving
both keeps paying the per-prompt cost for a duplicate, and guarantees one of
the two copies eventually goes stale. The promoted version is the record.

Finish by redeploying with `apm install --target claude`, running `make ci`,
and committing the source change.

## Taking stock

Worth doing occasionally, not every session:

```bash
ls -d ~/.claude/projects/*/memory/ 2>/dev/null
grep -h '^description:' ~/.claude/projects/*/memory/*.md 2>/dev/null
```

Each project directory name is a slugified absolute path. Read them against
the repos that actually exist on this host — a directory naming a path that is
gone is stranded, and its lessons are reaching nobody. Rescue anything still
true into the relevant repo's `.apm/` and delete the rest.

Then check the other direction: a memory whose content is already shipped as a
rule or skill is dead weight being re-read on every prompt. Confirm the
shipped version really covers it, then delete the memory.

## Implementation and review

All work goes through two stages, and they have different budgets.

The implementation agent is under **context pressure**: it explores, writes and
debugs. The review agent receives a diff, so it explores nothing and usually
writes nothing.

Conventions that need judgement therefore belong to review, not to
implementation. When a finding says "the agent should have known X about
style," ask whether the reviewer could have said it instead — that costs the
implementer nothing.
