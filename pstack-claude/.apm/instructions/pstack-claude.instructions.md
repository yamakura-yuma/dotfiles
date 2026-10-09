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
止める hook は無いので、この指示が唯一の歯止めになる。作業は話題ごとに `chat-<topic>` worktree の話題チャットに渡し、ワーカーはそこから出す
（`pstack-on-claude-code` の `supervising-orca-workers.md` の "Supervising Orca workers"）。

## マージ

completion-reviewer が合格したら、ワーカーが自分で `gh pr merge` する。必要なら `--admin`
も使ってよい（個人リポジトリで、ブランチ保護より速さを取るとユーザーが決めた）。
合格前・不合格のままのマージはしない（`pstack-on-claude-code`）。

## コードを探す

`Read` / `Grep` より先に索引（graphify、codegraph）を引く。使い分けと索引の作り方は
`core-tools` スキル。
