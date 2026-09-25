---
name: core-dispatch
description: Taking work as the coordinator and handing it to a worker in a worktree of its own - classifying the request, writing the spec, dispatching, picking the results back up, and reporting them in a fixed shape. Use when a session that is the coordinator (the default branch of an original checkout, or a directory in no repository such as $HOME) is asked to change anything, when a dispatched worker needs a follow-up instruction, or when asking what workers are running.
---

# 仕事を受ける、出す、戻す

このセッションは **coordinator**、つまり仕事を配る側で、ここでは実装しない。Edit /
Write / NotebookEdit は `guard-coordinator-edit` hook が拒否し、`git commit` /
`git push` は `guard-default-branch` hook が拒否する。調査・計画・コマンド実行は
ここでしてよい。

この分担には Orca 公式の裏付けがある。`orca skills get orchestration --reference
coordinator-loop` の **Review ownership** は「review-only な `worker_done` は所見の
統合を許すが、coordinator によるファイル編集は許さない。修正は dispatch か handoff に
回す（ユーザーが明示的に coordinator に割り当てた場合を除く）」と定めている。hook は
これを Orca の外側にも効かせているだけで、独自の方針ではない。

coordinator かどうかの判定は 1 か所にある
（`.apm/hooks/scripts/lib/coordinator-workspace.sh`）。**デフォルトブランチ上の
元の checkout**（`git worktree` の子ではないほう）か、**どのリポジトリにも属さない
cwd**（`~` など）がそれにあたる。子 worktree は違う。そこは仕事が落ちる先である。

層は 4 つに分かれる。**受付**でメッセージを分類し、**振り分け**でワーカーに出し、
**統合**で結果を拾い、**片付け**で端末と worktree を畳む。返し方は「報告の型」で
公式に揃える。コマンドの綴りと実測で踏んだ落とし穴は `references/orca.md` にある。

## 1. 受付 — まず 4 つに分類する

| 種類 | 見分け方 | すること |
| --- | --- | --- |
| 新規の作業 | ファイルが変わる依頼 | 下の「2. 振り分け」 |
| 稼働中ワーカーへの追加指示 | 既に出した作業の修正・補足。ワーカー名だけで指されることが多い | 下の「追加指示を届ける」 |
| 状況確認 | 「どうなってる」「終わった？」 | 下の「3. 統合」、`/workers` |
| オーケストレーション制御 | 止める・伝える・解放する | `reply` / `worker-release`、`references/orca.md` |

ここで完結してよいのは下 3 つと、**対象リポジトリを特定するための 1 問**だけ。
それ以外は、どれだけ小さく見えても出す。「これくらいなら自分で」が、この層を
成立させなくする。

## 2. 振り分け

**リポジトリを決める。** `orca worktree list --json` の `repoId` を使い、`--repo
id:<repoId>` を必ず明示する（`active` や `current` は当てにならない。理由は
references）。依頼から一意に決まらないときだけ、ここで 1 問聞く。

**spec を書く。** ワーカーはこのテキストしか受け取らない。最低限、次を含める。

- 対象（リポジトリ、触ってよい範囲、触ってはいけない範囲）
- やること、そして**完了条件**（何が観測できたら終わりか）
- 検証の打ち方（そのリポジトリの `make ci` など既存の入口）
- 「節目ごとに進捗を、終わったら完了を、自分のカードのコメントに 1 行で書くこと
  （`orca worktree set --worktree active --comment "<いまの状態>" --json`）」
- 「終わったら `mkdir -p ~/.claude/worker-reports` して
  `~/.claude/worker-reports/<worktree 名>.md` に、やったこと・検証結果・残っている
  問題を書くこと。チャットの要約ではなくこのファイルが報告の本体になる。**先に
  書いてから**完了を送ること。リポジトリの中に報告ファイルを作らないこと」

報告をファイルに書かせるのは、長時間のオーケストレーションでは最適化プロキシが
ツール出力を圧縮し、ハッシュからの復元が期限切れで失敗するのを実測しているため。
チャットに出た要約は読めなくなることがあるが、ファイルは残る。Orca 再起動を
またぐと完了自体を送れなくなるのも実測済みで、そのときもファイルだけが残る。

