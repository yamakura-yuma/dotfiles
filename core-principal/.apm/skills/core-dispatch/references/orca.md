# orca コマンド早見表と、実測で踏んだ落とし穴

手順そのものの正本は Orca が配っているスキルで、実行中のバイナリと同じ版が出る。

```
orca skills get orca-cli
orca skills get orchestration
```

ここに書くのは、**その早見表と、上のスキルどおりにやって失敗した点**だけ。齟齬が
あったら `orca skills get` のほうが正しい。

## リポジトリを指す — `--repo id:<repoId>` を必ず書く

`orca worktree current` は cwd を Windows 側のホストで解決しようとして
`C:\home\...` を返し、そのまま失敗する。プライマリ workspace は Orca が管理する
worktree の外にあることも多く、`active` / `current` に依存した指定も当てにならない。
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

## 投げっぱなしで出す

戻りを待たずに走らせてよい作業はこちら。作った worktree の第一ターミナルで
エージェントが起き、`--prompt` がそのまま最初のメッセージになる。

```
orca worktree create --repo id:<repoId> --name <kebab-name> --agent claude --prompt "<spec>" --setup run --json
```

- `--name` は必須。作業内容から短い kebab-case を付ける。
- `--agent` を渡したら `orca terminal create` を重ねない。ターミナルは既にある。
  ハンドルは `result.agentTerminalHandle`（古いランタイムは
  `result.startupTerminal.handle` しか返さない）。
- リポジトリ側の setup フックを確実に走らせたいときだけ `--setup run`。

## 監視付きで出す

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

`check` は `--help` を解釈せず inbox を表示する（そのため
`core-principal/tests/harness-check.sh` のフラグ検査はこのサブコマンドを飛ばす）。

`--wait` と `--timeout-ms` でメッセージが来るまでブロックできるが、**プライマリでは
使わない。** 前景で待てばターンが塞がって次の依頼を受けられず、バックグラウンドの
Bash で待たせても **Claude Code のセッションが終われば道連れに消え、完了通知を
取りこぼす**（実測）。

待たなくても起こしてもらえる。Orca はコーディネータ端末のセッションに

> You have N orchestration message. Run `orca orchestration check --run <run_id>`

という通知を自分で注入してくる（実測。heartbeat もこれで届いた）。**これが統合の
正しいトリガー**で、来たら `check` する。取りこぼしはセッション開始時と依頼を
受けた時の拾い直しで回収する。メッセージは inbox に残っているので消えはしない。

## Run を結び直す

コーディネータ側の端末ハンドルもセッション再起動で変わる。ハンドルが変われば Run と
の束縛も切れるので、通知が来ない・`check` が空に見えるときはここを疑う。

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

## 状況を見る

```
orca worktree ps --json
orca orchestration task-list --brief --json
orca orchestration inbox --limit 20 --json
```

`worktree ps` は実行ホストごとに行を返し、末尾の `scope:` 行がどのホストを見たかを
書く。そこに出ていないホストの workspace は「無い」のではなく「見ていない」。

## ハンドルが stale になったとき — 死亡と判定しない

Orca 本体が再起動するとターミナルハンドルが変わる。dispatch に記録されたハンドルは
そのまま古くなり、`orca orchestration worker-list --json` の liveness が
`unverifiable` や `missing_status` になる。**これはワーカーが死んだということでは
ない。** ここで停止や再試行をかけると、生きているワーカーの作業を捨てることになる。

引き直して、自分の目で確かめる:

```
orca terminal list --worktree <selector> --json
orca terminal read --terminal <new-handle> --screen --json
orca terminal wait --terminal <new-handle> --for tui-idle --timeout-ms 60000 --json
```

読んで判断する。作業中なら放っておく。**アイドルなのに worker_done が来ていない
なら、それは落ちたのではなく止まっているので、続きの指示を送って起こす**
（下の `terminal send`）。

## 稼働中のワーカーに追加で言う

```
orca orchestration send --to dispatch:<dispatch_id> --subject "<短く>" --body "<追加指示>" --json
orca terminal send --terminal <handle> --text "<追加指示>" --enter --json
```

監視付きで出したワーカーには `orchestration send`、投げっぱなしのワーカーには
`terminal send`。どちらも届くのは相手が次に受信を見たときで、割り込みではない。
