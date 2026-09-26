---
name: pstack-on-claude-code
description: Translation table for running pstack (poteto-mode and the skills it routes to) on Claude Code under Orca instead of Cursor - which tool, skill, model, path and forge to use wherever pstack names a Cursor one, and which playbooks hand parallel work to Orca. Read before following /poteto-mode or any pstack skill.
---

# pstack on Claude Code

pstack is written for Cursor. Its text is used unchanged; read it through this
table. When pstack names something on the left, do what the right says. Nothing
here overrides pstack's judgment, only its plumbing.

## Tools

| pstack says | On Claude Code |
|---|---|
| `Task` call | `Agent` tool. `subagent_type` values `poteto-agent` and `Comment Sicko` work as written (deployed to `.claude/agents/`) |
| `generalPurpose` | `general-purpose` |
| readonly subagent | `Explore` |
| `run_in_background: true` | same parameter on `Agent` |
| `AskQuestion` | `AskUserQuestion`. In an Orca-dispatched worker, `orca orchestration ask` instead (the `orchestration` skill), since nobody sees a local prompt |
| Cursor's `/loop` | Claude Code's `/loop` |
| **create-skill** (Cursor's authoring skill) | pstack's own `playbooks/authoring-a-skill.md`, with Claude Code's `SKILL.md` frontmatter (`name`, `description`) |

## Skills and services

| pstack says | On Claude Code |
|---|---|
| Bugbot, agentic security review | `/code-review` on the PR (and `/security-review` for the security pass). Triage its findings with pstack's `references/bugbot-triage.md` exactly as written for Bugbot |
| `deslop`, `control-ui`, `control-cli` from `cursor-team-kit` | Installed under the same names; use as written |
| `control-ui` against a browser surface | Orca's embedded browser (`orca-cli` skill) when a page must be driven by hand |
| **unslop** on Japanese prose | `humanizer-ja` |
| Cursor cloud agent | An Orca worker in its own worktree (`orchestration` skill) |
| Origin (`origin pr ...`) | Not installed; stay on `gh` as pstack's fallback says |

## Models

This replaces `~/.cursor/rules/pstack-models.mdc`; do not run `/setup-pstack`,
which writes Cursor's rule directory. Values are the `model` parameter of the
`Agent` tool. `inherit` means omit it.

```
feature, refactoring: sonnet
bug-fix: sonnet
perf-issue: sonnet
hillclimb: sonnet
judgment and prose: opus
hardest tasks: opus
how explorer: sonnet
how explainer: opus
why investigators: sonnet
why synthesizer: opus
reflect tooling: sonnet
reflect judgment, divergent, synthesizer: opus
arena runners: opus, sonnet, haiku
arena cross-judge pool: opus, sonnet
swarm workers: sonnet
architect runners: opus, sonnet, haiku
interrogate reviewers: opus, sonnet, haiku
```

Every panel is one model family. The panels still fan out, but they lose the
cross-vendor disagreement pstack counts on; say so when a panel's verdict is
unanimous.

## Paths

| pstack says | On Claude Code |
|---|---|
| `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/*.jsonl` (slug is the working directory with `/` as `-`) |
| `~/.cursor/skills/`, `.cursor/skills/` | `~/.claude/skills/`, `.claude/skills/` |
| `~/.cursor/plugins/` | `apm_modules/` of the consuming repo |

## Who runs parallel work

Orca owns parallelism across worktrees and supervision; pstack owns rigor
inside one session. In-session fan-out (`how`, `why`, `interrogate`,
`architect`, `arena`, `swarm`, a playbook's delegates) stays on `Agent`.

| Playbook | Under Orca |
|---|---|
| Orchestrate, Autopilot-full, Autopilot-stack | Keep pstack's briefs, standing orders and verdict gates. Each unit that outlives this session is an Orca worker (`orchestration` skill: dispatch, `check`, `worker_done`), not a subagent or cloud agent |
| Shipping | The per-PR verdict agent is a local `Agent` or an Orca worker; either way it must not have written the code |
| Babysit | As written, on `gh` and `/loop` |
| Pause safely | As written. In a dispatched worker, the resume note is also the worker report the preamble asks for |
| Session pickup | As written, with the transcript path above. For an Orca worker, read its report and `orca orchestration` history first |
| Worktree cleanup | Worktrees Orca created are removed with `orca worktree rm`, never `git worktree remove` |

Everything else is used as written.