**置き場は作業ツリーの外に取る。** 報告のうち git に残すべきもの（決めたこと、積み
残し）はコミットメッセージと PR 本文に書けば足り、残りはオーケストレーションの作業
控えでしかない。`.gitignore` で隠すのではなく最初から置かないのは、未追跡の `.agent/`
が残ったせいで `git worktree remove` が Directory not empty で落ちた実例があるため。
ファイル名に worktree 名を入れるのは、報告どうしの衝突を避けるためである。

ワーカーが coordinator と別ホストで走る場合（Orca の ssh 実行ホストなど）、この
パスはワーカー側のホストを指すので coordinator からは読めない。worktree 直下に
置いても同じなので、悪化はしない。

**出す。** 出し方は監督ありの 1 通りに統一する。Run を確かめ（無ければ
`run-create`）、`worker-start` で出す。ワーカーは `worker_done` で完了を返し、
こちらは「3. 統合」で拾って `worker-release` する。コマンドは `references/orca.md`
の「出す」。短い kebab-case の `--name` は必須で、これがそのままワーカー名になる。

例外は 1 つだけ。ユーザーが**所有権ごと渡す**と明示したときは handoff
（`orca skills get orca-cli` の手順）にし、監督しない。

**親は coordinator の worktree にする。** ただし Orca の親子は同じリポジトリ・同じ
実行ホスト・同じプロジェクトの間でしか張れない（実測）。`~/coordinator` 自身の作業は
`--worktree new-child` で子にし、他のリポジトリの作業は `new-top-level` で出す。詳細は
`references/orca.md`「親子を張る」。

**進捗はカードのコメントで見る。** ワーカーに書かせたコメントは `orca worktree ps`
にそのまま出るので、覗きに行かずに状況が分かる。状態の列（`--workspace-status`）は
ボードに反映されない既知のバグ（Orca #13620）があるので、補助としてだけ使う。

出したら、**そのターンで待たない。** 「報告の型」(a) の 2 行を返して終える。

## 3. 統合 — 張って待つのではなく、拾い直す

`orca orchestration check --wait` をバックグラウンドで張って完了を待つ設計は
**成立しない**。Claude Code のセッションが終わるとバックグラウンドプロセスごと
消え、完了通知を取りこぼす（実測）。メッセージ自体は inbox に残る。

**そもそも到着を前提にできない。** 公式は、所有権を失ったことを知る手段は `check`
が返す `consumer_fenced` だけだと明記している（"`consumer_fenced` is the only way
you learn that"）。つまり自分から引かなければ資格喪失にすら気づけない。さらに
未文書の実測として、Orca 再起動で capability が失効し、送信自体が拒否される経路も
ある。いずれも「来るはずのものが来ない」形なので、**完了は pull で突き合わせる**。
詳しくは `references/orca.md`「資格を失うとき」。

拾いに行く機会は 3 つ。**Orca 自身の通知**（「You have N orchestration message.
Run `orca orchestration check --run <run_id>`」がセッションに注入される。これが実質の
起こし役なので、来たら従う）、**セッションの最初**、**新しい依頼を受けた時**。
いずれでも:

1. `orca worktree ps --json` で稼働中の workspace と、ワーカーが書いたカードの
   コメントを見る
2. `orca orchestration check --json` で溜まっている worker_done / escalation /
   question を読む
3. worker_done なら、`--report-path` が指すファイル（我々の規約では
   `~/.claude/worker-reports/<worktree 名>.md`）を Read して報告する
   （チャット上の要約ではなく、これが正本）
4. escalation / question は人に取り次ぎ、返答を `orca orchestration reply` で返す
5. 落ち着いたワーカーは `orca orchestration worker-release` で解放する。有効な
   worker_done は Task と Dispatch を自動で決着させるので、続けて `task-update` を
   打たない。ただし **拒否された・stale な完了では release しない**。その場合の
   決着だけが `worker-abandon` → `task-update` の順になる（`references/orca.md`）
6. 決着したら「4. 片付け」に進む。端末を閉じても worktree は残るので、消すのは別の手順

セッションが再起動した直後は、自分の端末ハンドルも変わっている。`check` が空に
見えるときは、まず Run の束縛を確かめて結び直す（`references/orca.md` の
「Run を結び直す」）。ワーカーが消えたのではなく、自分が Run から外れている。

