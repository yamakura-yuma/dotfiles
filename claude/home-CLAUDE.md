## ここは coordinator

`~` はどのリポジトリにも属さない。ここでは実装しない。作業はブランチと worktree を
切り、Orca 上の別 workspace にワーカーを立てて出す。

```
orca worktree list --json                                  # repo id は id の :: より前
orca orchestration run-current --json                      # セッションで Run は 1 つ。無いときだけ run-create
orca orchestration run-create --objective "<このセッションの作業>" --json
orca orchestration worker-start --run <run_id> --task-title "<題>" --spec "<依頼・完了条件・報告先>" \
  --worktree new-top-level --name <kebab> --repo id:<repoId> --agent claude --json
```

Run は 1 つで、2 本目以降も同じ Run に `worker-start` する（目的の違いは
`--task-title` とワーカー名）。`check` は束縛中の Run の最古の Delivery を ack するまで
返し続けるので、処理したら `check --ack <delivery_id>` で ack する。待つときは
`check --wait --types "worker_done,escalation,question" --timeout-ms <n> --json` を
`run_in_background` で動かす。

`--spec` には依頼、完了条件、報告先 `~/.claude/worker-reports/<name>.md` を書く。
`worktree create --prompt` は完了が inbox に届かず回収の手順に乗らないので使わない。
`consumer_fenced` で失敗したら（再起動で束縛が外れた）`orca orchestration run-use --id <run_id>`
で同じ Run に結び直す。付け替えには使わない。

`~` はどのパッケージも読み込まないので、スキル名では案内しない。手順の正本は
ファイルで読む。coordinator は pstack-claude に切り替わる予定で、入口は `/p-mode`。

- `~/dotfiles/pstack-claude/.apm/skills/p-mode/SKILL.md`
- `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/SKILL.md`
  （ワーカーの監督・回収・後片付け）

Orca 自身の手順書は `orca skills get orca-cli` と `orca skills get orchestration` が
実行中のバイナリと同じ版を返す。
