---
description: "Report what dispatched workers are doing, and pick up anything that finished"
argument-hint: "[絞り込みたい対象（省略可）]"
---

いま走っているワーカーの状況を報告してください。絞り込み: $ARGUMENTS
（空なら全部。）

`core-dispatch` スキルの「3. 統合」と「報告の型」の手順です。Run はこのセッションで
束縛した 1 つだけ（公式の「bind one Run」）。完了は `check --wait` の返りと Orca が注入
する「You have N orchestration message」の通知をきっかけに拾います。このコマンドは
それを人間から明示的に起こす入口であり、詳細を求めるときの入口でもあります。

**自前の書式を作らないこと。** 公式の projection をそのまま整形して出します。

1. `orca worktree ps --json`
2. `orca orchestration worker-list --include-remote --json`（既定で束縛 Run。
   `--run <run_id>` で上書き）
3. `orca orchestration task-list --ready --brief --json`
4. `orca orchestration check --json` で未 ack の Delivery を読む。ack するまで同じ束が
   返るので、処理（reply・検証・release の判断）を済ませたものだけを結果の
   `deliveryId` で `check --ack <delivery_id>` する（`--peek` は読むだけで
   `deliveryId` が出ないので、ack には使えない）

出力は表ひとつ。列は **Task / コメント / attention.categories / nextAction /
outcome / evidence / unresolved blocker / 片付け**。Task は「`<ワーカー名>`
（<リポジトリ>）＋ 一行の題」で、ワーカー名は worktree 名。PR 番号は単独の識別子に
せず、evidence にリンクとして添えます。ユーザーはこのワーカー名だけで追加指示を
出せます。コメントは `worktree ps` に出るカードのコメント（ワーカーが書いた進捗）を
そのまま置きます。状態の列（`workspaceStatus`）はボードと食い違うことがある
（Orca #13620）ので使いません。`projection.attention.categories` と
`projection.nextAction` は公式の値をそのまま置き、言い換えない。`nextAction` が
`none` の行には打つべき argv が無いので、`liveness.reason` を書いて待ちます。
evidence には一次情報を短く（「make ci 緑」「2 コミット、ci 未実行」）。「順調です」
は evidence ではありません。

worker_done が届いていなくても、カードのコメントが完了を言っているか
`gh pr list --head <branch>` に PR があるワーカーは終わっているものとして扱います。
終わっているワーカーは、worker_done の `--report-path` が指すファイル（我々の規約
では `~/.claude/worker-reports/<worktree 名>.md`）を Read して outcome / evidence /
unresolved blocker を埋めます。escalation / question があれば人に取り次ぎ、
落ち着いたワーカーは `orca orchestration worker-release` で解放します。ただし拒否
された・stale な完了では release しません。報告の「残っている問題」でその場で片付けない
ものは、`gh issue create` で対象リポジトリに Issue として残します。

**取りこぼしの回収はここで済ませます。** `worktree ps` に残っているもののうち、PR が
マージ済みなのに worktree がまだある行は「片付け可能」です。`片付け` 列にそう書き、
`core-dispatch` スキルの「4. 片付け」の条件（報告を取り込み済み、PR マージ済み、
作業ツリーが clean で未 push のコミットが無い）を満たすものは、**その場で片付けまで
行います**。ユーザーは worktree を自分で管理したくないと言っているので、条件を満たす
ものは確認を取らずに消してよい。ただし**消したことは報告に 1 行残す**（`片付け` 列に
「削除済み」と書く）。条件を欠くものは消さず、何が欠けていたかを同じ列に書きます。
`terminal close --worktree <selector> --all` が `terminal_stop_unverifiable` を返した
ときは、端末 0 件と残プロセス無しの 2 点を確かめるまで `worktree rm` に進みません。

生の JSON や端末出力は貼らず、実行手順の逐次説明もしません。異常があったときだけ、
表の下に理由を 1〜2 文足します。

`check` が空なら、ワーカーが消えたのではなく自分が Run から外れている可能性がある
ので、`orca orchestration run-current` で束縛を確かめ、外れていたら同じ Run に
`run-use --id <run_id>` で結び直すこと（Run の付け替えには使わない）。旧運用で Run が
複数残っているときは、各 Run を `check --run <run_id>` で見て、未 ack のものだけ
処理して `check --run <run_id> --ack <delivery_id>` で ack する。終わった Run は触らない。`unverifiable` や
`missing_status` も死亡ではありません。殺したり再試行したりせず、`core-dispatch`
スキルの `references/orca.md`「ハンドルが stale になったとき」に従って引き直し、
生きているなら続きの指示で起こしてください。
