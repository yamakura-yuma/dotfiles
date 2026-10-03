# Grounding a topic before the first worker

The topic chat grounds the request with the human before its first
`worker-start`: what the human actually asked, why, for what, and in which
words. The main chat does not ground; workers do not ground (they `ask` when a
premise breaks).

## Order

1. Start in plan mode (`open-topic-chat` launches with `--permission-mode
   plan`). Before approval: read files and glossaries, run read-only `orca`
   (`run-current`, `worker-list`, `check --peek`), and `run-use` a handed-over
   Run. Never `run-create`, `worker-start` or `send` to a worker.
2. Read the hand-off's three parts. Every line under 「推測（要確認）」 is a
   question until the human confirms it.
3. Look terms up before asking (see "Terms").
4. Ask in the `grilling` skill's rounds: it decides what to ask (the frontier,
   a recommended answer, facts you look up yourself). Deliver each round with
   `AskUserQuestion`, at most four questions per call, the recommended answer
   as the first option marked "(Recommended)". Never list questions or options
   in reply text.
5. Depth is yours to choose. A one-line topic needs one or two lines: the
   original words, the goal, the completion criterion. A topic that starts from
   an Issue ("Run an Issue" in `supervising-orca-workers.md`) whose body fills all five items of
   `issue-template.md` skips steps 3 and 4: write the brief from the Issue, and
   the human's naming of it is the original words. A missing item is grounded as
   above. Step 6 stays: the Issue's author may have been an earlier session, so
   the human approves the brief once.
6. Check the checklist below, then write the brief (template below) as the
   plan and call `ExitPlanMode`. That approval is the brief's approval; do not
   ask "is this plan ready?" with `AskUserQuestion`.
7. After approval, write the plan verbatim to
   `~/.claude/worker-reports/<topic>-brief.md` with
   `状態: ユーザー承認済み v1（<date>）`, then create or bind the Run and
   dispatch.

## Question tool

- Claude Code: `AskUserQuestion`. If it is not in your tool list, load it with
  `tool_search_tool_regex` (pattern `AskUserQuestion`): the headroom proxy
  defers it server-side, so Claude Code's `ToolSearch` cannot find it.
- GitHub Copilot: `vscode/askQuestions` in VS Code, `ask_user` in Copilot CLI.
- If no question tool loads, do not ask in text. Stop, tell the human in one
  line that the question tool is missing, and wait.
- Workers never use these; they use `orca orchestration ask`.

## Checklist

| # | Item | Met when |
|---|---|---|
| 1 | Original words | Quoted, not paraphrased |
| 2 | Question or request | A question ("is there a tool that…?") was not rewritten into work ("apply X to every repo"); the human said whether an answer alone ends it |
| 3 | Goal | One sentence, in the human's terms |
| 4 | Target | Repos, files and scope named; "all" only if the human said so |
| 5 | Done | An observable completion criterion |
| 6 | Means | Tools and methods to use or avoid were agreed, not assumed |
| 7 | Terms | Key terms match a glossary, or the definition was agreed |
| 8 | Guesses | Every 「推測（要確認）」 line confirmed, or the human left it to you |
| 9 | Out of scope | What not to do or stop is written down |
| 10 | Approved | `ExitPlanMode` approved the brief |

Rows that do not apply read 「該当なし」.

## Terms

Before asking what a word means, look in this order and cite what you find:
the target repo's `CONTEXT.md`, `docs/`, README and ADRs; dotfiles `docs/`;
`~/knowledge-base/docs/src/`; the auto-memory files. Ask only about terms that
are missing or defined two ways, and ask the human to confirm a found
definition rather than to supply one. Hand a heavy search to an `Explore`
subagent.

## Brief template

```markdown
# 合意書: <topic>

状態: ユーザー承認済み v<n>（<date>[、v<n-1> から <変更点>]）

## ユーザーの原文
## 目的
## 合意した内容
## 用語
| 語 | 意味 | 出典 |
## 対象
## 除外すること・制約
## ワーカーが詰めること
## 進め方
```

## Spec header

Every worker spec starts with:

```markdown
## 合意書（最初に読む。正本）
`~/.claude/worker-reports/<topic>-brief.md`（v<n>）を全文読み、その「合意した内容」を前提に作業する。
合意と矛盾する作業はしない。合意に無理があると判断したら、作業を進める前に `question` で返す。
```

Do not copy the brief into the spec.

## When the brief changes

- Small (the worker's scope stays): edit the brief, bump the version, and
  `orca orchestration send --to dispatch:<dispatch_id> --subject "[brief v<n>]
  <change>" --body "<diff>"`. A worker reads follow-ups only at its
  checkpoints, so this is not immediate.
- Large (target, completion criterion or means change): edit, bump, get the
  human's approval again, then `worker-stop` and dispatch a new spec.
- A worker's `question` that shows the brief is wrong: ask the human with
  `AskUserQuestion`, fix and bump the brief, then `reply --id <msg_id>` with
  the new version (small) or with "stopping" and re-dispatch (large). The
  worker resumes its `ask` by message ID if it timed out meanwhile.