**liveness が `unverifiable` / `missing_status` でも、死んだと判定しない。** Orca
再起動でハンドルが変わっただけのことが多い。引き直し方と起こし方は
`references/orca.md` の「ハンドルが stale になったとき」。

### 追加指示を届ける

ユーザーは**ワーカー名だけ**で追加指示を出してよい（「dispatch-supervised に〜も
足して」）。coordinator はその名前から worktree と Dispatch を引き、該当ワーカーの
端末へ届ける。

1. `orca worktree list --json` で名前（`displayName`）から worktree を特定する
2. `orca orchestration worker-list --run <run_id> --json` でその worktree の
   Dispatch を引き、`orca orchestration send --to dispatch:<dispatch_id>` で送る
3. Dispatch が決着済み・資格失効などで送れないときは、`orca terminal list
   --worktree <selector>` で端末を引き、`orca terminal send --enter` で送る

どちらも割り込まないので、届いたかは `orca terminal read` の差分で確かめる
（`references/orca.md`「稼働中のワーカーに追加で言う」）。

## 4. 片付け — 終わった worktree を残さない

終わった worktree を放置しない。ユーザーは自分で管理したくないと言っているので、
**下の条件を満たすものは断らずに消す**。消したことは報告に 1 行だけ残す。

**orchestration 層は worktree を消さない。** `worker-release` は settled な Dispatch が
所有する端末だけを閉じて出力をアーカイブし、`worker-stop` は「worktree、setup 端末、
設定されたタブ、無関係なプロセスを決して削除しない」と明記している。削除の口は
`orca worktree rm` だけである（`references/orca.md` の「片付ける」）。

**(a) 先に報告を自分の手元に取り込む。** 報告の本体は worktree の中のファイルなので、
消せば一緒に消える。outcome / evidence / unresolved blocker をユーザーへの報告に
写し終えるまで、片付けに進まない。

**(b) 片付けてよい条件を全部確かめる。** ひとつでも欠けたら消さない。

- PR がマージ済み（`gh pr view --json state` が `MERGED`、または `git branch --merged`
  で base に入っている）
- 作業ツリーが clean で、push していないコミットが無い
- 報告を (a) で取り込み済み

**(c) 端末を閉じる。** Dispatch が正常に settle しているなら release で閉じる。

```
orca orchestration worker-release --dispatch <dispatch_id> --json
```

settle できなかったとき（`worker-abandon` した、capability が失効した）は資源が
user_owned になっていて release の対象にならないので、orca-cli 側で閉じる。
**release を代用してはならない。**

```
orca terminal close --worktree <selector> --all --json
```

**この bulk close は、失敗を返しても実際には閉じていることがある。** 実行ホストが
すべての PTY の停止を確認できないと `terminal_stop_unverifiable` で失敗するが、これは
「終了していない」ではなく「確認が取れていない」である。receipt が `closed 1`
`stopped 1` と言いながら失敗した実例がある。**戻り値だけで削除の可否を決めない。**
unverifiable が返ったら次の 2 つを別に確かめ、**両方取れたときだけ (d) へ進む**。

1. `orca terminal list --worktree <selector> --json` が 0 件を返す
2. OS 側に、その worktree のパスを含むプロセスが残っていない

どちらかが取れなければ消さずに残す。プロセスが生きているかもしれない worktree を
消すことは、この手順では許さない。

**(d) 消す。**

```
orca worktree rm --worktree id:<repoId>::<path> --force --json
```

Orca と git の両方から外れる。`--force` が強制するのは worktree の削除だけで、
ブランチ削除は強制しない。チェックアウト中のローカルブランチも削除しようとするが、
**worktree より前からあったと分かっているブランチと、変更がマージ済みだと証明できない
ブランチは残す**。つまり未マージの作業は Orca 自身が守るので、ブランチをどうするかの
安全側の判断は Orca に任せ、先回りして消さない。

archive hook を持つリポジトリでは、`--run-hooks` を付けるか既定のまま付けないかを
そのリポジトリの運用に合わせる。付けると hook の失敗が削除をブロックし、`--force`
でも waive されない（`references/orca.md`）。

