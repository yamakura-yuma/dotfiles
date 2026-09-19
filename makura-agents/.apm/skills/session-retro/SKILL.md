---
name: session-retro
description: >-
  Use at the end of a session, after a user correction, or after resolving a
  tricky bug, to decide whether a durable lesson was learned and where it
  should be recorded. Routes lessons to skills rather than letting CLAUDE.md
  grow.
---

# Session retrospective

CLAUDE.md should stay short: stack, layout, commands. It is loaded on every
prompt, so anything added to it is paid for on every prompt forever. That
makes it the wrong home for lessons learned. This skill routes lessons to
skills instead, so the knowledge base can grow without CLAUDE.md growing.

## When to trigger

- The user corrected an approach, pointed out a mistake, or stated a standing
  preference.
- A bug took real effort to track down and the root cause generalizes beyond
  this one instance.
- A review caught something worth remembering for next time.

Skip it for anything one-off, already covered by an existing skill, or that
wouldn't change future behavior.

## What to do

1. State the lesson as one durable, generalizable sentence: the situation,
   what went wrong or what was preferred, and the correct behavior going
   forward. If you can't write that sentence, there is no lesson yet.
2. Decide where it belongs, in this order:
   - An existing skill already covers the topic → append to that skill's
     `references/` file, or to its `SKILL.md` body if it has no `references/`
     yet.
   - No skill covers it, but it is **true of every repository** → a new skill
     in `makura-agents/.apm/skills/`.
   - No skill covers it and it is specific to this repository → a new skill
     in this repo's own `.apm/skills/`.
   Use the `skill-authoring` skill for the two "new skill" cases.
3. Write it as a short bullet naming the concrete scenario it applies to, not
   a vague principle. "Prefer clarity" teaches nothing; "when apm rejects a
   symlinked apm.yml, copy the file instead" does.
4. Redeploy with `apm install --target claude` and commit the source change.

The "true of every repository?" question is the same one that decides what may
live in `makura-agents` at all. Getting it wrong in the shared direction is the
expensive mistake: it pushes a rule onto repos it does not fit.

Do not add the lesson to `CLAUDE.md`. Being tempted to is the signal that it
should be a skill, or a `references/` entry in an existing one.
