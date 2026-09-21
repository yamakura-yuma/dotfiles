# orca コマンド早見表と、実測で踏んだ落とし穴

手順そのものの正本は Orca が配っているスキルで、実行中のバイナリと同じ版が出る。

```
orca skills get orca-cli
orca skills get orchestration
```

全文（790 行、reference 込み）が要るときは `--full`、個別に読むなら
`--reference <name>`。

ここに書くのは、**その早見表と、上のスキルどおりにやって失敗した点**だけ。齟齬が
あったら `orca skills get` のほうが正しい。

各項目には出どころを付ける。**【公式】** は Orca のスキルや `--help` に明記されて
いること、**【実測】** はここで観測しただけで、どこにも文書化されていないこと。
実測は次の版で変わりうるので、公式と同じ重みで扱わない。

## リポジトリを指す — `--repo id:<repoId>` を必ず書く 【実測】

`orca worktree current` は cwd を Windows 側のホストで解決しようとして
`C:\home\...` を返し、そのまま失敗する。coordinator は Orca が管理する worktree の
外にあることも多く、`active` / `current` に依存した指定も当てにならない。
**リポジトリは毎回明示する。**

```
orca worktree list --json
```

`result.worktrees[]` の `repoId` がそのまま `--repo id:<repoId>` に渡す値になる
（`id` フィールドは `<repoId>::<path>` という形なので、`::` より前と同じもの）。
`hostId` は実行ホストで、この環境では `ssh:ssh-1789836108505-xyk3n6`。ホストを
またぐときだけ意識すればよく、同一ホスト内なら `--repo` だけで足りる。

欲しい 1 行を取り出すなら:

```sh
orca worktree list --json |
  jq -r '.result.worktrees[] | select(.isMainWorktree) | "\(.repoId)\t\(.path)"'
```

## 投げっぱなしで出す 【公式】

戻りを待たずに走らせてよい作業はこちら。作った worktree の第一ターミナルで
エージェントが起き、`--prompt` がそのまま最初のメッセージになる。

```
orca worktree create --repo id:<repoId> --name <kebab-name> --agent claude --prompt "<spec>" --setup run --json
```

- `--name` は必須。作業内容から短い kebab-case を付ける。
- `--agent` を渡したら `orca terminal create` を重ねない。ターミナルは既にある。
  ハンドルは `result.agentTerminalHandle`（古いランタイムは
  `result.startupTerminal.handle` しか返さない）。以上は `--help` の Notes にある。
- リポジトリ側の setup フックを確実に走らせたいときだけ `--setup run`。

## 監視付きで出す 【公式】

worker_done / escalation / question を受け取りたい、つまり統合まで面倒を見るなら
orchestration 側から出す。Run が無ければ先に作る。

```
orca orchestration run-current --json
orca orchestration run-create --objective "<この一連の作業の目的>" --json
orca orchestration worker-start --spec "<spec>" --task-title "<短い題>" --worktree new-top-level --name <kebab-name> --repo id:<repoId> --agent claude --setup run --json
```

- `--worktree new-top-level` が「独立した新しい worktree を切ってそこで走らせる」。
  今いる worktree の子として切るなら `new-child`、既存を使うなら selector を渡す。
- `--spec` を渡すとタスクも同時に作られる。既に `task-create` したタスクに出すなら
  `--task <task_id>`。

## 受け取る — 待ち続けずに、そのつど拾い直す

```
orca orchestration check --json
orca orchestration check --terminal <handle> --json
```

**【公式】** `check` は `--terminal` で呼び出し元を名乗る（`--from` ではない）。
`--wait` と `--timeout-ms` でメッセージが来るまでブロックできる。

**【実測】** `check` は `--help` を解釈せず inbox を表示する（そのため
`core-principal/tests/harness-check.sh` のフラグ検査はこのサブコマンドを飛ばす）。

**【実測】** coordinator では `--wait` を使わない。前景で待てばターンが塞がって次の
依頼を受けられず、バックグラウンドの Bash で待たせても **Claude Code のセッションが
終われば道連れに消え、完了通知を取りこぼす**。

**【実測】** 待たなくても起こしてもらえる。Orca は coordinator 端末のセッションに

> You have N orchestration message. Run `orca orchestration check --run <run_id>`

