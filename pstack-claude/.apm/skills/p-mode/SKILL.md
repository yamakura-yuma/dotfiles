---
name: p-mode
description: The user's working style on top of poteto-mode - which of this harness's own skills to use in which situation, and Orca workers as the unit of parallel work. Use for /p-mode.
disable-model-invocation: true
---

# p-mode

Read `../poteto-mode/SKILL.md` in full first and follow it; the Skill tool
cannot load it, since it is user-invoked only. Its playbooks, principles and
reply rules stay in force. p-mode only adds the rows below. Where a row and
poteto-mode disagree, the row wins.

| When | Use |
|---|---|
| Finding or reading code | The `core-tools` skill: query an index before `Read` or `Grep` |
| Explaining a design, a structure or findings | Lead with a table or a diagram, then keep the prose short. Write the sentences per poteto-mode. For a diagram the user will open, the `show-me` skill; for an architecture diagram kept and edited in draw.io (`.drawio`), `drawio-skill` |
| Writing Japanese prose | `japanese-tech-writing`, then `humanizer-ja` in place of **unslop** |
| Stating how a tool or service behaves | Check the vendor's docs or `--help` first. Label each claim as documented or observed |
| About to write a new skill | The `find-skills` skill first. Take a well-known one as an apm dependency instead of copying it |
| Work that splits across branches or worktrees | An Orca worker per unit (`orchestration` skill), not a subagent. Fan-out inside one unit (`how`, `arena`, `swarm`, `interrogate`, delegates) stays on subagents as poteto-mode says |
| Any message to the main chat that names work, in any topic (implementation, research, documents) | Open a topic chat (`open-topic-chat`: a `chat-<topic>` worktree whose `orca.yaml` setup installs the harness, a session on Opus in plan mode) for a new topic without asking, with the hand-off split into the human's words, what is known and what is guessed; never ground or start a worker from the main chat; send a continuation to the topic's chat, answer a status question per topic from `worker-list` and `orca terminal read`, and put the conclusion first, ask the human to decide with `AskUserQuestion` choices, and end every reply with the topic checklist and 「次にあなたがすること」 (the "Reply shape" bullet of `pstack-on-claude-code`'s "Supervising Orca workers", Main chat) |
| In a topic chat, before its first `worker-start` | Ground the request with the human (`pstack-on-claude-code`'s `grounding.md`): plan mode, `grilling` for what to ask, `AskUserQuestion` for how. The row wins over poteto-mode's Never Block on the Human here: intent, target and done-criterion are product direction. Workers inside the approved brief are dispatched without asking |
| In a topic chat: dispatching, checking on or cleaning up Orca workers | One Run per topic chat (`run-use` when the main chat hands one over), each `check` Delivery acked once handled, waiting with `wait-worker-events` in the background (`pstack-on-claude-code`'s "Supervising Orca workers", Topic chat), and its Orca worker model table (role to model, effort, the implementation spec lines, the advisor block for the first half of the work, the review before the PR and its re-review cap), on top of the `orchestration` skill |
