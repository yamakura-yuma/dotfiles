---
name: claude-session-to-html
description: Claude Code の会話（セッションの jsonl）を 1 枚の HTML にして、Windows 側のブラウザで開く。サブエージェントの会話も親の中に展開される。過去のセッションで何を言い、何を読んだかを見返したいとき、ワーカーや subagent の会話を人に見せたいときに使う。
---

# セッションの会話を HTML で開く

会話で何を言い、何を読んだか（サブエージェントを含む）を見る手段。所要時間や
ツール呼び出しの入れ子を見たいときは Grafana Tempo、ワーカーの進み具合は Orca の
ダッシュボードで、これではない。

```
scripts/session-to-html.sh <session.jsonl>                 # 変換して既定ブラウザで開く
scripts/session-to-html.sh --no-open -o out.html <session.jsonl>
```

- セッションは `~/.claude/projects/<cwd の / を - にしたもの>/<session-id>.jsonl`。
  新しい順は `ls -t ~/.claude/projects/<dir>/*.jsonl`。`subagents/agent-*.jsonl` は
  隣にあれば `claude-code-log` が自動で読む。
- 出力先の既定は `~/.cache/claude-session-html/<session-id>.html`。jsonl は読むだけで書き換えない。
- 外部へは送らない。`--gist` など送る option は足さない。
- `claude-code-log` は 1.6.0 に固定している。上げるときは `tests/check.sh` の期待値と
  `docs/claude-session-to-html.md` も合わせる。

詳しい経緯と既知の癖は `docs/claude-session-to-html.md`。
