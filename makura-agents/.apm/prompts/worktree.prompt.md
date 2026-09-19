---
description: "Hand a task to a Claude worker in a fresh Orca worktree"
argument-hint: "<ワーカーにやらせる作業>"
---

次の作業を、Orca の新しい worktree 上のワーカーに任せてください。自分でこの作業を
始めないこと。

作業: $ARGUMENTS

手順:

1. 作業内容から短い kebab-case の名前を決める（`--name` は必須）。
2. ワーカーに渡すプロンプトを組み立てる。**次の 2 点は必ず含めること。**
   - 作業内容と、完了条件
   - 「終わったら worktree 直下の `.agent/report.md` に、やったこと・検証結果・残って
     いる問題を書くこと。チャットの要約ではなくこのファイルが報告の本体になる」
3. 起動する:

   ```
   orca worktree create --name <name> --agent claude --prompt "<上で組み立てたプロンプト>"
   ```

4. `orca orchestration check --wait` で終了を待つ。
5. 終わったら、チャット上の要約ではなく `.agent/report.md` を Read して結果を確認する。

報告をファイルに書かせるのは、長時間のオーケストレーションでは最適化プロキシがツール
出力を圧縮し、ハッシュからの復元が期限切れで失敗することが実測されているため。詳しくは
`orca-orchestration` スキルを参照。手順そのものに迷ったら
`orca skills get orchestration` で本家の手順書を読むこと。