**(e) 消さない選択もある。** あとで再開するなら端末を閉じずに workspace Sleep を使う。
レビュー待ちならカードのコメントに「PR #N レビュー待ち」と書いて残す。
`--workspace-status` を動かしてもよいが、ボードに反映されないことがある（Orca
#13620）ので、それだけを完了の表現にしない。

## 報告の型 — 公式に揃える

書式を自前で発明しない。俯瞰する道具も、報告に名指しすべき項目も、Orca の公式が
既に決めている。**返答はその形に収め、型に無いものは書かない。**

**(a) 俯瞰は公式の ready view と projection から作る。** 読むのはこの 3 つ。

```
orca worktree ps --json
orca orchestration worker-list --run <run_id> --include-remote --json
orca orchestration task-list --ready --brief --json
```

`worker-list` は行ごとに `projection.attention.categories`、
`projection.attention.requiresAction`、そのまま実行できる argv である
`projection.nextAction` を返す。公式は `task-list --ready --brief` の ready view を
**external memory** と位置づけている。つまり「何が次に動けるか」は覚えておく
ものではなく、そのつど引くものである。

**(b) 報告は Task ごとに outcome / evidence / unresolved blocker。** 公式の Outcome
節が、ターンを終えてよい条件として「per Task, its outcome, the evidence behind it,
and any unresolved blocker」を名指しすることを求めている。表にするならこの 3 つを
列にする。

**作業の識別子はワーカー名（worktree 名）にする。** Task 列は
「`<ワーカー名>`（<リポジトリ>）＋ 一行の題」。PR 番号は単独の識別子にせず、
evidence にリンクとして添える。ユーザーがワーカー名だけで追加指示を出せるように
するためで、届け方は「追加指示を届ける」にある。

| Task | outcome | evidence | unresolved blocker |
| --- | --- | --- | --- |
| `dispatch-layer`（dotfiles）監督ありに統一 | succeeded | make ci 緑、[PR #12](https://github.com/o/r/pull/12) | なし |
| `docs-ja`（temporal-saga）README を日本語化 | 作業中 | 2 コミット、ci 未実行 | なし |

**evidence には一次情報を短く置く。**「順調です」は evidence ではない。「make ci
緑」「テスト 3 件失敗」のように、こちらが実際に見たものを書く。

**(c) ディスパッチ直後は 2 行。** これは公式の型ではなく、待たずにターンを閉じる
ための最小形である。

```
出した: <ワーカー名> / <リポジトリ>:<ブランチ> / <エージェント>
次: <何を待つか>
```

**(d) 報告ファイルのパスは公式のフラグで渡す。** worker_done に
`--report-path <path>` を添えるのが規約で、`~/.claude/worker-reports/<worktree 名>.md`
はその値として我々が選んだ置き場所にすぎない。公式が定めた名前ではないので、値のほうを
動かしてよく、規約のほうは動かさない。作業ツリーの外に移したのもこの自由による。

**(e) 書かないもの。**

- コマンドの生 JSON、端末出力の tail、ログの貼り付け
- 「まず〜して、次に〜しました」という実行手順の逐次説明
- 同じ内容の再掲（表に書いたことを、下の地の文でもう一度言わない）
- 異常や例外のとき**だけ**、理由を 1〜2 文足す。平常運転に理由は要らない

**(f) 詳細は push ではなく pull。** 型に入らない細部は、聞かれたときに出す。その
入口が `/workers` で、そこでは (a) の出力を整形して出す。読む側が深掘りを選べる形に
しておき、こちらから先回りして流さない。

## 台帳は持たない

稼働中ワーカーの状態は Orca 側（`orca worktree ps`、`orca orchestration task-list`、
`orca orchestration inbox`）を正とする。公式が ready view を external memory と
呼んでいるとおり、覚えておく代わりに引く。自前の一覧ファイルは置かない。coordinator
ではそもそも Write が拒否されるので置けず、二重管理にもならない。

## 解除

人間がターミナルで `MAKURA_ALLOW_MAIN=1` を export して Claude Code を起動すると、
注入もブロックも止まる。エージェントは自分で設定できない（hook が見るのは Claude
Code の環境で、Bash ツールが組み立てた環境ではない）。
