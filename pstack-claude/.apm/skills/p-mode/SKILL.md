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
| Dispatching, checking on or cleaning up Orca workers | `pstack-on-claude-code`'s "Supervising Orca workers" and its Orca worker model table (role to model, effort, the implementation spec lines, the advisor block for the first half of the work, the review and one re-review before the PR), on top of the `orchestration` skill |
