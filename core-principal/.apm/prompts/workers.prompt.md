---
description: "Report what dispatched workers are doing, and pick up anything that finished"
argument-hint: "[絞り込みたい対象（省略可）]"
---

いま走っているワーカーの状況を報告してください。絞り込み: $ARGUMENTS
（空なら全部。）

`core-dispatch` スキルの「3. 統合」の手順です。完了は待ち受けではなく、Orca が
セッションに注入してくる「You have N orchestration message」の通知をきっかけに
拾いに行きます。このコマンドはそれを人間から明示的に起こす入口であり、詳細を
求めるときの入口でもあります。

1. `orca worktree ps --json` と `orca orchestration check --json`
2. 終わっているワーカーは、その worktree 直下の `.agent/report.md` を Read する。
   チャットの要約ではなくファイルが正本。
3. escalation / question があれば人に取り次ぐ
4. 落ち着いたワーカーは `orca orchestration worker-release` で解放する。ただし
   拒否された・stale な完了では release しない。

出力は「報告の型」(b) の表ひとつに揃えること。前後に地の文を足さない。

| ワーカー | 状態 | 証拠 | 次 |
| --- | --- | --- | --- |

証拠の列には一次情報を短く置く（「2 コミット、ci 未実行」「make ci 緑、report.md
あり」）。「順調です」は証拠ではありません。異常があったときだけ、表の下に理由を
1〜2 文足します。

`check` が空なら、ワーカーが消えたのではなく自分が Run から外れている可能性がある
ので、`orca orchestration run-current` で束縛を確かめること。`unverifiable` や
`missing_status` も死亡ではありません。殺したり再試行したりせず、`core-dispatch`
スキルの `references/orca.md`「ハンドルが stale になったとき」に従って引き直し、
生きているなら続きの指示で起こしてください。
