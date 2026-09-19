---
name: orca-orchestration
description: 複数エージェントを worktree に分けて走らせるときの入口。Orca が持つ orchestration 手順書の場所と、このワークスペース固有の取り決めだけを書いてある。
---

# Orca でオーケストレーションする

**手順書はこのファイルには無い。** 監督ループの権限モデル、worker の義務、
`live` / `unverifiable` / `exited` の判定規則、復旧手順は Orca 本体が持っている。
作業を始める前に必ず取ってきて読むこと。

```
orca skills get orchestration
```

他に `orca-cli` / `orca-linear` / `computer-use` / `orca-emulator` なども
`orca skills get <name>` で取れる。ここに書き写すと必ず古くなるので、写さない。

## このワークスペース固有の取り決め

- **worktree は自分で掘らない。**
  `orca worktree create --name <名前> --agent claude --prompt "<指示>"` か
  `orca orchestration worker-start --worktree new-child` に任せる。Orca が worktree と
  エージェントの起動をまとめて面倒を見る（`--name` は必須）。
- **プライマリはオーケストレーションに徹する。** 実作業は worktree 側のワーカーが行い、
  プライマリは `orca orchestration check --wait` で結果を待つ。
- **デフォルトブランチでは commit / push できない。** guard-default-branch hook が
  exit 2 で拒否する。hook はプロジェクトスコープなので、makura-agents を導入した
  リポジトリでだけ効く。ワーカーは自分の worktree のブランチ上にいるので素通りする。
- **`wsl` 以外のホストにも撒ける。** `orca host list` で接続状態を確認し、
  `worker-start --on <environment>` で配置先を選ぶ。

## ワーカーの報告はファイルに書かせる

**ワーカーには、最終報告を worktree 内の `.agent/report.md` に書かせ、プライマリはその
ファイルを読むこと。** チャット上の報告だけに頼らない。

理由は headroom（`ANTHROPIC_BASE_URL` 経由で全セッションが通る最適化プロキシ）の挙動に
ある。headroom は大きなツール出力を
`[N words compressed to M ... hash=...]` という印に置き換え、原文は後から
`headroom_retrieve` で引く建て付けになっている。しかし実測したところ、**同一セッション
内の約 40 分前のハッシュが `Content not found. It may have expired.` で復元できなかった。**
長時間のオーケストレーションでは、ワーカーの報告が読み返せなくなる時間帯が必ず来る。

ディスク上のファイルなら、Read の出力が圧縮されても読み直せばよいだけなので、この問題を
受けない。したがって:

- ワーカーへの `--prompt` に「終わったら `.agent/report.md` に、やったこと・検証結果・
  残っている問題を書くこと」を必ず含める。
- プライマリは `orca orchestration check` で終了を確認したあと、チャットの要約ではなく
  そのファイルを読む。
- 途中経過が長いワーカーは、同じファイルに追記していけばよい。

`.agent/report.md` はワーカーの作業物なので、リポジトリの `.gitignore` に `.agent/report.md`
を入れておくこと（`.agent/verify.sh` は追跡する）。
