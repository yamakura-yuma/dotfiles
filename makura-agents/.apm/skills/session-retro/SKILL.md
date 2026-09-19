---
name: session-retro
description: >-
  Use at the end of a session, after a user correction, or after resolving a
  tricky bug, to decide whether a durable lesson was learned and where it
  should be recorded. Promotes lessons out of per-path memory into the repo,
  rather than letting CLAUDE.md grow.
---

# Session retrospective

CLAUDE.md should stay short: stack, layout, commands. It is loaded on every
prompt, so anything added to it is paid for on every prompt forever. That
makes it the wrong home for lessons learned. This skill routes lessons to
instructions and skills instead, so the knowledge base can grow without
CLAUDE.md growing.

## When to trigger

- The user corrected an approach, pointed out a mistake, or stated a standing
  preference.
- A bug took real effort to track down and the root cause generalizes beyond
  this one instance.
- A review caught something worth remembering for next time.
- Explicitly, through `/retro`. Nothing else fires this skill, so an end of
  session that nobody marks is an end of session where no lesson is kept.

Skip anything one-off, already covered by an existing skill, or that would not
change future behavior.

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

Everything in a repo's `.apm/` has none of those problems, because it moves
with the repo, is copied into every worktree, is pushed to every host, and
shows up in a diff. So: let memory collect the draft, and promote from it.

## What to do

1. State the lesson as one durable, generalizable sentence: the situation,
   what went wrong or was preferred, and the correct behavior going forward.
   If you can't write that sentence, there is no lesson yet.
2. Decide where it belongs, in order:
   - An existing skill or instruction already covers the topic → append to that
     skill's `references/` file, to its `SKILL.md` body if it has no
     `references/` yet, or to the instruction.
   - Nothing covers it, and it is **true of every repository** → a new
     instruction or skill in `makura-agents/.apm/`.
   - Nothing covers it, and it is specific to this repository → the repo's own
     `.apm/`.
   - It is genuinely one-off, or not yet articulable → leave it in memory and
     stop here.
   Use the `skill-authoring` skill for the two "new" cases, including the
   question of whether it is a skill or an instruction.
3. Write it as a short bullet naming the concrete scenario it applies to, not a
   vague principle. "Prefer clarity" teaches nothing; "when apm rejects a
   symlinked apm.yml, copy the file instead" does.
4. Redeploy with `apm install --target claude` and commit the source change.
5. **Delete the memory file you promoted from.** Leaving both keeps paying the
   per-prompt cost for a duplicate, and guarantees that one of the two copies
   will eventually be the stale one. The promoted version is the record.

The "true of every repository?" question is the same one that decides what may
live in `makura-agents` at all. Getting it wrong in the shared direction is the
expensive mistake: it pushes a rule onto repos it does not fit.

Do not add the lesson to `CLAUDE.md`. Being tempted to is the signal that it
should be an instruction or a skill.

## Taking stock

Worth doing occasionally, not every session:

```bash
ls -d ~/.claude/projects/*/memory/ 2>/dev/null
grep -h '^description:' ~/.claude/projects/*/memory/*.md 2>/dev/null
```

Each project directory name is a slugified absolute path. Read them against the
repos that actually exist on this host — a directory naming a path that is gone
is stranded, and its lessons are reaching nobody. Rescue anything still true
into the relevant repo's `.apm/` and delete the rest.

Then check the other direction: a memory whose content is already shipped as a
rule or skill is dead weight being re-read on every prompt. Confirm the shipped
version really covers it, then delete the memory.
