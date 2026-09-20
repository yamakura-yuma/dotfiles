---
name: core-tools
description: Locating and understanding code: which index to query (graphify for where to look, codegraph for verbatim source and call paths), how to create an index when a directory has none, why a worktree inherits neither, and what the headroom proxy does to large Read and Grep output. Use when searching a codebase, when an index turns up empty, or when deciding whether Read/Grep is warranted.
---

# コードの探し方

コードを探すとき・理解するときは、まず **codegraph** と **graphify** を使うこと。
**Read / Grep / Glob は、これらで当たらなかったときの手段**とする。

この 2 つは役割が違うので、順番に意味がある。

## graphify — どこを見ればよいかを決める

`graphify-out/graph.json` があるディレクトリで使える。

```
graphify query "<質問>"        # 質問に関係するノードと辺を返す
graphify path "<A>" "<B>"      # 2 つのものの関係を辿る
graphify explain "<概念>"      # 1 つの概念とその周辺
```

返ってくるのはノードと辺、そして `src=<file> loc=L<n>` という位置情報で、**ソース本体
ではない**。つまりこれは「どのファイルの何行目を見ればよいか」を決める道具で、
grep を総当たりで撒く代わりになる。`graphify-out/wiki/index.md` があれば全体の地図として
先に読む。`GRAPH_REPORT.md` は広く見渡したいときだけ。

コードを変更したら `graphify update .` でグラフを更新する（AST のみ・API コスト無し）。
**`graphify-out/` は必ず `.gitignore` に入れる。** ソースから再生成できるマシンローカルな
派生物で、`cache/ast/` 以下にハッシュ名の JSON が大量にできるため、コミットすると差分が
ノイズだらけになる。`graphify update .` を初めて走らせたリポジトリでは、その場で
`.gitignore` を確認すること。

## codegraph — 中身を読む

`.codegraph/` があるリポジトリで使える。

```
codegraph explore "<シンボル名や質問>"
```

こちらは**逐語の、行番号付きの、現在のディスク上のソース**を、呼び出し経路つきで返す。
出力自体に「ここに表示したファイルを Read し直すな」と書いてあるとおり、Read の代わりに
なる。grep では追えない動的ディスパッチの経路も出る。MCP ツールが使えるなら
`codegraph_explore`、無ければシェルの `codegraph explore` で同じ結果が得られる。

## 索引が無いディレクトリでは、作ってよい

索引はディレクトリ単位で存在する。**git worktree は元のチェックアウトの `graphify-out/`
や `.codegraph/` を引き継がない**ので、worktree で作業するときは「メイン側にあるから
使えるはず」と決めつけず、まず存在を確認すること。

無ければ `codegraph init` や `graphify update .` で初期化してよい。許可を求める必要は
ない。`~/.claude/CLAUDE.md` の CodeGraph 節には「indexing is the user's decision」と
書かれているが、あれはインストーラが書き込む定型文で、このリポジトリの方針が優先する。
初期化したら、上のとおり `graphify-out/` が `.gitignore` に入っているかだけ確認する。

## Read / Grep を使ってよいとき

- 索引を作るほどでもない、単発の文字列探しのとき。
- graphify / codegraph で探して当たらなかったとき。
- **編集やデバッグのために、特定の行の正確な現在内容が要るとき。** グラフは前回の更新
  時点のスナップショットなので、書き換える直前は必ず現物を読む。

## headroom — 探索の道具ではない

headroom は `ANTHROPIC_BASE_URL` 経由で全セッションが通る最適化プロキシで、大きなツール
出力を `[N words compressed to M ... hash=...]` に置き換える。検索に使うものではないが、
上の優先順位を裏から支えている。**巨大な grep 結果や全文 Read は圧縮されて読めなくなる
おそれがあり、しかも `headroom_retrieve` でのハッシュ復元は当てにならない**
（同一セッション内の約 40 分前のハッシュが `Content not found. It may have expired.` で
失敗した実測がある）。範囲を絞った問い合わせのほうが、安上がりである以前に確実である。
長い結果が後から要るなら、ディスク上のファイルに書いて読み直すこと。
