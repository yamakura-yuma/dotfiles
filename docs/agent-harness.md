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
| 助言フック（ブロックしない） | `dispatch-in-coordinator` | 1 |
| コマンド | `/retro`、`/workers`、`/worktree` | 3 |
| `core-*` スキル | `core-tools`、`core-communication`、`core-harness`、`core-retro`、`core-dispatch` | 5 |
| 取り込んだ公開スキル | `find-skills`、`show-me`、`drawio-skill`、`ponytail*`、Orca のスキル群、日本語文章のスキルなど | `core-principal/apm.yml` 参照 |

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

## 外したガード

`guard-default-branch`、`guard-destructive-git`、`guard-coordinator-edit` の3つ（exit 2 で
止める PreToolUse hook）は意図的に外しました。個人のリポジトリで、エージェントに速く
開発させたいからです。デフォルトブランチへの commit、`git reset --hard`、force push、
`gh pr merge --admin` を止めるものはもうありません。coordinator → 話題チャット →
ワーカーの委任の形は、指示（`core-dispatch` スキルなど）だけで残しています。
資格情報を守る `permissions.deny`（`worker-deny.settings.json`）は残しています。

## 話題チャットの allow

話題チャットは plan で起動し、承認後は auto で動きます（bypass にしません）。auto は分類器が
判定するので、Run の作成・`worker-start`・`~/.claude/worker-reports/` への書き込みが
`[Self-Modification]` や `[Instruction Poisoning]` で止まっていました。公式
（[permission-modes](https://code.claude.com/docs/en/permission-modes)、
[auto-mode-config](https://code.claude.com/docs/en/auto-mode-config)）によると、auto に入るときに
`Bash(*)` のような広い allow は外れ、狭い allow は分類器より先に効きます。`~/.claude/` への
書き込みは保護パスで、allow があっても分類器に回ります。この2つは `soft_deny` で、`autoMode.allow`
で外せます。`autoMode` は `~/.claude/settings.json` からしか読まれません（`.claude/settings.local.json`
では無視）。

| 何を | どこに | どう届く |
| --- | --- | --- |
| `Bash(orca orchestration:*)`、`Bash(.claude/skills/pstack-on-claude-code/scripts/*)` | `pstack-claude/.apm/hooks/scripts/lib/topic-chat.settings.json` | coordinator の `orca.yaml` setup が `.claude/settings.local.json` に merge |
| `autoMode.allow`（worker-reports への書き込み、ワーカーの出動） | `claude/auto-mode.json` | `setup.sh reload`（`claude-settings`）が `~/.claude/settings.json` に merge。`autoMode.allow` を置き換える |

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
