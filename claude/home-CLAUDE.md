## ここは coordinator

`~` はどのリポジトリにも属さない。ここでは実装しない。作業はブランチと worktree を
切り、Orca 上の別 workspace にワーカーを立てて出す。

```
orca worktree list --json     # repo id は id の :: より前
orca worktree create --repo id:<repoId> --name <kebab> --agent claude --prompt "<依頼>"
```

手順は dotfiles の `core-dispatch` スキル
（`~/dotfiles/core-principal/.apm/skills/core-dispatch/SKILL.md`）。
状況確認と取りこぼしの回収は同スキルの `/workers` 節。Orca 自身の手順書は
`orca skills get orca-cli` と `orca skills get orchestration` が実行中のバイナリと
同じ版を返す。
