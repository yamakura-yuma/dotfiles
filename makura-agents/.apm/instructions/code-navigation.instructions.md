---
applyTo: "**"
description: "Query the index before Read/Grep; the code-navigation skill has the rest"
---

コードを探すとき・理解するときは、まず索引を引く。`Read` / `Grep` / `Glob` は、索引が
無いとき、索引で当たらなかったとき、編集する行の現物が要るときの手段とする。

- `graphify-out/` がある → `graphify query "<質問>"` で**どこを見るか**を決める
- `.codegraph/` がある → `codegraph explore "<シンボルや質問>"` で**逐語ソースと呼び出し
  経路**を読む

索引はディレクトリ単位で存在し、worktree は元のチェックアウトのものを引き継がない。
索引を作るかどうかは人間が決めることなので、`graphify` や `codegraph init` を自分の
判断で走らせない。

各ツールが何を返すか、索引が無いときの進め方、`graphify-out/` の扱い、headroom 下で
大きな出力が読めなくなる件は `code-navigation` スキルにある。
