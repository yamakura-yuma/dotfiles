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
| `AskQuestion` | `AskUserQuestion`; if it is missing from the tool list, load it with `tool_search_tool_regex` (the headroom proxy defers it; `ToolSearch` cannot find it). In an Orca-dispatched worker, `orca orchestration ask` instead (the `orchestration` skill), since nobody sees a local prompt |
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
| Light work: a wording fix, a version bump, cleanup | `claude-sonnet-5-5` | `medium` | Yes |
| Review | Opus 5.5, as the `completion-reviewer` subagent | — | — |
| Advisor (every session, on trial) | Fable, a host setting (dotfiles `docs/configuration.md`, "advisor") | — | — |

**Pass `--effort high` to an implementation worker, `medium` to light work.** Per the official
model-config page, Sonnet 5.5 defaults to `medium`; `high` is for "work where
verification matters or edge cases are likely", and higher levels test more
edge cases and verify more before answering. Tests and verification are what
Sonnet alone dropped on dotfiles#19. Not `max`: the docs warn it overthinks.
Light work (a wording fix, a version bump, cleanup: no logic to get wrong) stays
on Sonnet's own default: pass `--effort medium`. It still gets the review before the PR.

**Usage changes the table only at red.** Before picking a launch, run
`.claude/skills/pstack-on-claude-code/scripts/routing-facts` and read `zone`
(it prints numbers and decides nothing).

| `zone` | Launch |
|---|---|
| green, yellow, orange | The table above, unchanged |
| red (session or weekly at 90% or more) | Everything on `claude-sonnet-5-5`: the topic chat (`--agent-cmd "claude --model claude-sonnet-5-5 --effort high --permission-mode plan"`) and design workers too. Do not start a new worker or topic chat before asking the human, with the zone and the launch you would use |
| unknown (no reading, or older than 30 minutes) | The table above, and ask the advisor first if the work is a design worker on Opus |

Opus and Sonnet share one weekly window, so a downgrade saves less than the
percentage suggests; only Fable has a window of its own, and the table does not
move work there on its own. Roles that assume Opus (the topic chat, the
`completion-reviewer`) drop to Sonnet only at red, and only after asking the
human; say in the report that they did.

**Ask the advisor in these cases, and only these.** Every other launch is
decided by the zone and the table.

1. `zone` is unknown and you are about to launch a design worker on Opus.
2. `zone` is orange or red and you cannot say in one line whether the work is
   design or implementation.
3. The launch names an agent that is not available (`agents[]` says
   `installed: false` or `signed_in: false`, with its `error`).
4. A downgrade would put an Opus role (topic chat, `completion-reviewer`) on
   Sonnet.
5. After `worker-start`, `worker-show` has `launch.effective` different from
   `launch.requested`; do not name the model from `requested` alone.

**Where the numbers come from.** `routing-facts` reads Orca's cached rate limits
(`orca account list --json`, a local call; Orca fetched them from Anthropic with
its own sign-in), then the snapshot Claude Code keeps in `~/.claude.json`, and
never the network. A reading older than `ROUTING_FACTS_MAX_AGE` seconds (default
1800) becomes `unknown`. `agents[].error` says why an agent is not `signed_in`:
Claude on API-key billing has no usage numbers, which is not the same as being
signed out.

**Keep live-state work off implementation workers.** Shell profiles,
clusters, systemd, `~/.claude/settings.json`: anything hard to undo is a design
worker's job, on Opus. If it must go to Sonnet, the spec names the verification
sandbox (a temp profile, a scratch `HOME`, a dry run). Sonnet with an advisor on
#19 wrote duplicates into the real profile.

**Every worker's spec, design or implementation, carries this line.** It
keeps the human's view current without a notification:

- "At the start of investigating, at the start of implementing, after the
  tests, and before the report, update the card with `orca worktree set
  --worktree active --comment "<one-line status>" --json` (no notification).
  Do not report a failure of this command. Before `worker_done`, add
  `--workspace-status in-review`."

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

`orchestration` skill is the procedure. These are the gaps it leaves that
cost us in practice. Two kinds of chat split the work: the **main chat** takes
topics in, and one **topic chat** per topic sees that topic through.

