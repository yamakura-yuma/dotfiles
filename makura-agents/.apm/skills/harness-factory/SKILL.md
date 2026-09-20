---
name: harness-factory
description: >-
  Use when building or changing this agent harness — adding or improving a
  rule, skill, subagent, slash command or hook, taking a published skill as a
  dependency, or deciding whether a piece of knowledge should be a check, a
  rule, a skill, or nothing at all.
---

# Building the harness

The harness is the environment the agent works in: what is loaded every
prompt, what can be loaded on demand, what runs on its own, and what is
checked mechanically. This skill is how that environment gets changed.

## Search before writing

Before writing anything, search the published ecosystem with the
`find-skills` skill (`npx skills find "<keywords>"`). Where something fits,
**adopt** it — take it as an apm dependency — or **cite** it, pointing at it
instead of restating it. Author only the part that genuinely does not exist.

The point is to use knowledge other people have already refined, so "I looked
and found nothing" is a result to state, not a formality to clear.

Two specific cases worth checking every time:

- **The tool ships its own skill.** Orca, graphify and others publish skills
  for their own use. A summary maintained here is less accurate and does not
  follow upstream. Prefer the vendor's.
- **The subject is generic.** How to write a good skill, how to write for
  agents, how to review — these have strong published versions. Keep only
  what is specific to *this* environment.

References worth reaching for rather than rewriting:

- `writing-for-agents` (installed) — how any of this gets written: a rule, a
  skill, a `CLAUDE.md` line. Read it before authoring one.
- `obra/superpowers`, `skills/writing-skills` — skill authoring treated as
  test-driven development, with Anthropic's own guidance alongside.
- `mattpocock/skills`, `skills/in-progress/retro` — the upstream this repo's
  `retro` skill is adapted from.

## Where a piece of knowledge goes

Ask in this order, and stop at the first yes:

1. **Can a script decide it?** Then it is a check, not prose. Add a target
   under `make ci`. A rule that restates what a check enforces is a rule
   nobody needs, and prose is the weakest way to enforce anything mechanical.
2. **Must it hold whenever some glob matches, with no judgement about when?**
   An instruction (`.apm/instructions/`). Loaded every prompt.
3. **Is it a procedure that applies in a specific situation?** A skill. Costs
   nothing until that situation comes up.
4. **Is it a fact about the project — stack, layout, commands?** `CLAUDE.md`.
   Loaded every prompt, so keep it to a few lines.
5. **None of the above?** Do not write it.

The rule of thumb between 2 and 3: an instruction answers "what must always be
true", a skill answers "how do I do X when X comes up".

### An instruction is a pointer, not an essay

An instruction is loaded on every prompt whether or not it turns out to be
relevant, so it pays its cost constantly and earns hard pruning. Write it as
the imperative plus the branches that decide when to go further, and put the
reasoning, the procedure, the examples and the caveats into a skill of the
same name that the closing line points at. The rules here went from 12.7 KB of
always-loaded prose to 5.6 KB that way, with nothing dropped — the prose moved
rather than shrank.

Keep the instruction strong enough to act on by itself. A guardrail behind a
vague pointer only fires when the agent happens to open the skill, which is
not a guardrail. The test is whether the rule still forbids the wrong thing
when the skill is never read.

**`language` is the exception**, and it marks where the line falls: a rule has
to carry its own content when obeying it cannot wait for a skill to be opened.
By the time anything could be loaded, the response language is already wrong.

## Which package

`makura-agents/` is depended on by other repos, so anything in it is asserted
about all of them. apm cannot deploy part of a package, which means keeping
something out of that directory is the only way to hold it back.

- True of every repository → `makura-agents/.apm/`
- Specific to this repository → this repo's own `.apm/`

Erring toward the shared package is the expensive mistake: it pushes a rule
onto repos it does not fit, and the repos that receive it have no way to
decline.

## Everything goes through apm

`.claude/` is generated output. Always edit the source under `.apm/` and
redeploy; editing the deployed copy works until the next `apm install`
silently overwrites it.

Everything deploys into the repo's own `./.claude/`, never into `~/.claude/`.
Host-level files belong to the person using the machine: a tool once wrote
`~/.claude/settings.json.graphify-bak` over settings it did not own, and the
loss was invisible until something stopped working. Deploy into the repo, and
let the repo be installed.

Do not package agent config as a Claude Code plugin or marketplace entry
instead. Two distribution mechanisms writing the same `.claude/` tree means
neither one's record of what it owns stays true, and apm's record is what
`apm.lock.yaml` and the idempotent merge into `.claude/settings.json` rely on.
When an upstream project ships as a plugin, take its skills as apm
dependencies and leave its hooks behind.

| Source under `.apm/` | Lands at |
| --- | --- |
| `instructions/<name>.instructions.md` | `.claude/rules/<name>.md`, and compiles into `AGENTS.md` |
| `skills/<name>/` | `.claude/skills/<name>/` |
| `agents/<name>.agent.md` | `.claude/agents/<name>.md` |
| `prompts/<name>.prompt.md` | `.claude/commands/<name>.md`, i.e. `/<name>` |
| `hooks/*.json` | merged into `.claude/settings.json`, with ownership recorded in `.claude/apm-hooks.json` |

## Adding a skill

1. Pick a lowercase-hyphenated name that says **what it is for**, not what
   activity it is. A name like `skill-authoring` fits any repo and therefore
   describes nothing; `harness-factory` names the thing being built. If the
   name would make sense in someone else's repo unchanged, either the name is
   wrong or the content should have been a dependency.

2. Create `.apm/skills/<name>/SKILL.md` with frontmatter:

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

3. Write the body. Keep `SKILL.md` under roughly 500 lines, and push
   deep-dive content, checklists and examples into `references/`, `scripts/`,
   `assets/` or `examples/` subdirectories that the body points at.

4. Preview, audit, deploy:

   ```
   apm install --dry-run --target claude
   apm audit --file .apm/skills/<name>/SKILL.md
   apm install --target claude
   ```

5. Run `make ci` and commit the source — `.apm/skills/<name>/` and the updated
   `apm.lock.yaml`. Whether the generated `.claude/` is committed depends on
   the repo; follow what it already does.

Improving an existing skill is the same from step 3, preceded by the search in
"Search before writing" — an existing self-authored skill is a candidate for
replacement by a published one, not exempt from the question.

## Taking a dependency

Dependencies go in `makura-agents/apm.yml` under `dependencies.apm`, one entry
per skill with an explicit `ref` commit and an `alias`. A collection directory
is not a package: take `skills/<one-skill>` at a time.

Pin the commit rather than track a branch, and say in a comment why that
revision. Note that `apm update` will not move an explicit `ref` — bumping one
means editing the pin by hand.

## Hooks

A blocking hook has to earn its place one at a time. A hook that only nags
does not change behaviour; a hook that blocks does, and every blocking hook is
also a way for work to stop for a reason nobody can see. Prefer a check under
`make ci`, then an instruction, and reach for a hook only when the wrong thing
has to be impossible rather than discouraged.
