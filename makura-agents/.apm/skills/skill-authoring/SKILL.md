---
name: skill-authoring
description: >-
  Use when adding or improving a Claude Code skill in a repo that manages its
  agent config with apm, or when deciding whether knowledge belongs in
  CLAUDE.md versus a skill.
---

# Authoring skills through apm

`.claude/skills/` is generated output. Always edit the source under
`.apm/skills/` and redeploy; editing the deployed copy works until the next
`apm install` silently overwrites it.

Decide first **which** `.apm/` the skill belongs to:

- True of every repository → `makura-agents/.apm/skills/`, where every
  consumer picks it up.
- Specific to this repository → this repo's own `.apm/skills/`.

apm cannot deploy part of a package, so keeping something out of the shared
package is the only way to hold it back.

Everything goes through apm — skills, instructions, hooks, agents and prompts
alike. Do not package agent config as a Claude Code plugin or marketplace entry
instead. Two distribution mechanisms writing the same `.claude/` tree means
neither one's record of what it owns stays true, and apm's record is what
`apm.lock.yaml` and the idempotent merge into `.claude/settings.json` rely on.

What apm deploys where, for all five primitives:

| Source under `.apm/` | Lands at |
| --- | --- |
| `instructions/<name>.instructions.md` | `.claude/rules/<name>.md`, and compiles into `AGENTS.md` |
| `skills/<name>/` | `.claude/skills/<name>/` |
| `agents/<name>.agent.md` | `.claude/agents/<name>.md` |
| `prompts/<name>.prompt.md` | `.claude/commands/<name>.md`, i.e. `/<name>` |
| `hooks/*.json` | merged into `.claude/settings.json`, with ownership recorded in `.claude/apm-hooks.json` |

## Add a new skill

1. Pick a lowercase-hyphenated name and create
   `.apm/skills/<name>/SKILL.md` with frontmatter:

   ```yaml
   ---
   name: <name>
   description: >-
     Imperative, intent-focused description of when to load this skill.
     ("Use when...") Under 1024 characters.
   ---
   ```

   The description is the only part loaded up front, so it is what decides
   whether the skill ever activates. Describe the *situation*, not the
   contents.

2. Write the body. Keep `SKILL.md` itself under roughly 500 lines, and push
   deep-dive content, checklists and examples into `references/`, `scripts/`,
   `assets/` or `examples/` subdirectories that the body points at.

3. Preview the deployment without writing anything:

   ```
   apm install --dry-run --target claude
   ```

4. Scan for issues such as hidden Unicode:

   ```
   apm audit --file .apm/skills/<name>/SKILL.md
   ```

5. Deploy:

   ```
   apm install --target claude
   ```

6. Commit the source — `.apm/skills/<name>/` and the updated `apm.lock.yaml`.
   Whether the generated `.claude/skills/<name>/` is committed depends on the
   repo: some track it, others gitignore `.claude/` entirely and regenerate on
   clone. Follow whatever the repo already does.

## Improve an existing skill

Edit under `.apm/skills/<name>/`, then repeat steps 3–6.

## Look for an existing skill first

Before writing anything, search the published ecosystem with the `find-skills`
skill. Where something fits, take it as a dependency or follow its structure;
author only the part that genuinely does not exist yet. The point is to use
knowledge other people have already refined, so "I looked and found nothing" is
a result to state, not a formality to clear.

`writing-for-agents` is the reference for how any of this gets written — a
rule, a skill, a `CLAUDE.md` line. Read it before authoring one.

## Deciding where knowledge belongs

- **CLAUDE.md** — things true of the whole project that rarely change: stack,
  build/test/run commands, directory layout. It is loaded every prompt, so
  keep it short.
- **A skill** — anything procedural or checklist-like that only applies in a
  specific situation. It loads when that situation comes up and costs nothing
  otherwise.
- **An instruction** (`.apm/instructions/`) — a rule that must hold whenever
  its `applyTo` glob matches, with no judgement about when to load it. Use
  this for things that are wrong to violate, not for procedures.

The rule of thumb: if it answers "how do I do X when X comes up", it is a
skill. If it answers "what must always be true", it is an instruction.

### An instruction is a pointer, not an essay

An instruction is loaded on every prompt whether or not it turns out to be
relevant, so it pays its cost constantly and earns hard pruning. Write it as
the imperative plus the branches that decide when to go further, and put the
reasoning, the procedure, the examples and the caveats into a skill of the same
name that the closing line points at. The six rules here went from 12.7 KB of
always-loaded prose to 5.6 KB that way, with nothing dropped — the prose moved
rather than shrank.

Keep the instruction strong enough to act on by itself. A guardrail behind a
vague pointer only fires when the agent happens to open the skill, which is not
a guardrail. The test is whether the rule still forbids the wrong thing when
the skill is never read.

**`language` is the exception**, and it marks where the line falls: a rule has
to carry its own content when obeying it cannot wait for a skill to be opened.
By the time anything could be loaded, the response language is already wrong.