という通知を自分で注入してくる。これが統合の実際のトリガーだが、**通知に依存しない
こと。** 通知が途絶える経路が 2 つあり、片方は公式に明記されている（下の「資格を失う
とき」）。取りこぼしはセッション開始時と依頼を受けた時の拾い直しで回収する。
メッセージは inbox に残っているので消えはしない。

## Run を結び直す 【公式】

coordinator 側の端末ハンドルもセッション再起動で変わる。ハンドルが変われば Run との
束縛も切れるので、通知が来ない・`check` が空に見えるときはここを疑う。

```
orca orchestration run-current --json
orca orchestration run-use --id <run_id> --json
```

`run-use` が取るのは **`--id`** で、`--run` ではない（`--run` を渡すとフラグエラーに
なる。他の多くのサブコマンドが `--run` なので間違えやすい）。

返事をする・解放する:

```
orca orchestration reply --id <msg_id> --body "<返答>" --json
orca orchestration worker-release --dispatch <dispatch_id> --json
```

## 状況を見る — 公式の projection を読む 【公式】

```
orca worktree ps --json
orca orchestration worker-list --run <run_id> --include-remote --json
orca orchestration task-list --ready --brief --json
orca orchestration inbox --limit 20 --json
```

`worker-list` の各行には `projection.attention.categories`、
`projection.attention.requiresAction`、そして argv がそのまま入った
`projection.nextAction` がある。判断はここから組み立てる。`nextAction` が `none` の
行に打つべき argv は無いので、`liveness.reason` を読んで待つ。行は新しい順で 100 件
ごとに切れるので、`page.hasMore` の間は `page.nextCursor` を `--cursor` に渡す。

`task-list --ready --brief` の ready view を、公式は **external memory** と呼ぶ。
次に動けるものを覚えておくのではなく、そのつどここから引く。

**【実測】** `worktree ps` は実行ホストごとに行を返し、末尾の `scope:` 行がどのホスト
を見たかを書く。そこに出ていないホストの workspace は「無い」のではなく「見ていない」。

## ハンドルが stale になったとき — 死亡と判定しない

**【公式】** `live` / `unverifiable` / `exited` の判定はそのまま保つこと。**接触の
喪失はプロセスの死ではない**（Authority and safety floor）。停止・放棄・再試行・解放を
authorize するのは positive proof だけで、不在は何も authorize しない。

**【実測】** Orca 本体が再起動するとターミナルハンドルが変わる。dispatch に記録された
ハンドルはそのまま古くなり、`worker-list` の liveness が `unverifiable` や
`missing_status` になる。これは上の「接触の喪失」にあたり、死亡ではない。

引き直して、自分の目で確かめる:

```
orca terminal list --worktree <selector> --json
orca terminal read --terminal <new-handle> --screen --json
orca terminal wait --terminal <new-handle> --for tui-idle --timeout-ms 60000 --json
```

読んで判断する。作業中なら放っておく。**アイドルなのに worker_done が来ていない
なら、それは落ちたのではなく止まっているので、続きの指示を送って起こす**
（下の `terminal send`）。

## 資格を失うとき — 公式の経路と、我々が踏んだ経路

**【公式】** lifecycle の権限は **active Dispatch** に紐づく。ターミナルのタイトル、
コピーした ID、古い DB 行、provider の transcript、見えているペインのどれでもない。
ワーカーは live preamble にある executable / handle / capability / Task ID /
Dispatch ID を**そのまま**使い、再構成も翻訳も拡張もしてはならない。したがって
worker_done は preamble の `--from <handle>` と `--dispatch-capability <capability>`
を付けて送る。

**【公式】** 所有権を失ったことは `check` が `consumer_fenced` を返したときに知る。
Attempt が別のワーカーに付け替えられたか、自分抜きで決着したということなので、
**停止し、worker_done を送らず、check を再試行しない**。空の `check` は「置き換え
られた」を意味しない。公式は **`consumer_fenced` is the only way you learn that** と
明記している。つまり想定経路は「check で気づいて静かに降りる」である。

**【実測・未文書】** ここで踏んだのはその経路ではない。Orca 本体が再起動したあと、
`worker_done` の送信そのものが拒否された。旧ハンドルでは
`caller is not the Dispatch pane`、`terminal list` で引き直した新ハンドルでは
`The Dispatch process incarnation changed`。**`dispatch_capability_invalid` という
エラーコードも、プロセス世代（incarnation）が変わると弾かれるという挙動も、
`--full` の 790 行に一語も出てこない。** 送信が拒否されて初めて資格喪失を知る、
という経路は公式には書かれていない。

