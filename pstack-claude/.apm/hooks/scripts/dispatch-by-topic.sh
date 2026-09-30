#!/usr/bin/env bash
# UserPromptSubmit hook: in the coordinator workspace, attach the topic routing
# rule to every message. Registered by ../dispatch-by-topic.json, which
# `apm install` merges into the consuming repo's .claude/settings.json.
#
# The rule itself lives in pstack-on-claude-code's "Supervising Orca workers";
# this only puts it in front of the message, because the failure it prevents
# (starting the work here, or asking before dispatching) happens in the first
# tool call.
#
# UserPromptSubmit is read for its stdout, not its exit code, and exit 2 would
# cancel the human's prompt. So this always exits 0 and prints nothing when it
# has nothing to say. The text goes in hookSpecificOutput.additionalContext.
set -uo pipefail

case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Same switch as the edit guard: once a human has said this session may work on
# main itself, the routing rule is just noise.
[ "${MAKURA_ALLOW_MAIN:-}" = "1" ] && exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
is_coordinator_workspace "$cwd" || exit 0

context="$(cat <<'CTX'
ここは coordinator。ここでは実装しない（Edit / Write は hook が拒否する）。
このメッセージを分類し、`pstack-on-claude-code` の "Supervising Orca workers" 節、
"Start workers by topic, without asking" に従う。

- 新しい話題 → 確認せず、同じ Run に `worker-start`。kebab の話題名を
  `--task-title` と `--name` に使う。実装は実装ワーカー、調査・設計・文書は設計ワーカー。
  起動したら一行で報告する（話題名・リポジトリ・モデル）
- 既存話題の続き → `worker-list` の Task 題とワーカー名から引き、`orca orchestration send` で届ける
- 状況確認 → 話題ごとに outcome / evidence / unresolved blocker
- 制御（止める・解放する）→ 同節の該当項目
- 聞いてよいのは、話題が曖昧なときと対象リポジトリが決まらないときの 1 問だけ
CTX
)"

jq -nc --arg ctx "$context" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
exit 0