| | Main chat | Topic chat |
|---|---|---|
| Runs in | The coordinator's original checkout, where the UserPromptSubmit hook fires | Its own worktree `chat-<topic>` of the coordinator repo, opened by the main chat |
| Does | Intake, status across topics, closing finished topics | Grounds the request with the human in plan mode, then owns the topic's Run: `worker-start`, `wait-worker-events`, pickup, release, worker cleanup |
| Never | `worker-start`, `run-create`, `check` (bar handing over a Run it already holds) | Implement; its workers do |

- **Reply shape.** Every reply of either chat ends with two blocks. Write
  nothing at all, no acknowledgement and no checklist, when all a background
  return brought was heartbeats or an empty wait: reply only when a topic's
  state changed (`worker_done`, `escalation`, `question`, a `status`, a report file or a
  PR appeared, or the human wrote).
  1. A checklist, one line per topic (main chat) or per worker (topic chat):
     state symbol (✅ done, 🔄 working, ⏸ waiting on human, ⬜ not started, ❌
     failed), name, repo, one line of current state, PR link (「—」 until there
     is one). Take it from `worker-list` (the projection) and the Task list,
     never from memory. Add the chat's own remaining steps (merge, release,
     cleanup) as items.
  2. 「次にあなたがすること」: what needs the human's approval or decision,
     numbered; 「なし（待機中）」 when nothing does.
- The ledger is Orca's Task list. Keep no topic file of your own.

### Main chat

- **Open a topic chat for each new topic, without asking.** Sort each message
  into a new topic, a continuation, a status question or a control (stop,
  close). A new topic never starts a worker here. Pick a kebab `<topic>` and
  run `.claude/skills/pstack-on-claude-code/scripts/open-topic-chat
  [--run <run_id>] [--agent-cmd "<command>"] --said "<words>" [--known "<facts>"]
  [--guess "<guesses>"] <topic>`. It creates the worktree
  `chat-<topic>` of the coordinator repo (repo id read from `orca worktree
  list`, or `--repo <selector>`; `--no-parent` so unrelated topics
  do not nest). `--setup inherit` because `.claude/` and `apm_modules/` are gitignored, so
  a fresh worktree has no harness: the repo's `orca.yaml` setup installs it and the agent
  waits for that (`wait-for-setup`), so the script runs no `apm install` of its own. It starts the chat on the hand-off by typing
  `claude --model claude-opus-5-5 --permission-mode plan "<hand-off>"` into the
  one terminal Orca opened with the worktree, so the worktree has one terminal.
  It types only after `terminal list` shows that terminal alone and `terminal
  read` shows a shell prompt that has stopped moving; otherwise it opens a
  terminal of its own, as before (`terminal wait --for tui-idle` is for agent
  TUIs and times out on a shell, so it is not the check). `--agent-cmd` replaces
  that command; the hand-off is appended to it as the last argument. Whatever
  chooses the agent and model passes it there. It adds the topic chat's role (the hook and
  the edit guard stay silent in a child worktree, so that text is the only place
  the chat is told) and, with `--run`, the instruction to bind that Run. The
  hand-off has three parts, and the main chat does not ground: `--said` is the
  human's words verbatim, `--known` only what the human stated or the
  repository shows (the target repo included), `--guess` everything you
  inferred, for the topic chat to confirm. It prints the worktree path and the
  terminal handle.
  Opening the session is yours, not the human's. Before the script, run
  `.claude/skills/pstack-on-claude-code/scripts/routing-facts`; only at `zone`
  red does the chat's launch change: ask the human, then pass `--agent-cmd` with
  `claude --model claude-sonnet-5-5 --effort high --permission-mode plan` ("Models",
  above). Report in one line: topic, chat worktree, repo.
- **Session models.** `--model` outranks every `model` setting, so the script pins the
  topic chat to Opus and it stays Opus even where project settings name another
  model. The main chat is Sonnet: the human starts it with `claude --model
  claude-sonnet-5-5`. apm does not deploy a `model` setting into the
  consuming repo, so there is no file to put it in.