**【実測】因果の訂正。** 「`worker-abandon` したから通知が来なくなった」のではない。
順序は逆で、**Orca 再起動の時点で capability は既に失効しており**、`worker-abandon`
はそのあとで fence を確定させただけである。

**設計上の含意。** 通知は fence（公式経路）でも capability 失効（未文書の実測）でも
途絶えうる。どちらも「来るはずのものが来ない」形で起きるので、**完了は待ち受けでは
なく pull で突き合わせる**。根拠は上の公式引用そのもので、`consumer_fenced` を自分
から `check` しない限り資格喪失に気づけないのなら、到着を前提にした設計は最初から
成り立たない。

## 拒否された完了をどう決着させるか

**【実測】ワーカー側**: 報告はファイルに書き、**先に書き終えてから** `worker_done` を
試みる。順序が逆だと、拒否された時点で報告がどこにも残らない。
ファイルの場所は公式のフラグで渡す規約である:

```
orca orchestration send --type worker_done --outcome succeeded --report-path <path> --subject "<短く>" --body "<3 文>" --json
```

**【公式】** 規約は `--report-path` のほうで、`~/.claude/worker-reports/<worktree 名>.md`
はその値として我々が選んだ置き場所にすぎない。パスは要件しだいで動かしてよい。作業
ツリーの外に置いているのは、未追跡の報告ファイルが worktree の削除を妨げるため。

**【実測】coordinator 側**: 拒否された worker_done もこちらの受信箱には worker_done
型で届き、本文と payload（outcome、filesModified、reportPath）はそのまま読める。これを
完了の証拠として読んでよい。ただし **`worker-release` は打たない**（stale または
拒否された完了で release しない）。決着はこの順で:

```
orca orchestration worker-abandon --dispatch <dispatch_id> --json
orca orchestration task-update --id <task_id> --status completed --json
```

**【実測】** `task-update` を先に打つと `task_not_startable`（supervised Dispatch is
active）で弾かれる。**【公式】** なお有効な worker_done は Task と Dispatch を自動で
決着させるので、通常は `task-update` を続けて打たない。この 2 手が要るのは、いまの
ように worker_done が拒否されて成立しなかった場合だけである。`worker-abandon` は
「プロセスが止まった」と主張せずに Dispatch を fence するだけなので、**決着後も
ワーカーの端末と worktree は生きたまま残る**。この経路で決着させた Dispatch の資源は
release の対象ではないので、片付けは下の「片付ける」に従って orca-cli 側から行う。

## 片付ける — 端末を閉じて worktree を消す

**【公式】orchestration 層は worktree を消さない。** `worker-release` は settled
（succeeded / failed）なワーカーの後片付けで、**そのワーカーの、coordinator が所有する
エージェント端末だけ**を閉じる。setup 端末、設定されたタブ、再利用・既存の端末、
ユーザーが引き取った端末、証明できない identity は決して閉じない。閉じる前に
inspectable な出力アーカイブが残るので、閉じたあとでも `worker-read` は出力を返す。
冪等で、繰り返すと `already_released` を返す。`worker-stop` のほうは「**worktree、
setup 端末、設定されたタブ、無関係なプロセスを決して削除しない**」と明記されている。
つまり orchestration 側のどのサブコマンドも worktree を消さない。

**【公式】削除の口は `orca worktree rm` だけで、Orca と git の両方から外す。**

```
orca worktree rm --worktree id:<repoId>::<path> --force --json
```

`--force` の説明は「サポートされる場合に worktree の削除を強制する。**ブランチ削除は
強制しない**」である。git worktree の場合、削除はチェックアウト中のローカルブランチの
削除も試みる（`--force` の有無にかかわらず）が、**Orca は「worktree より前から存在した
と分かっているブランチ」と「変更が既にマージ済みだと証明できないブランチ」を残す**。
未マージの作業はここで守られるので、ブランチ削除の安全側の判断は Orca に任せる。

**【実測】** この保護が効いていることを観測した。`dotfiles-orca-dispatch-layer` を
片付けたとき、`worktree rm --force` は `{"removed": true}` を返し、**`main` に
マージ済みだったローカルブランチ `orca-dispatch-layer` は Orca が削除した**。マージ済み
だと証明できたので残さなかった、という向きの実例である。

