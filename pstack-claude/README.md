# pstack-claude

[pstack](https://github.com/cursor/plugins/tree/main/pstack) (poteto-mode, MIT,
Lauren Tan) packaged for Claude Code under Orca. It is an alternative to
[`core-principal`](../core-principal/README.md): a repo depends on one or the
other, never both, so the two harnesses can be compared on the same task
without leaking into each other.

```yaml
dependencies:
  apm:
  - git: https://github.com/yamakura-yuma/dotfiles.git
    path: pstack-claude
    ref: <commit>
```

Then `/poteto-mode <task>` in Claude Code.

## What is upstream and what is ours

Upstream, pinned to one commit and never edited: every pstack skill and agent,
plus `deslop`, `control-ui` and `control-cli` from `cursor-team-kit`, which
poteto-mode calls by name. Also Orca's `orca-cli` and `orchestration`, and
`humanizer-ja`, and the pieces in the next section's table.

Ours, kept as thin as possible so that bumping `ref` in `apm.yml` stays the
whole upgrade:

| | |
|---|---|
| `pstack-on-claude-code` skill | Reads pstack's Cursor names as Claude Code and Orca ones: tools, Bugbot, models, paths, and which playbooks hand parallel work to Orca |
| `pstack-claude` rule | Always loaded: reply in Japanese, read the overlay before pstack, the coordinator norm, index tools via `core-tools` |
| `guard-coordinator-edit` hook | Refuses file edits in a coordinator workspace. The decision (`lib/coordinator-workspace.sh`) is a byte-for-byte copy of core-principal's, checked by `tests/check.sh` |

## What is taken from core-principal

Only what pstack has no counterpart for. Published skills are depended on at
the same git, path and ref as `core-principal/apm.yml`; core-principal's own
files are copied. `tests/check.sh` fails if either drifts.

| Taken | What it does | Closest pstack piece, and why it is not the same job |
|---|---|---|
| `core-tools` skill (copy) | Which index to query: graphify for where to look, codegraph for verbatim source and call paths; creating an index; worktrees inherit none | None. pstack's `how` and `why` explore with subagents, not indexes |
| `guard-destructive-git` hook (copy) | Refuses git commands that lose unrecoverable work (`reset --hard`, force push, ...) | None. pstack only says it in prose |
| `guard-default-branch` hook (copy, points at `orchestration` instead of `core-dispatch`) | Refuses commits and pushes on the default branch | None |
| `find-skills` | Finds a published skill before one is written | `playbooks/authoring-a-skill.md` writes one; it does not search |
| `show-me` | Diagrams and standalone HTML to explain a design | `show-me-your-work` keeps a decision log, it does not draw |
| `japanese-tech-writing`, `cognitive-rhythm-writing` | Norms and rhythm for Japanese technical prose | `technical-writing` and `unslop` are written for English |
| `grill-me`, `grilling` | Interview the human to sharpen their plan | `interrogate` is a model panel reviewing code, not a questioning of the human |
| `to-questionnaire` | Turns an open decision into a questionnaire for someone else | None |
| `wait-what` | Re-pitches a reply that did not land | None |
| `writing-for-agents` | How to write skills, AGENTS.md and CLAUDE.md | `playbooks/authoring-a-skill.md` is the procedure; this is the prose norm it lacks |
| `handoff` | Compacts the conversation into a document for another agent | `pause-safely` stops and checkpoints the same agent's work; `session-pickup` is the receiving side |
| `orca-emulator`, `orca-emulator-android`, `computer-use`, `linear-tickets`, `orca-linear`, `orca-per-workspace-env` | Orca's own skills for simulators, desktop GUI, Linear and per-workspace environments | None. pstack's `control-ui` / `control-cli` drive browsers and terminals only |

Left out on purpose: `teach` (pstack ships one of the same name), the core-*
skills whose job pstack already does (`core-dispatch`, `core-retro`,
`core-harness`, `core-communication`), and ponytail. Installed as an always-on
norm it was never opened under poteto-mode; used only as `ponytail-review` on
architect's sketch it cut the most. See [`docs/ponytail.md`](docs/ponytail.md).

Whether each skill actually gets used is measured with `make skill-eval`
(`claude plugin eval` over the apm-deployed skills); findings are in
[`docs/skill-audit.md`](docs/skill-audit.md).

## Why not depend on core-principal

apm cannot deploy part of a package. Depending on core-principal for its
language rule and guard would bring every core-* skill and its published
skills along, which is exactly the mixing a comparison has to avoid. What this
environment needs is taken piece by piece instead: the language rule is a few
lines, Orca's dispatch procedure comes from Orca's own skill, and everything
else is the table above.

`/setup-pstack` is deployed but not used: it writes Cursor's rule directory.
The model table lives in the overlay skill.
