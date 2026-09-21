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

層は 3 つに分かれる。**受付**でメッセージを分類し、**振り分け**でワーカーに出し、
**統合**で結果を拾う。返し方は「報告の型」で公式に揃える。コマンドの綴りと実測で
踏んだ落とし穴は `references/orca.md` にある。

## 1. 受付 — まず 4 つに分類する

| 種類 | 見分け方 | すること |
| --- | --- | --- |
| 新規の作業 | ファイルが変わる依頼 | 下の「2. 振り分け」 |
| 稼働中ワーカーへの追加指示 | 既に出した作業の修正・補足 | `orca orchestration send`、または `orca terminal send` |
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
- 「終わったら worktree 直下の `.agent/report.md` に、やったこと・検証結果・
  残っている問題を書くこと。チャットの要約ではなくこのファイルが報告の本体になる。
  **先に書いてコミットまで済ませてから**完了を送ること」

報告をファイルに書かせるのは、長時間のオーケストレーションでは最適化プロキシが
ツール出力を圧縮し、ハッシュからの復元が期限切れで失敗するのを実測しているため。
チャットに出た要約は読めなくなることがあるが、ファイルは残る。Orca 再起動を
またぐと完了自体を送れなくなるのも実測済みで、そのときもファイルだけが残る。

**出す。** 完了を追跡するなら orchestration 経由、投げっぱなしでよいなら worktree
create（`references/orca.md` の 2 節）。短い kebab-case の `--name` は必須。

出したら、**そのターンで待たない。** 「報告の型」(a) の 2 行を返して終える。

## 3. 統合 — 張って待つのではなく、拾い直す

`orca orchestration check --wait` をバックグラウンドで張って完了を待つ設計は
**成立しない**。Claude Code のセッションが終わるとバックグラウンドプロセスごと
消え、完了通知を取りこぼす（実測）。メッセージ自体は inbox に残る。

拾いに行く機会は 3 つ。**Orca 自身の通知**（「You have N orchestration message.
Run `orca orchestration check --run <run_id>`」がセッションに注入される。これが実質の
起こし役なので、来たら従う）、**セッションの最初**、**新しい依頼を受けた時**。
いずれでも:

1. `orca worktree ps --json` で稼働中の workspace を見る
2. `orca orchestration check --json` で溜まっている worker_done / escalation /
   question を読む
3. worker_done なら、その worktree 直下の `.agent/report.md` を Read して報告する
   （チャット上の要約ではなく、これが正本）
4. escalation / question は人に取り次ぎ、返答を `orca orchestration reply` で返す
5. 落ち着いたワーカーは `orca orchestration worker-release` で解放する。有効な
   worker_done は Task と Dispatch を自動で決着させるので、続けて `task-update` を
   打たない。ただし **拒否された・stale な完了では release しない**。その場合の
   決着だけが `worker-abandon` → `task-update` の順になる（`references/orca.md`）

セッションが再起動した直後は、自分の端末ハンドルも変わっている。`check` が空に
見えるときは、まず Run の束縛を確かめて結び直す（`references/orca.md` の
「Run を結び直す」）。ワーカーが消えたのではなく、自分が Run から外れている。

**liveness が `unverifiable` / `missing_status` でも、死んだと判定しない。** Orca
再起動でハンドルが変わっただけのことが多い。引き直し方と起こし方は
`references/orca.md` の「ハンドルが stale になったとき」。

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

| Task | outcome | evidence | unresolved blocker |
| --- | --- | --- | --- |
| dispatch-layer | succeeded | make ci 緑、4 コミット | なし |
| docs-ja | 作業中 | 2 コミット、ci 未実行 | なし |

**evidence には一次情報を短く置く。**「順調です」は evidence ではない。「make ci
緑」「テスト 3 件失敗」のように、こちらが実際に見たものを書く。

**(c) ディスパッチ直後は 2 行。** これは公式の型ではなく、待たずにターンを閉じる
ための最小形である。

```
出した: <ワーカー名> / <リポジトリ>:<ブランチ> / <エージェント>
次: <何を待つか>
```

**(d) 報告ファイルのパスは公式のフラグで渡す。** worker_done に
`--report-path <path>` を添えるのが規約で、`.agent/report.md` はその値として我々が
選んだ置き場所にすぎない。公式が定めた名前ではないので、値のほうを動かしてよく、
規約のほうは動かさない。

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
