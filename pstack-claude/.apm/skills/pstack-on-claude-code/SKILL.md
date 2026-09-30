---
name: pstack-on-claude-code
description: Translation table for running pstack (poteto-mode and the skills it routes to) on Claude Code under Orca instead of Cursor - which tool, skill, model, path and forge to use wherever pstack names a Cursor one, and which playbooks hand parallel work to Orca. Read before following /poteto-mode or any pstack skill.
---

# pstack on Claude Code

pstack is written for Cursor. Its text is used unchanged; read it through this
table. When pstack names something on the left, do what the right says. Nothing
here overrides pstack's judgment, only its plumbing.
The user's own preferences on top of poteto-mode are the `p-mode` skill.

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
| **architect** Phase C (the synthesized sketch, before Phase D) | Run `ponytail-review` over the sketch as an adversarial reviewer, reading the sketch as the diff. Act on each `delete:` / `yagni:` finding before implementing, or state in one line why the requirement keeps it |
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

The table above is for subagents. An Orca worker is a separate launch: pass
`--model` (and `--effort`, which needs `--model`) to `orca orchestration
worker-start`, and name the model in one line when reporting the dispatch.

| Role | `--model` | `--effort` | Review before the PR |
|---|---|---|---|
| Coordinator (this session) | Opus 5.5 | — | — |
| Design worker: deciding the approach, research, root-causing, a setup across components | `claude-opus-5-5`; `claude-fable-5-1` when the user asks | omit (`high` if needed) | No |
| Implementation worker: a change whose approach is settled | `claude-sonnet-5-5` | `high` (`xhigh` if long or easy to get lost in) | Yes |
| Review | Opus 5.5, as the `completion-reviewer` subagent | — | — |
| Advisor (every session, on trial) | Fable, a host setting (dotfiles `docs/configuration.md`, "advisor") | — | — |

**Always pass `--effort high` to an implementation worker.** Per the official
model-config page, Sonnet 5.5 defaults to `medium`; `high` is for "work where
verification matters or edge cases are likely", and higher levels test more
edge cases and verify more before answering. Tests and verification are what
Sonnet alone dropped on dotfiles#19. Not `max`: the docs warn it overthinks.

**Keep live-state work off implementation workers.** Shell profiles,
clusters, systemd, `~/.claude/settings.json`: anything hard to undo is a design
worker's job, on Opus. If it must go to Sonnet, the spec names the verification
sandbox (a temp profile, a scratch `HOME`, a dry run). Sonnet with an advisor on
#19 wrote duplicates into the real profile.

**An implementation worker's spec adds these lines.** Sonnet alone on #19
missed each one.

- Completion criteria as a checklist, one `- [ ]` per condition
- "Write the root cause in the commit message and PR body" (why it broke, not
  what changed)
- "Add tests, following the repo's existing test layout and style"
- "Paste the verification commands and their results into the report file"
- The live-state operations it must not do, named ("do not edit `~/.bashrc`",
  "do not apply to the real cluster"), and where to verify instead
- "Before declaring completion, have the advisor confirm every completion
  criterion is met"
- The review-loop paragraph below, verbatim

**Review loop before the PR.** When an implementation worker judges its
criteria met, it gets reviewed **before** opening the PR. The limit is **3**
rounds (change only this number to change it). Paste into the spec, with the
limit filled in:

```
Review before the PR: once you judge the completion criteria met, and before
opening a PR, call the completion-reviewer subagent with the Agent tool in the foreground
(no run_in_background), passing
this spec verbatim and the round number. On verdict fail, fix every required
finding and call it again as the next round; optional findings are your call.
On pass, open the PR and send worker_done. If round <limit> still fails, do not
open a PR: write the remaining required findings to the report file and send an
escalation. Paste each round's reply verbatim into the report file.
```

A subagent (`.apm/agents/completion-reviewer.agent.md`, `model: opus`,
read-only) was the most reliable of the candidates. A coordinator-run loop
(dispatch a review worker, `send` the findings back) advances only while the
coordinator is awake to pull completions, so each round waits. It also puts a
second agent into a worktree whose implementer is still live. With a subagent,
the loop closes inside the implementer's session, and the fixer keeps its
context. The reviewer still has a fresh context that wrote no code, and it reads
the spec and the diff, not the whole conversation as the advisor does. Its one
weakness is being skipped, so on pickup the coordinator checks the report for a
passing round (see "Supervising Orca workers"). Design workers (Opus, Fable)
get no review loop.

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
| Worktree cleanup | Worktrees Orca created are removed with `orca worktree rm`, never `git worktree remove`, after the checks in "Supervising Orca workers" below |

Everything else is used as written.

## Supervising Orca workers

The `orchestration` skill is the procedure. These are the gaps it leaves that
cost us in practice.

- **Pick up completion without the notification.** `worker_done` can arrive
  late or never. When checking status, read the inbox (`orca orchestration
  check`), the worker's card comment (`orca worktree ps`) and its PR (`gh pr
  list --head <branch>`); a comment saying done or an open PR means it finished,
  so read its report. For an implementation worker (`claude-sonnet-5-5`), check the
  report for a `verdict: pass` round before releasing; if there is none, send it
  back to run the review loop.
- **Rebind the Run when fenced.** If `worker-start` or another call fails with
  `consumer_fenced` (it wants the coordinator terminal bound to the Task Run),
  run `orca orchestration run-use --id <run_id>` and retry. When filtering Orca
  output with jq or grep, keep `ok` and the error code visible; a filter that
  dropped them hid a failed launch.
- **Issues record leftovers only.** Instructions and completion go through
  Orca, never an Issue. Anything under a report's remaining problems that is
  not fixed on the spot becomes a `gh issue create` on the target repo; a
  one-line fix does not get an Issue.
- **When release is retained.** When `worker-release` returns
  `retained` because Orca judged the terminal user-owned (user_takeover), do
  not repeat or substitute release. Close with `orca terminal close --worktree
  <selector> --all`; if that returns `terminal_stop_unverifiable`, remove the
  worktree only after `orca terminal list --worktree <selector>` shows none and
  no OS process uses the worktree path.
- **Check for mounts before removing.** A dev container or other process that
  mounts the worker's worktree blocks cleanup; recreate it on the original
  checkout first, then remove the worktree.
