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

Then `/poteto-mode <task>` in Claude Code, or `/p-mode <task>` for the same
with this harness's own skills and Orca workers slotted in ([`p-mode`](.apm/skills/p-mode/SKILL.md)).

## What each agent gets

`apm install` deploys to Claude Code, Codex and GitHub Copilot CLI. Only Claude
Code has been run; the other two columns are what lands on disk, checked with
`apm install --target claude,codex,copilot` in a scratch consumer.

| | Claude Code | Codex | Copilot CLI |
|---|---|---|---|
| Skills (all 72) | `.claude/skills/` | `.agents/skills/` | `.agents/skills/` (Copilot reads it) |
| Rule | `.claude/rules/` | Only after `apm compile --target codex`, which writes `AGENTS.md` | `.github/instructions/` |
| Subagents (`poteto-agent`, `Comment Sicko`, `completion-reviewer`) | `.claude/agents/` | `.codex/agents/*.toml` | `.github/agents/` |
| `guard-destructive-git`, `guard-default-branch` hooks | Yes | Yes (`.codex/hooks.json`). Codex asks to trust project hooks before they run | Deployed, but **Claude only**: Copilot's `preToolUse` sends `toolArgs`, not `tool_input`, so the scripts see no command and allow it |
| `guard-coordinator-edit` hook | Yes | Deployed, but **Claude only**: Codex edits with `apply_patch`, which has no `file_path` | Deployed, but **Claude only**, same reason as above |
| `dispatch-by-topic` hook (UserPromptSubmit) | Yes | Deployed, but **Claude only**: only checked on Claude Code | Deployed, but **Claude only**, same reason above |
| `pstack-on-claude-code` overlay | Yes | Deployed, but it maps Cursor's names onto **Claude Code only** | Same |
| `japanese-guard` hook (Stop) | Yes | Deployed to `.codex/hooks.json`, not run | Deployed as `agentStop`, not run |

Every upstream package is deployed to all three without being edited: what had
kept them Claude-only was the `targets: [claude]` on each dependency in
`apm.yml`, not anything upstream.

## What is upstream and what is ours

Upstream, pinned to one commit and never edited: every pstack skill and agent,
plus `deslop`, `control-ui` and `control-cli` from `cursor-team-kit`, which
poteto-mode calls by name. Also Orca's `orca-cli` and `orchestration`,
`humanizer-ja`, mizchi/explainer's `explainer`, `explainer-book` and
`first-reader` (reader-specific crash courses and chaptered material, checked by
their own scripts; the npm packages those scripts need go in the repository the
material lives in), and the pieces in the next section's table.

Ours, kept as thin as possible so that bumping `ref` in `apm.yml` stays the
whole upgrade:

