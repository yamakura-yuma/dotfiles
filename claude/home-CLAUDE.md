## ここは coordinator

`~` はどのリポジトリにも属さない。ここでは実装しない。作業は話題ごとに Orca 上の
別 workspace（話題チャット）へ渡す。

```
~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/scripts/open-topic-chat \
  [--run <run_id>] [--repo <selector>] [--agent-cmd "<起動コマンド>"] --said "<ユーザーの原文>" \
  [--known "<わかっていること>"] [--guess "<推測（要確認）>"] <topic>
```

上のスクリプトが、coordinator の repo id を `orca worktree list` から引き、worktree
`chat-<topic>` の作成（`--setup inherit --no-parent`。ハーネスは repo の `orca.yaml` の setup が入れ、起動は setup の完了を待つ）、
Opus（`--model claude-opus-5-5`）の話題チャットの起動（plan モード）までを行う。起動コマンドは
worktree と一緒に開く最初のシェルに打つ（`Setup` 端末は除いて数える）。待機中のシェルと確かめられないときは
別に `terminal create` する。起動したあと、成功した `Setup` と使われていないシェルは閉じるので、
残る端末はエージェントだけになる（setup が失敗したときは `Setup` を残す）。コマンドは `--agent-cmd` で差し替えられる（引き継ぎ文は最後の引数に付く）。`~` は repo ではないので
`--repo id:<coordinatorRepoId>` を渡す（repo id は `orca worktree list --json` の id の `::` より前）。
引き継ぎ文は原文（`--said`）・わかっていること（`--known`）・推測（`--guess`）の 3 つに分ける。
掘り下げは話題チャットの仕事で、ここではしない。
開く前に `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/scripts/routing-facts` を流す。
`zone` が red（使用量が 90% 以上）のときだけ、ユーザーに聞いてから
`--agent-cmd "claude --model claude-sonnet-5-5 --effort high --permission-mode plan"` を渡す。

`~` と `~/coordinator` の元 checkout は **main chat**。話題の受付と全話題の状況の
まとめだけをして、`worker-start` も `run-create` もしない（main chat は Sonnet:
`claude --model claude-sonnet-5-5` で開く）。新しい話題は上の手順で
**話題チャット**（`chat-<topic>` worktree の別セッション）に渡す。新しいセッションは
人に開かせず Orca で開く。話題チャットが自分の Run を作り、ワーカーを出し、回収・解放・
後片付けまで行う。状況は `orca orchestration run-list --json`（目的の先頭が話題名）で
Run を引き、`worker-list --run <run_id>` と `orca terminal read` で読む。
話題が終わったら `orca terminal close --worktree path:<worktree のパス> --all` のあと
`orca worktree rm --worktree path:<worktree のパス>` で片付ける。

この main chat が Run を握っているなら、先に `check --wait` を止めて ack してから
`--run <run_id>` で渡す（話題チャットが `run-use --id <run_id>` で結ぶ。
Run を同時に 2 つのチャットが消費しない）。

`worktree create --prompt` は完了が inbox に届かず回収の手順に乗らないので使わない。

`~` はどのパッケージも読み込まないので、スキル名では案内しない。手順の正本は
ファイルで読む。coordinator は pstack-claude に切り替わる予定で、入口は `/p-mode`。

- `~/dotfiles/pstack-claude/.apm/skills/p-mode/SKILL.md`
- `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/SKILL.md`
  （冒頭の目次が各節の置き場を示す）
- `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/supervising-orca-workers.md`
  （main chat と話題チャットの役割、ワーカーの監督・回収・後片付け）

Orca 自身の手順書は `orca skills get orca-cli` と `orca skills get orchestration` が
実行中のバイナリと同じ版を返す。
