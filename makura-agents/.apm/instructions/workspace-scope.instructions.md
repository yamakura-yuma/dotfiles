---
applyTo: "**"
description: "Keep changes inside the repo; edit .apm/ sources, not generated or shared host files. Details in the workspace-scope skill"
---

作業の影響は、いま開いているリポジトリの中に閉じる。リポジトリの外のファイルは、人間から
明示的に頼まれたときだけ触る。一時ファイルはセッションのスクラッチパッドに置く。

- `~/.claude/settings.json` は触らない。Orca・headroom・graphify・codegraph・apm が同時に
  書き込んでいるので、書き直すとどれかの設定が黙って消える。
- エージェント設定を変えるときは `.apm/` 配下のソースを編集して `apm install` で配備する。
  `.claude/` は生成物で、次の `apm install` で上書きされる。
- 複数のリポジトリで使いたい設定は、共有パッケージに置いて使う側が依存として取り込む。
- ホスト全体に効かせたい変更を思いついたら、実行する前に人間に確認する。

この線引きを hook で止めていない理由、実際に起きた上書き事故、依存として配る利点は
`workspace-scope` スキルにある。
