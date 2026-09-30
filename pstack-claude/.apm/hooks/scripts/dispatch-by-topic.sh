#!/usr/bin/env bash
# UserPromptSubmit hook: in the coordinator workspace, attach the topic routing
# rule to every message. Registered by ../dispatch-by-topic.json, which
# `apm install` merges into the consuming repo's .claude/settings.json.
#
# The rule itself lives in pstack-on-claude-code's "Supervising Orca workers";
# this only puts it in front of the message, because the failure it prevents
# (starting the work or a worker here, or asking before opening a topic chat)
# happens in the first tool call.
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
ここは coordinator の main chat。ここでは実装しないし、`worker-start` もしない
（Edit / Write は hook が拒否する）。話題の受付と全話題の状況のまとめだけをする。
このメッセージを分類し、`pstack-on-claude-code` の "Supervising Orca workers" 節、
Main chat に従う。

- 新しい話題 → 確認せず話題チャットを開く。kebab の話題名 `<topic>` で
  `orca worktree create --name chat-<topic> --setup skip --no-parent` →
  その worktree で `apm install` → `orca terminal create --worktree path:<path>
  --title <topic> --command "claude <引き継ぎ文>"`。新しいセッションは人に開かせず Orca で開く。
  起動したら一行で報告する（話題名・worktree・リポジトリ）
- 既存話題の続き → `orca terminal list --worktree` で話題チャットを引き、`orca terminal send` で届ける
- 状況確認 → 話題ごとに `worker-list --run <run>` と `orca terminal read` で読み、outcome / evidence / unresolved blocker
- 制御（止める・閉じる）→ 同節の該当項目。話題が終わったら話題チャットの worktree を片付ける
- この main chat が Run を握っているなら、`check --wait` を止めてから引き継ぐ（同節の "Hand over a Run"）
- 聞いてよいのは、話題が曖昧なときと対象リポジトリが決まらないときの 1 問だけ

どの応答も（短い相づち、バックグラウンド通知の処理後も）末尾に、話題ごとのチェックリストと
「次にあなたがすること」（無ければ「なし（待機中）」）を置く。同節の "Reply shape" に従う。
CTX
)"

jq -nc --arg ctx "$context" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
exit 0
