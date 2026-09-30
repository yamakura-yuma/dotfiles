## ここは coordinator

`~` はどのリポジトリにも属さない。ここでは実装しない。作業は話題ごとに Orca 上の
別 workspace（話題チャット）へ渡す。

```
orca worktree list --json                                  # coordinator の repo id は id の :: より前
orca worktree create --repo id:<coordinatorRepoId> --name chat-<topic> --setup skip --no-parent --json
(cd <worktree のパス> && apm install)                      # .claude/ は gitignore。ハーネスを入れる
orca terminal create --worktree path:<worktree のパス> --title <topic> \
  --command 'claude "$(cat <引き継ぎ文のファイル>)"' --json
```

`~` と `~/coordinator` の元 checkout は **main chat**。話題の受付と全話題の状況の
まとめだけをして、`worker-start` も `run-create` もしない。新しい話題は上の手順で
**話題チャット**（`chat-<topic>` worktree の別セッション）に渡す。新しいセッションは
人に開かせず Orca で開く。話題チャットが自分の Run を作り、ワーカーを出し、回収・解放・
後片付けまで行う。状況は `orca orchestration run-list --json`（目的の先頭が話題名）で
Run を引き、`worker-list --run <run_id>` と `orca terminal read` で読む。
話題が終わったら `orca terminal close --worktree path:<worktree のパス> --all` のあと
`orca worktree rm --worktree path:<worktree のパス>` で片付ける。

この main chat が Run を握っているなら、先に `check --wait` を止めて ack してから
引き継ぎ文に Run id を書く（話題チャットが `run-use --id <run_id>` で結ぶ。
Run を同時に 2 つのチャットが消費しない）。

`worktree create --prompt` は完了が inbox に届かず回収の手順に乗らないので使わない。

`~` はどのパッケージも読み込まないので、スキル名では案内しない。手順の正本は
ファイルで読む。coordinator は pstack-claude に切り替わる予定で、入口は `/p-mode`。

- `~/dotfiles/pstack-claude/.apm/skills/p-mode/SKILL.md`
- `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/SKILL.md`
  （main chat と話題チャットの役割、ワーカーの監督・回収・後片付け）

Orca 自身の手順書は `orca skills get orca-cli` と `orca skills get orchestration` が
実行中のバイナリと同じ版を返す。
