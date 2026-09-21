---
description: "Report what dispatched workers are doing, and pick up anything that finished"
argument-hint: "[絞り込みたい対象（省略可）]"
---

いま走っているワーカーの状況を報告してください。絞り込み: $ARGUMENTS
（空なら全部。）

`core-dispatch` スキルの「3. 統合」の手順です。完了は待ち受けではなく、Orca が
セッションに注入してくる「You have N orchestration message」の通知をきっかけに
拾いに行きます。このコマンドはそれを人間から明示的に起こす入口で、取りこぼしの
回復口でもあります。`check` が空なら、ワーカーが消えたのではなく自分が Run から
外れている可能性があるので、`orca orchestration run-current` で束縛を確かめること。

1. `orca worktree ps --json` と `orca orchestration check --json`
2. 終わっているワーカーは、その worktree 直下の `.agent/report.md` を Read して
   結果を報告する。チャットの要約ではなくファイルが正本。
3. escalation / question があれば人に取り次ぐ
4. 落ち着いたワーカーは `orca orchestration worker-release` で解放する

報告は表で、1 ワーカー 1 行。名前・リポジトリ・ブランチ・状態・次にすべきこと。

止まっているように見えても、`unverifiable` や `missing_status` は死亡ではありません。
Orca 再起動でハンドルが変わっただけのことが多いので、殺したり再試行したりせず、
`core-dispatch` スキルの `references/orca.md`「ハンドルが stale になったとき」に従って
引き直し、生きているなら続きの指示で起こしてください。