| | |
|---|---|
| `pstack-on-claude-code` skill | Reads pstack's Cursor names as Claude Code and Orca ones: tools, Bugbot, models, paths, and which playbooks hand parallel work to Orca |
| `pstack-claude` rule | Always loaded: reply in Japanese, read the overlay before pstack, the coordinator norm, index tools via `core-tools` |
| `guard-coordinator-edit` hook | Refuses file edits in a coordinator workspace. The decision (`lib/coordinator-workspace.sh`) is a byte-for-byte copy of core-principal's, checked by `tests/check.sh` |
| `dispatch-by-topic` hook (UserPromptSubmit) | In the coordinator workspace, attaches the rule that opens a topic chat (a `chat-<topic>` worktree with its own session) per topic without asking, never a worker, and that every reply ends with a per-topic checklist and what the human does next (`pstack-on-claude-code`, "Supervising Orca workers"). Silent elsewhere. Replaces the `dispatch-in-coordinator` hook of core-principal, whose text points at core-dispatch |
| `open-topic-chat` script (`pstack-on-claude-code/scripts/`) | Opens a topic chat in one call: worktree `chat-<topic>` of the coordinator repo, `apm install` in it, a `claude --model claude-opus-5-5` session on the hand-off, optionally told to bind an existing Run (`--run`). Tested against stub `orca` and `apm` in `tests/check.sh` |
| `japanese-guard` hook | Sends an English final answer back to be rewritten in Japanese. Vendored unedited from [minorun365/claude-code-japanese-guard](https://github.com/minorun365/claude-code-japanese-guard) (Apache-2.0), which has no manifest to depend on; pin, thresholds and how to turn it off in [`docs/japanese-guard.md`](docs/japanese-guard.md) |

## What is taken from core-principal

Only what pstack has no counterpart for. Published skills are depended on at
the same git, path and ref as `core-principal/apm.yml`; core-principal's own
files are copied. `tests/check.sh` fails if either drifts.

| Taken | What it does | Closest pstack piece, and why it is not the same job |
|---|---|---|
| `core-tools` skill (copy) | Which index to query: graphify for where to look, codegraph for verbatim source and call paths; creating an index; worktrees inherit none | None. pstack's `how` and `why` explore with subagents, not indexes |
| `guard-destructive-git` hook (copy) | Refuses git commands that lose unrecoverable work (`reset --hard`, force push, ...) | None. pstack only says it in prose |
| `guard-default-branch` hook (copy, points at `orchestration` instead of `core-dispatch`) | Refuses commits and pushes on the default branch | None |
| `completion-reviewer` subagent (copy) | Opus reviews an implementation worker's change against its spec before the PR, with re-reviews capped in `pstack-on-claude-code` | pstack's Shipping verdict agent judges the PR after it is opened; this runs before, inside the worker |
| `find-skills` | Finds a published skill before one is written | `playbooks/authoring-a-skill.md` writes one; it does not search |
| `show-me` | Diagrams and standalone HTML to explain a design | `show-me-your-work` keeps a decision log, it does not draw |
| `drawio-skill` | Editable `.drawio` architecture diagrams kept in the repo and updated, not one-off HTML. Exports need the draw.io desktop CLI ([setup](../docs/setup.md)) | None. pstack draws nothing that outlives the reply |
| `japanese-tech-writing`, `cognitive-rhythm-writing` | Norms and rhythm for Japanese technical prose | `technical-writing` and `unslop` are written for English |
| `grill-me`, `grilling` | Interview the human to sharpen their plan | `interrogate` is a model panel reviewing code, not a questioning of the human |
| `to-questionnaire` | Turns an open decision into a questionnaire for someone else | None |
| `wait-what` | Re-pitches a reply that did not land | None |
| `writing-for-agents` | How to write skills, AGENTS.md and CLAUDE.md | `playbooks/authoring-a-skill.md` is the procedure; this is the prose norm it lacks |
| `ponytail-review` | Lists what a diff can delete: speculative abstractions, unused config, hand-rolled stdlib. Run on architect's sketch only | `interrogate`'s code-quality lens and architect's red flags judge structure; neither names a requirement nobody has yet as the thing to cut |
| `handoff` | Compacts the conversation into a document for another agent | `pause-safely` stops and checkpoints the same agent's work; `session-pickup` is the receiving side |
| `orca-emulator`, `orca-emulator-android`, `computer-use`, `linear-tickets`, `orca-linear`, `orca-per-workspace-env` | Orca's own skills for simulators, desktop GUI, Linear and per-workspace environments | None. pstack's `control-ui` / `control-cli` drive browsers and terminals only |

Left out on purpose: `teach` (pstack ships one of the same name), the core-*
skills whose job pstack already does (`core-dispatch`, `core-retro`,
`core-harness`, `core-communication`), and the rest of ponytail. Installed as an
always-on norm it was never opened under poteto-mode, and its reply and comment
rules contradict pstack's; see [`docs/ponytail.md`](docs/ponytail.md).

Whether each skill actually gets used is measured with `make skill-eval`
(`claude plugin eval` over agent-neutral cases); findings are in
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
