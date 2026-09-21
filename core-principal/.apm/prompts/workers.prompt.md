---
description: "Report what dispatched workers are doing, and pick up anything that finished"
argument-hint: "[絞り込みたい対象（省略可）]"
---

いま走っているワーカーの状況を報告してください。絞り込み: $ARGUMENTS
（空なら全部。）

`core-dispatch` スキルの「3. 統合」と「報告の型」の手順です。完了は待ち受けでは
なく、Orca がセッションに注入してくる「You have N orchestration message」の通知を
きっかけに拾いに行きます。このコマンドはそれを人間から明示的に起こす入口であり、
詳細を求めるときの入口でもあります。

**自前の書式を作らないこと。** 公式の projection をそのまま整形して出します。

1. `orca worktree ps --json`
2. `orca orchestration worker-list --run <run_id> --include-remote --json`
3. `orca orchestration task-list --ready --brief --json`
4. `orca orchestration check --json` で未処理のメッセージを読む

出力は表ひとつ。列は **worktree / attention.categories / nextAction / outcome /
evidence / unresolved blocker**。`projection.attention.categories` と
`projection.nextAction` は公式の値をそのまま置き、言い換えない。`nextAction` が
`none` の行には打つべき argv が無いので、`liveness.reason` を書いて待ちます。
evidence には一次情報を短く（「make ci 緑」「2 コミット、ci 未実行」）。「順調です」
は evidence ではありません。

終わっているワーカーは、worker_done の `--report-path` が指すファイル（我々の規約
では worktree 直下の `.agent/report.md`）を Read して outcome / evidence /
unresolved blocker を埋めます。escalation / question があれば人に取り次ぎ、
落ち着いたワーカーは `orca orchestration worker-release` で解放します。ただし拒否
された・stale な完了では release しません。

生の JSON や端末出力は貼らず、実行手順の逐次説明もしません。異常があったときだけ、
表の下に理由を 1〜2 文足します。

`check` が空なら、ワーカーが消えたのではなく自分が Run から外れている可能性がある
ので、`orca orchestration run-current` で束縛を確かめること。`unverifiable` や
`missing_status` も死亡ではありません。殺したり再試行したりせず、`core-dispatch`
スキルの `references/orca.md`「ハンドルが stale になったとき」に従って引き直し、
生きているなら続きの指示で起こしてください。
