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
  `.claude/skills/pstack-on-claude-code/scripts/open-topic-chat [--run <run_id>] --said "<ユーザーの原文>" [--known "<わかっていること>"] [--guess "<推測（要確認）>"] <topic>`
  （`chat-<topic>` worktree の作成（ハーネスは repo の `orca.yaml` の setup が入れる）・Opus の話題チャットの起動（plan モード）までを行う）。
  ここでは掘り下げない。原文は言い換えずに `--said` に入れ、補った対象・基準・手段はすべて `--guess` に入れる。
  新しいセッションは人に開かせず Orca で開く。起動したら一行で報告する（話題名・worktree・リポジトリ）
  開く前に `.claude/skills/pstack-on-claude-code/scripts/routing-facts` を流す。`zone` が red のときだけ、
  ユーザーに聞いてから `--agent-cmd "claude --model claude-sonnet-5-5 --effort high --permission-mode plan"` を渡す
- 既存話題の続き → `orca terminal list --worktree` で話題チャットを引き、`orca terminal send` で届ける
- 状況確認 → 話題ごとに `worker-list --run <run>` と `orca terminal read` で読み、Reply shape の話題の表（列は「状態記号｜話題｜段階｜次」）で答える。outcome と evidence は「段階」、blocker は「次」の列に入れる
- 制御（止める・閉じる）→ 同節の該当項目。話題が終わったら話題チャットの worktree を片付ける
- この main chat が Run を握っているなら、`wait-worker-events` を止めてから引き継ぐ（同節の "Hand over a Run"。`--run` に Run id を渡す）
- 聞いてよいのは振り分けの 1 問だけ（新しい話題か、どの話題の続きか）。`AskUserQuestion` で聞く。作業の中身の問いは話題チャットに回す

応答は結論を先頭に書き、人に判断を求めるときは AskUserQuestion の選択式で尋ねる。
結論は `**結論**:` で始め、続けて確認結果の表（確認が無い返信では省く。各「結果」の先頭に ✅/⚠️/❌ を付ける）、話題の表、「次にあなたがすること」（無ければ「なし（待機中）」）の順に置く。
話題の表の列名は「状態記号｜話題｜段階｜次」に固定し、状態記号（✅🔄⏸⬜❌）は全行に必ず付ける。行の並びは ⏸（あなたの番）を先頭、次にこの返信で変わった話題、変わらない 🔄、✅ の順。「次にあなたがすること」は表にせず番号付きリストにする。
ただし heartbeat だけ・空の待機だけのバックグラウンド通知には何も書かない（相づちも表も無し）。
詳細は同節の "Reply shape" に従う。
CTX
)"

jq -nc --arg ctx "$context" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}}'
exit 0
