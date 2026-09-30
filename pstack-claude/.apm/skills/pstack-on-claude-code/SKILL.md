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
dropped them.

- Completion criteria as a checklist, one `- [ ]` per condition
- "Write the root cause in the commit message and PR body" (why it broke, not
  what changed)
- "Add tests, following the repo's existing test layout and style"
- "Paste the verification commands and their results into the report file"
- The live-state operations it must not do, named ("do not edit `~/.bashrc`",
  "do not apply to the real cluster"), and where to verify instead
- The advisor block and the review block below, verbatim

**Split the roles: the advisor covers the first half, the review covers
completion.** At completion the two overlap, and the review is both
independent (it doesn't know the history) and certain to run (the spec makes
the worker call it). What only the advisor can give is a word mid-task that
draws on the whole history: before settling an approach, or when stuck.

| | Advisor | `completion-reviewer` subagent |
|---|---|---|
| Receives | The whole conversation, forwarded automatically; shares the worker's assumptions | Only the prompt it is handed (spec and round number) |
| Does | Uses no tools; returns short advice | Reads the diff, runs verification, judges independently |

**Advisor block.** Paste this into the spec as is. It is the official text from
[Advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)
("Suggested system prompt for coding tasks" and "Trimming advisor output
length"), verbatim except that the completion items (the "When you believe the
task is complete ..." bullet and "and once before declaring done") are removed.
The last line is the official length trim, which the docs recommend placing in
the user message.

```text
You have access to an `advisor` tool backed by a stronger reviewer model. It takes NO parameters — when you call advisor(), your entire conversation history is automatically forwarded. They see the task, every tool call you've made, every result you've seen.

Call advisor BEFORE substantive work — before writing, before committing to an interpretation, before building on an assumption. If the task requires orientation first (finding files, fetching a source, seeing what's there), do that, then call advisor. Orientation is not substantive work. Writing, editing, and declaring an answer are.

Also call advisor:
- When stuck — errors recurring, approach not converging, results that don't fit.
- When considering a change of approach.

On tasks longer than a few steps, call advisor at least once before committing to an approach. On short reactive tasks where the next action is dictated by tool output you just read, you don't need to keep calling — the advisor adds most of its value on the first call, before the approach crystallizes.

Give the advice serious weight. If you follow a step and it fails empirically, or you have primary-source evidence that contradicts a specific claim (the file says X, the paper states Y), adapt. A passing self-test is not evidence the advice is wrong — it's evidence your test doesn't check what the advice is checking.

If you've already retrieved data pointing one way and the advisor points another: don't silently switch. Surface the conflict in one more advisor call — "I found X, you suggest Y, which constraint breaks the tie?" The advisor saw your evidence but may have underweighted it; a reconcile call is cheaper than committing to the wrong branch.

(Advisor: please keep your guidance under 80 words — I need a focused starting point, not a comprehensive plan.)
```

Claude Code's built-in advisor description still carries the completion item.
A spec cannot remove it, only steer away from it (dotfiles
`docs/configuration.md`, "advisor").

**Review before the PR.** When an implementation worker judges its criteria
met, it gets reviewed **before** opening the PR, fixes any required findings,
and gets re-reviewed. The re-review limit lives in one place only: "**once
more**" in the block below (change it there). If required findings remain at
the limit, they are findings open to interpretation: the worker does not open
the PR but returns them, and the coordinator asks the human.

```
Review before PR: once you judge the completion criteria met, and before
opening the PR, call the completion-reviewer subagent with the Agent tool in
the foreground (no run_in_background), passing this spec verbatim (no summary, no
omissions), the report file path, and the round number. On verdict pass, open the PR and send worker_done. On fail, fix
every required finding and call it once more (the re-review); optional
findings are your call. If the re-review passes, open the PR and send
worker_done. If it still fails, do not open the PR: write the remaining
required findings to the report file and send an escalation (or a question,
if you need an interpretation decided). Paste each round's reply verbatim into
the report file.
```

A subagent (`.apm/agents/completion-reviewer.agent.md`, `model: opus`,
read-only) was the most reliable of the candidates. A coordinator-run loop
(dispatch a review worker, `send` findings back) advances only while the
coordinator is awake to pull completions, so each round waits. It also puts a
second agent into a worktree whose implementer is still live. With a subagent,
the review closes inside the implementer's session, and the fixer keeps its
context. The one weakness is being skipped, so on pickup the coordinator checks
the report for a passing round (see "Supervising Orca workers"). Design workers
(Opus, Fable) get no review.

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
  back to run the review. If the re-review still failed and the worker
  escalated, show the remaining required findings to the human to decide.
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
