# 開発と検証

```bash
make ci          # 決定的なもの全部（lint + test）
make -k ci       # 最初の失敗で止めず、全部報告する
make metrics     # ~/.claude/projects のセッションログを数える（ARGS=--json で JSON）
make eval        # 振る舞いの eval。実 API を叩くので課金される
make install     # このマシンに配る（= ./setup.sh）
make help        # ターゲット一覧
```

検証は開発プロセスの側にあって、エージェント専用の儀式ではありません。`make ci` は人が
打つコマンドであり、CI が走らせるコマンドであり、エージェントに走らせるコマンドでもある。
名前が1つで入口も1つです。

`make ci` は何も変更しません。`apm install` も `./setup.sh reload` もしない。だから
`make install` が別のターゲットになっています。

## `make ci` の中身

| ターゲット | 見るもの |
| --- | --- |
| `lint-shell` | シェルスクリプトの構文（`bash -n`） |
| `lint-exec` | フックスクリプトとテストの実行ビット |
| `lint-json` | JSON がパースできるか（`jq empty`） |
| `lint-yaml` | YAML がパースできるか |
| `lint-frontmatter` | instruction に `applyTo:` と `description:` があるか |
| `lint-pins` | `pins.tsv` を読んでピンの古さを報告する（オフライン。報告だけで失敗にはしない） |
| `test-guards` | `core-principal/tests/guards.sh` — dispatch-in-coordinator に payload を食わせる |
| `test-harness` | `core-principal/tests/harness-check.sh` — ハーネスのドリフト |
| `test-statusline` | `claude/tests/statusline.sh` |
| `test-metrics` | `claude/tests/metrics.sh` fixture のログを `claude/metrics.py` に数えさせる |
| `test-nix-tools` | `tests/nix-tools.sh` — 偽の `nix` を相手に `setup.sh nix-tools` を確かめる |
| `test-github-settings` | `tests/github-settings.sh` — 偽の `gh` を相手に `bin/github-settings.sh` を確かめる（GitHub には触れない） |

対象ファイルは `git ls-files --cached --others --exclude-standard` で選びます。コミット前の
新しいファイルも拾い、生成物の `.claude/` や `apm_modules/` には入らないためです。

実行ビットを見ているのは、実行できないフックが黙って fail open するからです。Claude Code
が起動できないので、ガードレールが単に存在しないことになる。本番ではなくここで捕まえたい。

`harness-check.sh` は `AGENTS.md` が現在の instructions の再生成と一致するかを見ます。
ずれていたら `apm compile --target agents` を走らせてください。

## `make metrics`

エージェント評価の第 1 段です。`~/.claude/projects/` のセッションログ（JSONL）を読んで、
プロジェクト別のセッション数とターン数、ツール別の呼び出し数、hook に拒否された回数
（hook スクリプト名ごと）、ツールエラーの数（hook 拒否・権限拒否・その他）を数えます。
LLM も API も使わず、ログは読むだけです。各数値の定義は `claude/metrics.py` の冒頭に
あります。

出力はこのマシンの履歴なので `make ci` には入れていません。`make metrics ARGS=--json`
で機械向けの JSON になります。

## `make eval`

`core-principal/tests/eval/` は別の問いを立てています。パッケージを入れるとエージェントの
振る舞いが実際に変わるのか、です。同じプロンプトを2つのフィクスチャリポジトリ（入れた
ほうと入れないほう）で走らせ、狙った振る舞いが前者にだけ現れることを要求します。

1ケースごとに実 API を叩いて課金されるので `make ci` には入れず、`make eval` にしてあり
ます。書き方は `core-principal/tests/eval/README.md` に。

## `core-principal` を編集するとき

`apm` は path 依存を `apm_modules/_local/` にコピーし、推移的依存をそのコピーから読みます。
`core-principal/apm.yml` にスキルを足しても、install は成功と表示するのに
`.claude/skills/` にも `apm.lock.yaml` にも現れず、エラーも出ません。`version` を上げても
剥がれない。古いコピーを消してから入れ直してください。

```sh
rm -rf apm_modules/_local/core-principal
apm install
```

このパッケージを git ref で取っている側のリポジトリには起きません。

## worktree で作業するとき

`.claude/` と `apm_modules/` は gitignore されているので、新しい worktree にはありません。
Orca が作る worktree では、ルートの `orca.yaml` の `setup`（`apm install`）が展開します。
エージェントは `wait-for-setup` で、setup が終わるまで起動しません。Orca を通さず
`git worktree add` で作った worktree には走らないので、`make ci` の `test-harness` が
`apm compile` で落ちたら、先に `apm install` を1回走らせてください。

索引も同じです。`graphify-out/` や `.codegraph/` は worktree に引き継がれません。必要なら
その場で作ってください。

## 何をどこに足すか

新しく分かったことを、ルール・スキル・検査のどこに置くかは `core-harness` スキルが、
セッションの振り返りから拾い上げる手順は `core-retro` スキル（`/retro`）が持っています。
迷ったら、散文のルールを足す前に `make ci` の検査にできないかを先に考えてください。