- **Hand over a Run you already hold.** A Run has one consuming terminal. Stop
  your background `wait-worker-events` first, ack what it returned, and only then
  run the script with `--run <run_id>`; the topic chat binds it with
  `run-use`. Your next consuming call fails `consumer_fenced`: leave it, since
  the main chat stays unbound.
- Continuation: `orca terminal list --worktree path:<path>` gives the topic
  chat's handle; deliver with `orca terminal send --terminal <handle> --text
  "<message>" --enter`.
- Control: to stop a topic, `send` the topic chat the instruction; it stops and
  releases its workers. To close a finished topic, see below.
- Status: one entry per topic, naming outcome, evidence and unresolved
  blocker. Find the topic's Run with `orca orchestration run-list --json`
  (its objective starts with the topic), then read `worker-list --run <run_id>
  --json` for the workers and `orca terminal read --terminal <handle>` for
  what the chat is doing. Unbound, `worker-list` without `--run` covers every
  Run.
- Ask only to route, with `AskUserQuestion`, one question at most: whether a
  message is a new topic or which topic it continues. Everything about the
  work itself (target, goal, means, terms) goes to the topic chat, even when
  the target repo is unclear; put it under `--guess`.
- **Close a finished topic.** The topic chat's hand-off message ("Hand a
  finished topic to the main chat", below) is the trigger; do not ask the human.
  Close only if all three hold, each read from the worktree `<path>` the message
  names: `worker-list --run <run_id> --terminal-state active` is empty; `git -C
  <path> status --porcelain` is empty and `git -C <path> log HEAD --not --remotes
  --oneline` shows no commit; nothing mounts the worktree ("Check for mounts
  before removing"). Then `orca terminal close --worktree path:<path> --all` and
  `orca worktree rm --worktree path:<path>`. If a check fails, ask the human with
  the failing output. If `terminal close` returns `terminal_stop_unverifiable`,
  proceed as "When release is retained" says. `worktree rm` also drops the local
  `chat-<topic>` branch unless Orca cannot prove it merged; report a retained
  branch to the human. Report in one line: topic, worktree removed.

### Topic chat

- **Ground before the first worker.** The chat starts in plan mode. Before the
  first `worker-start`, ground the hand-off with the human: look terms up
  first, ask in `grilling`'s rounds through `AskUserQuestion`, check the
  checklist, and present the brief as the plan for `ExitPlanMode`; after
  approval write it to `~/.claude/worker-reports/<topic>-brief.md` and start
  every spec with it. Until approval, only reads and `run-use` of a handed-over
  Run. If `AskUserQuestion` is not in the tool list, load it with
  `tool_search_tool_regex`; if it still does not load, do not ask in text:
  say in one line that the question tool is missing, and wait. Detail, the
  brief template and how to change a brief under a running worker:
  `grounding.md`.
- **One Run per topic chat.** First `orca orchestration run-current --json`.
  If the hand-off names a Run, `run-use --id <run_id>` (a new Run would strand
  that Run's `worker_done`); if nothing is bound, `run-create --objective
  "<topic>: <goal>" --json`. `orchestration` skill's "Canonical supervised
  loop" binds one Run; put each unit of the topic in its own Task
  (`--task-title`) and worker name, and add later workers to the same Run with
  `worker-start`. `check` only returns the bound Run's mail, so a Run per
  purpose, rebound with `run-use`, hides every other Run's `worker_done`.
- **Dispatch within the brief, without asking.** Once the brief is approved,
  every worker for the topic goes through
  `worker-start` into the Run (`--task-title` = unit, `--name` = kebab worker
  name); the Models table picks the worker: implementation change, design
  research, design documents, light work. Run `routing-facts` first and follow
  the zone rule under "Models"; check `worker-show` for `launch.effective` after
  the start. A worker that falls outside the brief needs the brief changed first.
  Report in one line: worker name, repo, model, zone.
  The chat's first start also starts `wait-worker-events` below; restart it after
  each return.
- **Ack what you have handled.** A consuming `check` replays the bound Run's
  oldest FIFO Delivery until it is acknowledged. Reply, validate the
  `worker_done` against its active Dispatch and decide the release first, then
  restart the wait with `wait-worker-events --ack <delivery_id>` (below),
  which acks and keeps waiting in one call.
  An un-acked Delivery keeps returning and queues newer ones behind it.
- **Triage is a report, not a worker.** A message with `type=status` and a
  `[triage]` subject comes from the scheduled PR/Issue triage. Read the report
  file named in its body (`~/.claude/worker-reports/triage/YYYY-MM-DD.md`) and
  put every item that needs approval (merge, close, start a worker, a human
  decision) under 「次にあなたがすること」; the merge, close or `worker-start`
  happens after the human approves it. It is sent to `@worktree:`, so every Run
  with a coordinator terminal in that worktree gets a copy with the same
  `thread_id`: handle each `thread_id` once, then ack every copy (other Runs'
  copies with `check --run <run_id> --ack <delivery_id>`). `wait-worker-events`
  wakes on `status` too, so it returns with the message.
- **Wait with `wait-worker-events`.** Run
  `.claude/skills/pstack-on-claude-code/scripts/wait-worker-events [--ack
  <delivery_id>]` with Bash `run_in_background`, and never a bare `check
  --wait`: a Run takes one waiter. It waits with `status` and `heartbeat` among
  the wake types, so Orca types no "You have N orchestration messages" into this
  terminal for either, and it acks heartbeat-only batches itself. It
  returns only with a batch holding something else (`status` included), or empty at its deadline;
  process the batch, then restart it with `--ack <delivery_id>`. An empty return
  is a checkpoint: restart it and write nothing. After three empty returns in a
  row, read `worker-list --include-remote --json` and follow each row's
  `projection.attention` and `nextAction`; write only if one needs action.
- **Heartbeats are not news.** If "You have N orchestration messages" still
  arrives and the batch holds only heartbeats, ack it and restart the wait
  without a word. Orca types that line into the terminal itself, not through a
  hook, whenever no live waiter covers the message type, so it cannot be
  switched off entirely.
- **Pick up completion without the notification.** `worker_done` can arrive
  late or never. When checking status, read the unacked inbox (`orca
  orchestration check --peek`), the worker's card comment (`orca worktree ps`)
  and its PR (`gh pr list --head <branch>`); a comment saying done or an open PR
  means it finished, so read its report. For an implementation worker (`claude-sonnet-5-5`), check the
  report for a `verdict: pass` round before releasing; if there is none, send it
  back to run the review. If the re-review still failed and the worker
  escalated, show the remaining required findings to the human to decide.
- **Rebind the same Run when fenced.** If `worker-start` or another call fails
  with `consumer_fenced` (a session restart dropped the binding; it wants the
  topic chat's terminal bound to the Task's Run), run `orca orchestration
  run-use --id <run_id>` for that same Run and retry. Besides the hand-over
  above, `run-use` is for nothing else. Runs
  left over from the old one-Run-per-purpose habit: `check --run <run_id>` each,
  process what is unacked and `check --run <run_id> --ack <delivery_id>` it, leave
  finished Runs alone (`--peek` reads without a `deliveryId`, so it cannot ack).
  When filtering Orca output with jq or grep, keep `ok` and the error code visible; a filter that
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
- **Hand a finished topic to the main chat.** The topic is finished when all of
  these hold, or when the human says it is over: every PR of the topic is merged
  or closed; `worker-list --run <run_id> --terminal-state active` is empty;
  `orca orchestration check --peek` shows no unacked delivery; every problem the
  reports left is an Issue. Write the final report first, then do this as the
  last action of the chat, since the main chat closes this terminal:
  `orca worktree list --json` gives the coordinator's original checkout (the row
  with `isMainWorktree` and the same `repoId` as this worktree; skip rows with a null one); `orca terminal list
  --worktree path:<that path>` gives the main chat's handle; `orca terminal send
  --terminal <handle> --text "Topic finished: <topic>. worktree: <path>. run:
  <run_id>. Close it as 'Close a finished topic' says." --enter`. Then stop.
- **Check for mounts before removing.** A dev container or other process that
  mounts the worker's worktree blocks cleanup; recreate it on the original
  checkout first, then remove the worktree.
