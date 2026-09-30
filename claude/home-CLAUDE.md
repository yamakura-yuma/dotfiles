## ここは coordinator

`~` はどのリポジトリにも属さない。ここでは実装しない。作業はブランチと worktree を
切り、Orca 上の別 workspace にワーカーを立てて出す。

```
orca worktree list --json     # repo id は id の :: より前
orca worktree create --repo id:<repoId> --name <kebab> --agent claude --prompt "<依頼>"
```

`--prompt` には依頼、完了条件、報告先 `~/.claude/worker-reports/<name>.md` を書く。
`worker-start` で Run に載せて監督する場合も同じ。

`~` はどのパッケージも読み込まないので、スキル名では案内しない。手順の正本は
ファイルで読む。coordinator は pstack-claude に切り替わる予定で、入口は `/p-mode`。

- `~/dotfiles/pstack-claude/.apm/skills/p-mode/SKILL.md`
- `~/dotfiles/pstack-claude/.apm/skills/pstack-on-claude-code/SKILL.md`
  （ワーカーの監督・回収・後片付け）

Orca 自身の手順書は `orca skills get orca-cli` と `orca skills get orchestration` が
実行中のバイナリと同じ版を返す。
