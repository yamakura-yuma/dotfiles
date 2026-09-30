# claude-session-to-html

Claude Code の会話を HTML にして Windows 側のブラウザで開く skill。知りたいことのうち
「③ 会話で何を言い、何を読んだか」を見る手段で、①ワーカーの進み具合（Grafana の
Orca orchestration）と②時間の使い方（Tempo のスパン木）はすでにある。

```
pstack-claude/.apm/skills/claude-session-to-html/scripts/session-to-html.sh <session.jsonl>
```

`apm install` すると `.claude/skills/claude-session-to-html/` に展開される。

## 中身

[claude-code-log](https://github.com/daaain/claude-code-log)（MIT）を
`uvx claude-code-log@1.6.0 <session.jsonl> -o <out>.html` で呼ぶだけ。バージョンは
`session-to-html.sh` の `CCL_VERSION` で固定している。

| 見えるもの | |
|---|---|
| 会話本文、ツール呼び出し、thinking、トークン | 読みやすい。タイムラインは種類別のレーン |
| サブエージェント | `subagents/agent-*.jsonl` を自動で読み、親の会話の中に展開する |
| 外部への通信 | 会話は出ない。タイムラインのボタンを押したときだけ描画ライブラリを unpkg から取る |

## 既知の癖

- Claude Code 2.1.285 が書く行種 `atis-latch` と `cost-state` は `unrecognized message type`
  と出て読み飛ばされる。会話の表示には影響しない。
- タイムラインではサブエージェントがエージェント別のレーンにならず、「Async result」の
  バーとして出る。エージェント別に並べたいなら Tempo を見る。

## ブラウザの開き方

Windows の既定ブラウザを、https の関連付け（`UrlAssociations\https`）から引いて直接起動し、
`wslpath -w` のパスを渡す。`.html` の関連付けや `explorer.exe`、`cmd /c start` は
使わない: この環境では `.html` の関連付けが古く、「アプリの選択」ダイアログで止まった。
`powershell.exe` が PATH に無ければ `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/` を使う。

## 確かめたこと

`make ci` の `pstack-claude/tests/check.sh` は `uvx`、`wslpath`、`powershell.exe` を
差し替えて、固定バージョン・引数・`--no-open`・開くときのパスを見る（オフライン）。
サブエージェントの展開は claude-code-log 側の挙動なので、実在のセッションを 1 つ変換して
手で確かめた（サブエージェントの Bash コマンド 10 行がすべて HTML に出た）。
