#!/usr/bin/env bash
# UserPromptSubmit hook: in the coordinator workspace, put the dispatch norm in
# front of every message. Registered by ../dispatch-in-coordinator.json, which
# `apm install` merges into the consuming repo's .claude/settings.json.
#
# Why a hook and not a rule: `/worktree` only fires when a human types it, and
# a rule is advice the model weighs against the request in front of it. The
# norm has to arrive attached to the message itself, on every message, because
# the failure it prevents -- starting the work here instead of dispatching it
# -- happens in the first tool call.
#
# Contract differs from the PreToolUse guards: UserPromptSubmit is read for its
# stdout, not its exit code, and exit 2 here would cancel the human's prompt
# outright. So this script always exits 0 and simply prints nothing when it has
# nothing to say. The text goes in hookSpecificOutput.additionalContext, which
# Claude Code appends to the prompt as context.
set -uo pipefail

# Hooks inherit Claude Code's environment, which on some hosts has not picked up
# the Nix profile yet. jq and git both live there.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Same switch as the edit guard: once a human has said this session may work on
# main itself, injecting the dispatch norm every prompt is just noise.
if [ "${MAKURA_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
is_coordinator_workspace "$cwd" || exit 0

context="$(cat <<'EOF'
ここは **coordinator**、仕事を配る側のセッションです。**ここでは実装しません。**
Edit / Write / NotebookEdit は hook が拒否します。

このメッセージをまず 4 つに分類してください。

1. 新規の作業 → `core-dispatch` スキルに従い、worktree のワーカーに出す
2. 稼働中ワーカーへの追加指示 → `orca orchestration send` / `orca terminal send` で届ける
3. 状況確認 → `/workers`（`orca worktree ps` と inbox の要約）
4. オーケストレーション制御（止める・伝える・解放する）→ `core-dispatch` スキルの該当節

2〜4 と、対象リポジトリを特定するための 1 問だけが、ここで完結してよいことです。
調査・計画・コマンド実行はここでしてかまいません。書き込みだけが、ここではできません。

報告は `core-dispatch` スキルの「報告の型」に収めてください。俯瞰は
`worker-list` の `projection` と ready view から作り、報告は Task ごとに
outcome / evidence / unresolved blocker を名指しします。生の JSON や端末出力の
貼り付け、手順の逐次説明は書きません。
EOF
)"

jq -nc --arg ctx "$context" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
exit 0
