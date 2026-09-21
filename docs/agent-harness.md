# エージェントハーネス

`core-principal/` は、Claude Code の設定一式をまとめた独立の APM パッケージです。
Claude Code の設定ファイルを直接編集することはありません。ルール、スキル、コマンド、
フックはすべてここにあり、`apm install` が各リポジトリの `./.claude/` に展開します。

パッケージ自身の詳しい解説は [`core-principal/README.md`](../core-principal/README.md)
にあります。ここでは、全体の構成と「なぜこの配分なのか」をまとめます。

## 中身

| 種類 | 実体 | 数 |
| --- | --- | --- |
| ルール | `core-principal.instructions.md` | 1 |
| ガードフック（ブロックする） | `guard-default-branch`、`guard-destructive-git`、`guard-coordinator-edit` | 3 |
| 助言フック（ブロックしない） | `dispatch-in-coordinator` | 1 |
| コマンド | `/retro`、`/workers`、`/worktree` | 3 |
| `core-*` スキル | `core-tools`、`core-communication`、`core-harness`、`core-retro`、`core-dispatch` | 5 |
| 取り込んだ公開スキル | `find-skills`、`show-me`、`ponytail*`、Orca のスキル群、日本語文章のスキルなど | `core-principal/apm.yml` 参照 |

## ルール・スキル・フックの使い分け

3つは負担のかかり方が違います。そこで役割を分けています。

| | いつ読まれる・走るか | だから何を置くか |
| --- | --- | --- |
| ルール（instructions） | 毎プロンプト | 数行で完結する規範か、「この場面ではこれを使う」という橋渡しだけ |
| スキル | 必要になったときだけ | 手順、背景、具体例といった嵩のある知識 |
| フック | 対象のツール呼び出しごと | 機械的に判定でき、破られると取り返しがつかないことだけ |

ルールが1つしかないのは、毎プロンプト読み込まれるものを増やしたくないからです。唯一
自分で内容を持っている規範は応答の言語で、これは例外の理由がはっきりしています。
スキルを開くまで英語で答えてしまっては遅いからです。

逆に、**書かないと決めたもの**が2つあります。ガードフックが既に拒否している操作を散文で
繰り返すルールは置きません。強制はフックが行い、ルールはそれを再説明しない。Orca の
まとめも置きません。Orca が自前のスキルを公開しているので、写せばずれるだけです。

## 配置先

`apm` がどのファイルをどこに展開するかは決まっています。

| 元 | 配置先 |
| --- | --- |
| `.apm/instructions/*.instructions.md` | `./.claude/rules/` |
| `.apm/skills/<name>/SKILL.md` | `./.claude/skills/<name>/` |
| `.apm/agents/<name>.agent.md` | `./.claude/agents/<name>.md` |
| `.apm/prompts/<name>.prompt.md` | `./.claude/commands/<name>.md`（`/<name>`） |
| `.apm/hooks/*.json` | `./.claude/settings.json` にマージ |
| `host-apm.yml` の `dependencies.mcp` | `~/.claude.json`（ホスト全体） |

`AGENTS.md` は `apm compile --target agents` の生成物です。手で直さないでください。
`make ci` がクリーンなコピーと突き合わせるので、ずれていれば落ちます。直すのは元の
instructions のほうです。

## ルートに `./.apm/` を置いていない理由

このリポジトリのルートに `./.apm/` はありません。意図的です。中身がどのリポジトリでも
真だと分かったので、コピーを手元に残しても探す場所が2つに増えるだけでした。本当に
このリポジトリ固有のものが出てきたときに、ルートの `./.apm/` を使います。

apm はパッケージの一部だけを配らないので、何かを外に出さない唯一の方法がこれです。
`includes:` でファイルを除外しようとしたことがあり、黙って配られました。

## ガードフック

3つのガードは exit 2 でツール呼び出しをブロックし、理由を stderr でエージェントに返し
ます。

| フック | 拒否するもの | 外す環境変数 |
| --- | --- | --- |
| `guard-default-branch` | デフォルトブランチ上での `git commit` / `git push` | `MAKURA_ALLOW_MAIN=1` |
| `guard-destructive-git` | どこにも残っていない作業を消す4つ（`reset --hard`、`clean -f`、ツリー全体の `checkout --` / `restore`、`push --force`） | `MAKURA_ALLOW_DESTRUCTIVE=1` |
| `guard-coordinator-edit` | coordinator での `Edit` / `Write` / `NotebookEdit` | `MAKURA_ALLOW_MAIN=1` |

`--force-with-lease` と `reset --soft` は通します。線を引いているのは「危なく聞こえるか」
ではなく「復旧できないか」です。

ガードは、判断できないとき（`jq` が無い、リポジトリでない、detached HEAD、ペイロードが
読めない）は exit 0 で素通りします。Claude Code のフックプロトコルで exit 0 は「意見なし」
であって「承認」ではないからです。

外したいときは Claude Code を**起動する前に** export してください。マーカーファイルでは
なく環境変数なのは意図的です。フックは Claude Code の環境を継承するのであって、Bash
ツールの1回の呼び出しが作る環境ではありません。つまりエージェントはコマンドに変数を
前置きしても自分に許可を出せません。

フックが少数で止まっているのも意図的です。ブロックするフックは非対称で、誤検知は
発火するたびに必ずコストを払うのに、防いでいるものは一度も起きなかったかもしれない。
1つずつ場所を勝ち取らせています。理由の全文は
[`core-principal/README.md`](../core-principal/README.md) に。

なお、ガードフックがこのリポジトリの `main` を守るのは、ここに限った話です。
`core-principal` を入れていないリポジトリで開いたセッションには何の保護もありません。

## コード探索のツールが、意識せず効く

`codegraph`、`graphify`、`headroom` は、入れるだけでは半分です。持っていてなお `grep` に
手が伸びるエージェントには意味がない。なので `core-principal` のルールが順番を決めて
います。

| 場面 | 使うもの |
| --- | --- |
| どこを見るか決める | `graphify query`（`graphify-out/` があるとき） |
| ソースそのものを読む | `codegraph explore`（`.codegraph/` があるとき） |
| 索引が無い、索引で当たらない、編集する行の現物が要る | `Read` / `Grep` / `Glob` |

それぞれ何を返すか、worktree がなぜ索引を引き継がないかは `core-tools` スキルに
書いてあります。
