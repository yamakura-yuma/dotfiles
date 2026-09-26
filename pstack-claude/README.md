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
`humanizer-ja`.

Ours, kept as thin as possible so that bumping `ref` in `apm.yml` stays the
whole upgrade:

| | |
|---|---|
| `pstack-on-claude-code` skill | Reads pstack's Cursor names as Claude Code and Orca ones: tools, Bugbot, models, paths, and which playbooks hand parallel work to Orca |
| `pstack-claude` rule | Always loaded: reply in Japanese, read the overlay before pstack, the coordinator norm, index tools first |
| `guard-coordinator-edit` hook | Refuses file edits in a coordinator workspace. The decision (`lib/coordinator-workspace.sh`) is a byte-for-byte copy of core-principal's, checked by `tests/check.sh` |

## Why not depend on core-principal

apm cannot deploy part of a package. Depending on core-principal for its
language rule and guard would bring every core-* skill and its published
skills along, which is exactly the mixing a comparison has to avoid. The four
pieces this environment needs are small, so they are restated here instead:
the language rule and index bridge are a few lines each, Orca's dispatch
procedure comes from Orca's own skill, and the guard shares its decision code
with core-principal through a checked copy.

`/setup-pstack` is deployed but not used: it writes Cursor's rule directory.
The model table lives in the overlay skill.
