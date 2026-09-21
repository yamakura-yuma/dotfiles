# README を入口に絞り、詳細を docs/ に分割した

## やったこと

281 行の README.md を 102 行の入口に書き換え、抱えていた詳細を `docs/` 以下の 5 ファイル
に移した。粒度は 1 ファイル 1 話題。

| ファイル | 行数 | 話題 |
| --- | --- | --- |
| `README.md` | 102 | 何をするものか、デモ（`make ci`）、機能の表、最小のインストールと使い方、docs へのリンク、ライセンス |
| `docs/architecture.md` | 121 | 環境の全体像。3 つのスコープ、ホストに何が置かれるか（図）、APM による配布（図）、`host-apm.yml` と `apm.yml` の役割分担、バージョン固定の 4 ファイル、外部ツールとの境界 |
| `docs/agent-harness.md` | 109 | `core-principal` の中身、ルール／スキル／フックの使い分け、配置先、ルートに `./.apm/` を置かない理由、ガードフック、コード探索ツールの順番 |
| `docs/setup.md` | 103 | `setup.sh` のサブコマンド、`~/.bashrc` への追記、更新、ツールごとの 1 回きりの設定、他リポジトリへの導入、activate が要らない理由 |
| `docs/configuration.md` | 67 | 旧「API・設定」。ファイルの役割の表、ホストスコープの設定の書き手、環境変数、生成物 |
| `docs/development.md` | 77 | `make ci` の中身（ターゲット単位の表）、`make eval`、`core-principal` 編集時の `apm_modules/_local` の罠、worktree での注意 |

`docs/architecture.md` は散文の積み上げにせず、ASCII の図 2 枚（正 → 配る仕組み →
ホスト、`.apm/` → `apm install` → `<repo>/.claude/`）と表 4 つを軸にした。

挙動は 1 行も変えていない。`core-principal/` 以下、Makefile、pins.tsv、setup.sh、shell/、
claude/ には触れていない。

## 元の README になかった修正

移すついでに、現物と合っていなかった記述を直した。いずれもファイルを読んで確認済み。

- **フックの数**: 旧 README は「取り返しのつかない git 操作を2つのフックが拒否する」
  「git ガードフック2つ」と書いていたが、実際は `core-principal/.apm/hooks/` に 4 つある。
  ブロックするガードが 3 つ（`guard-default-branch`、`guard-destructive-git`、
  `guard-coordinator-edit`）と、ブロックしない助言フックが 1 つ
  （`dispatch-in-coordinator`、`UserPromptSubmit`）。
- **コマンドの数**: 旧 README は `/worktree` と `/retro` の 2 つとしていたが、
  `.apm/prompts/` には `workers.prompt.md` もあり `/workers` が使える。
- **`MAKURA_ALLOW_MAIN` の効果**: `guard-default-branch` だけでなく
  `guard-coordinator-edit` も外す（両スクリプトで確認）。
- **`make ci` の中身**: 旧 README の列挙に `lint-pins` が抜けていた。
- **`.gitignore` の参照先**: コメントが `(see "Agent harness" in README)` と、存在しない
  節を指していた。`(see docs/configuration.md)` に直した。

`AGENTS.md` には手を入れていない。`apm compile --target agents` の生成物で、README への
パス参照も持っていないため、直す箇所が無かった。

## レビュー #7 の指摘への対応

1. **コミットメッセージ**: 2 つめのコミット `2413376`（メッセージ `add`）を 1 つめに
   squash し、既存の履歴に合わせた英語のコミットに統合した。`2413376` で入った
   `docs/architecture.md` の編集内容（冒頭からホスト名の列挙を外す）はそのまま保持して
   いる。`--force-with-lease` で push し直した。
2. **報告ファイル**: この `.agent/report.md` を書き、コミットして push した。この
   パスはリポジトリの `.gitignore` に入っているため、`git add -f` で明示的に追跡させて
   いる。

## 検証

```
$ make ci
...
all checks passed
EXIT=0
```

squash 後の作業ツリーで再実行して緑。

新しい worktree には `apm_modules/` が無く、最初は `test-harness` が
`apm compile --target agents did not succeed on a clean copy` で落ちた。指示どおり
`apm install` を 1 回入れてから再実行して緑になった。

`apm install` は `apm.lock.yaml` の `deployed_file_hashes` を 8 行書き換えたが、これは
このタスクと無関係な既存のドリフトなので `git checkout --` で戻した。戻した状態でも
`make ci` は exit 0。

リンクは全件を機械的に検査した。`README.md` と `docs/*.md` の相対リンク（アンカー付きを
含む）は 14 本あり、すべて実在するファイルと実在する見出しを指している。外部 URL は
対象外。

## 残っている問題

- **README と architecture.md でホストの記述がずれている**。`2413376` で
  `docs/architecture.md` からホスト名の列挙（WSL、ubuntu、ZCU104）が外されたが、
  `README.md` は「対象は WSL、ubuntu、ZCU104 など。」のまま。意図が「具体名を出さない」
  なら README も揃えるべきだが、指示の範囲外なので触っていない。
- `2413376` の編集で `docs/architecture.md` の 3 行目が、他の行の折り返し幅（約 90 桁）を
  超えて 1 行に伸びている。「対象は 複数のホストで、」の空白も含め、意図的かどうか
  判断できないので原文のままにした。
- `make eval` は走らせていない。実 API を叩いて課金されるうえ、今回の変更は
  `core-principal/.apm/` に触れていないので振る舞いは変わらない。
- `lint-pins` が `humanizer-ja` のピンを 182 日で stale と報告する。元からの警告で、
  失敗にはならない。今回の範囲外。
