---
name: orca-orchestration
description: 複数エージェントを worktree に分けて走らせるときの入口。Orca が持つ orchestration 手順書の場所と、このワークスペース固有の取り決めだけを書いてある。
---

# Orca でオーケストレーションする

**手順書はこのファイルには無い。** 監督ループの権限モデル、worker の義務、
`live` / `unverifiable` / `exited` の判定規則、復旧手順は Orca 本体が持っている。
作業を始める前に必ず取ってきて読むこと。

```
orca skills get orchestration
```

他に `orca-cli` / `orca-linear` / `computer-use` / `orca-emulator` なども
`orca skills get <name>` で取れる。ここに書き写すと必ず古くなるので、写さない。

## このワークスペース固有の取り決め

- **worktree は自分で掘らない。** `orca worktree create --agent claude --prompt "<指示>"`
  か `orca orchestration worker-start --worktree new-child` に任せる。Orca が worktree と
  エージェントの起動をまとめて面倒を見る。
- **プライマリはオーケストレーションに徹する。** 実作業は worktree 側のワーカーが行い、
  プライマリは `orca orchestration check --wait` で結果を待つ。
- **このリポジトリのデフォルトブランチでは commit / push できない。**
  guard-default-branch hook が exit 2 で拒否する。hook はプロジェクトスコープなので
  dotfiles を開いたセッションにしか効かず、他リポジトリのワーカーは対象外。
- **`wsl` 以外のホストにも撒ける。** `orca host list` で接続状態を確認し、
  `worker-start --on <environment>` で配置先を選ぶ。
