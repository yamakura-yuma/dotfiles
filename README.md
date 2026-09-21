# dotfiles

複数のホストとリポジトリで共有する「エージェント環境」を、宣言的に組み立てるための
リポジトリ。対象は WSL、ubuntu、ZCU104 など。

プロジェクト固有のツールチェーンはここに置きません。それぞれのプロジェクトの
`flake.nix` や `.devcontainer/` の仕事です。ここにあるのは、どのリポジトリで作業しても
同じであってほしいもの、つまりエージェントの設定、ホスト共通のツール、シェルの見た目
だけ。

## デモ

`make ci` がこのリポジトリの検証。決定的で、ネットワークに出ず、CI と人間が同じ
コマンドを叩きます。

```console
$ make ci
== shell syntax
== executable bits
== json well-formed
== yaml well-formed
== instruction frontmatter
== pins
pins ok
== guard hooks
guard hooks OK
== harness invariants
harness invariants ok
== statusline
statusline tests ok
all checks passed
```

エージェント設定は手で書かず、APM のプリミティブとして書いて `apm` に配らせます。
`core-principal/` の中身が、インストールしたリポジトリの `./.claude/` に展開される。

```
core-principal/.apm/  →  apm install  →  <repo>/.claude/
```

## 機能・特徴

| | |
| --- | --- |
| エージェント設定をパッケージとして配る | ルール、スキル、コマンド、フックはすべて `core-principal` という独立した APM パッケージにある。このリポジトリ自身も最初の利用者にすぎない |
| 取り返しのつかない git 操作を拒否する | 3つのガードフックが、デフォルトブランチ上での commit / push、どこにも残っていない作業を消すコマンド、coordinator でのファイル編集を止める |
| コード探索のツールが、意識せず効く | `graphify` / `codegraph` / `headroom` を入れるだけでなく、どれをいつ使うかの順番をルールが決めている |
| ホストを跨いだ作業は Orca が持つ | オーケストレーション層はここに無い。Orca 自身が公開するスキルを依存に入れてあるので、CLI とずれない |
| 同じコミット＝同じツールチェーン | `flake.lock`、`versions.env`、`apm.lock.yaml`、`pins.tsv` で固定する |

## インストール・セットアップ

```bash
git clone <this-repo> ~/dotfiles   # 置き場所は任意。setup.sh は場所に依存しない
cd ~/dotfiles
./setup.sh                          # 初回の multi-user Nix インストールに sudo が要る
```

サブコマンドの一覧、`~/.bashrc` への追記、外部ツールの1回きりの設定は
[docs/setup.md](docs/setup.md) に。

## 使用方法

```bash
./setup.sh reload   # 設定やツールを更新したあと。再実行は安全
make ci             # 変更を出す前の検証
```

Claude Code のセッションからは `/retro`（振り返って、学んだことをチェック・ルール・
スキルのどこに置くか決める）、`/worktree`（Orca の新しい worktree にタスクを渡す）、
`/workers`（出したワーカーの状況を拾い直す）が使えます。

他のリポジトリでこのハーネスを使うには、そのリポジトリの `apm.yml` に `core-principal`
を足して `apm install` します。展開先は常にそのリポジトリの `./.claude/` で、`~/.claude/`
には何も置きません。書き方は
[docs/setup.md](docs/setup.md#他のリポジトリでこのハーネスを使う) に。

## ドキュメント

| | |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | 環境の全体像。3つのスコープ、ホストに何が置かれるか、APM による配布、バージョンの固定、外部ツールとの境界 |
| [docs/agent-harness.md](docs/agent-harness.md) | `core-principal` の中身。ルール・スキル・フックの使い分け、配置先、ガードフック |
| [docs/setup.md](docs/setup.md) | インストールと更新。`setup.sh` のサブコマンド、他のリポジトリへの導入 |
| [docs/configuration.md](docs/configuration.md) | 設定リファレンス。ファイルの役割、ホストスコープの設定の書き手、環境変数 |
| [docs/development.md](docs/development.md) | 開発と検証。`make ci` の中身、`core-principal` を編集するときの罠 |

パッケージ側の設計の根拠は [core-principal/README.md](core-principal/README.md) に
あります。

## 貢献方法

変更を出す前に `make ci`。最初の失敗で止めずに全部見たいときは `make -k ci`、個別の
ターゲットは `make help`。中身は [docs/development.md](docs/development.md) に。

## ライセンス・作者情報

作者は yyamakura。個人のホスト環境を組むためのリポジトリなので、LICENSE ファイルは
置いていません。

取り込んでいる公開スキルはそれぞれ上流のライセンスに従います。依存とそのコミットは
`core-principal/apm.yml` にあり、上流の出どころは同じファイルのコメントに書いてあります。
