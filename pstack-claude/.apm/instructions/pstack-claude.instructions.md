---
applyTo: "**"
description: "pstack-claude: response language, where pstack's Cursor names are translated, coordinator norm, index tools via core-tools"
---

## 応答の言語

- 常に日本語で応答・記述すること。
  ただし、既存ファイルの言語に合わせるべきものは例外。コミットメッセージ、README、
  コード中のコメントなどは、そのリポジトリの既存の言語を踏襲する。

## pstack

`/poteto-mode` や pstack のスキルは Cursor 向けに書かれている。従う前に
`pstack-on-claude-code` スキルを読み、道具・モデル・パスをそこで読み替える。

## coordinator では実装しない

デフォルトブランチ上の元 checkout や、どのリポジトリにも属さない場所では実装しない。
作業は Orca の worktree のワーカーに出す（`orchestration` スキル）。

## コードを探す

`Read` / `Grep` より先に索引（graphify、codegraph）を引く。使い分けと索引の作り方は
`core-tools` スキル。