**【公式】archive hook は `--run-hooks` を付けたときだけ走り、失敗すると削除を止める。**

```
orca worktree rm --worktree <selector> --force --run-hooks --allow-failed-archive-hook --json
```

repo の `orca.yaml` で定義された archive hook は、`--run-hooks` を渡さない限り
スキップされる。`--run-hooks` 付きで hook が失敗すると**削除全体がブロックされる**。
何も停止・削除・登録解除されず、`worktree_archive_hook_failed` で非ゼロ終了する。
**`--force` はこれを waive しない。** 失敗を承知で消すには
`--allow-failed-archive-hook` が要る。これは `--run-hooks` なしでは拒否される
（hook が走らないなら waive すべき失敗が存在しないため）。waive したことは
`result.archiveHookOverride` に返る。

**【公式】bulk close は、ホストが停止を確認できないと失敗する。**

```
orca terminal close --worktree <selector> --all --json
orca terminal list --worktree <selector> --json
```

`--worktree <selector> --all` は、そのワークスペースが所有するすべての端末プロセスを
停止し、端末タブ・レイアウト・resume 記録を durable に削除する。orca-cli の端末規則は
「**bulk close は実行ホストがすべての PTY の停止を確認できないと失敗する。
`unverifiable` として扱い、プロセスが終了したと報告してはならない**。別のホストに対して
retry してもならない」と明記している。あとで再開したい端末は close ではなく workspace
Sleep を使う、とも書かれている。

**【実測】`closed 1` / `stopped 1` と言いながら失敗し、実際には閉じていた。**
`dotfiles-orca-dispatch-layer` の片付けで `terminal close --worktree <id> --all` が
`terminal_stop_unverifiable` で失敗した。receipt には `closed 1`、`stopped 1` と出て
いるのに「the owning host did not confirm the PTY exit」が理由だった。そして実際には
閉じていた。**つまり close の戻り値が失敗でも、削除してよい状態になっていることがある。
戻り値だけでは判断できない。** unverifiable を受けたら、`terminal list --worktree
<selector>` が 0 件であることと、OS 側にその worktree のパスを含むプロセスが残っていない
ことを別々に確かめ、両方取れたときだけ `worktree rm` に進む。取れなければ消さない。

**【公式】完了は削除ではなくカード状態で表す。**

```
orca worktree set --worktree <selector> --workspace-status in-review --json
```

`--workspace-status` が取るのはボードの列 id で、既定は `todo` / `in-progress` /
`in-review` / `completed`。カスタム状態は設定された id を使う。「終わった」を表すのに
worktree を消す必要はないので、レビュー待ちや記録として残したいものはここを動かす。

## 稼働中のワーカーに追加で言う 【公式】

```
orca orchestration send --to dispatch:<dispatch_id> --subject "<短く>" --body "<追加指示>" --json
orca terminal send --terminal <handle> --text "<追加指示>" --enter --json
```

監視付きで出したワーカーには `orchestration send`、投げっぱなしのワーカーには
`terminal send`。どちらも enqueue は durable だが**割り込まない**ので、相手が
`check` を見るまで届かない。

**【実測】`terminal send` に `--enter` を付け忘れると、テキストは入力欄に残るだけで
submit されない。** これで追加指示を 2 本失った実例がある。加えて、ワーカー側で
memory のリコールなどのパネルが開いていると入力が飲まれることがあり、`--wait-submit`
の「no turn start」警告は誤検知もする。**届いたかどうかは戻り値ではなく
`orca terminal read` の差分で確かめる。**

## Orca に「primary workspace」という概念は無い 【実測】

Orca が見ているのは、**その端末が Run に束縛された coordinator かどうか**である
（Run の `coordinator_handle`、`orchestration run-current` が返す束縛、orchestration
スキルの役割分類表の Coordinator）。ワークスペースが「元の checkout か」「デフォルト
ブランチか」を Orca が判定することはない。

つまり `.apm/hooks/scripts/lib/coordinator-workspace.sh` の checkout ベースの判定は、
**この要件に固有のもの**である。Orca の外で起動したセッション（`~` で始めた Claude
Code など）にも同じ規範を効かせたい、という我々の事情から来ている。Orca の語彙に
合わせるのは呼称だけで、判定そのものは合わせようがない。
