---
name: core-dispatch
description: Taking work in the primary workspace and handing it to a worker in a worktree of its own - classifying the request, writing the spec, dispatching, then picking the results back up. Use when a session in the primary workspace (the default branch of an original checkout, or a directory in no repository such as $HOME) is asked to change anything, when a dispatched worker needs a follow-up instruction, or when asking what workers are running.
---

# 仕事を受ける、出す、戻す

プライマリ workspace は**オーケストレーション層**で、ここでは実装しない。Edit /
Write / NotebookEdit は `guard-primary-edit` hook が拒否し、`git commit` / `git push`
は `guard-default-branch` hook が拒否する。調査・計画・コマンド実行はここでしてよい。

プライマリかどうかの判定は 1 か所にある
（`.apm/hooks/scripts/lib/primary-workspace.sh`）。デフォルトブランチ上の元 checkout
か、どのリポジトリにも属さない cwd（`~` など）がプライマリで、子 worktree は違う。

層は 3 つに分かれる。**受付**でメッセージを分類し、**振り分け**でワーカーに出し、
**統合**で結果を拾う。コマンドの綴りと実測で踏んだ落とし穴は
`references/orca.md` にある。

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
  残っている問題を書くこと。チャットの要約ではなくこのファイルが報告の本体になる」

報告をファイルに書かせるのは、長時間のオーケストレーションでは最適化プロキシが
ツール出力を圧縮し、ハッシュからの復元が期限切れで失敗するのを実測しているため。
チャットに出た要約は読めなくなることがあるが、ファイルは残る。

**出す。** 完了を追跡するなら orchestration 経由、投げっぱなしでよいなら worktree
create（`references/orca.md` の 2 節）。短い kebab-case の `--name` は必須。

出したら、**そのターンで待たない。** ディスパッチしたことと名前・repo を答えて
ターンを終える。

## 3. 統合 — 張って待つのではなく、拾い直す

`orca orchestration check --wait` をバックグラウンドで張って完了を待つ設計は
**成立しない**。Claude Code のセッションが終わるとバックグラウンドプロセスごと
消え、完了通知を取りこぼす（実測）。メッセージ自体は inbox に残るので、待つ代わりに
**そのつど拾い直す**。

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
5. 落ち着いたワーカーは `orca orchestration worker-release` で解放する

セッションが再起動した直後は、自分の端末ハンドルも変わっている。`check` が空に
見えるときは、まず Run の束縛を確かめて結び直す（`references/orca.md` の
「Run を結び直す」）。ワーカーが消えたのではなく、自分が Run から外れている。

明示的に状況を聞かれたときの入口が `/workers` で、これが取りこぼしの回復口も
兼ねる。**liveness が `unverifiable` / `missing_status` でも、死んだと判定しない。**
Orca 再起動でハンドルが変わっただけのことが多い。引き直し方と起こし方は
`references/orca.md` の「ハンドルが stale になったとき」。

## 台帳は持たない

稼働中ワーカーの状態は Orca 側（`orca worktree ps`、`orca orchestration task-list`、
`orca orchestration inbox`）を正とする。自前の一覧ファイルを置かない。プライマリでは
そもそも Write が拒否されるので置けず、二重管理にもならない。

## 解除

人間がターミナルで `MAKURA_ALLOW_MAIN=1` を export して Claude Code を起動すると、
注入もブロックも止まる。エージェントは自分で設定できない（hook が見るのは Claude
Code の環境で、Bash ツールが組み立てた環境ではない）。
