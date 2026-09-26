# Claude Code 公式の道具でスキルを監査する

pstack-claude と core-principal を apm で入れた consumer を 1 つずつ作り、公式の道具で
監査した。評価は直列に走らせ、認証情報はコピーしていない（本人のログインのまま）。
agent run は計 23 本、費用は約 $2.6 だった。見込みは 10 本だったが、道具の挙動を確かめる
追加の run が増えた。

## 道具ごとに測れること

「公式」は code.claude.com の docs か `--help` に書かれていること、「観測」は今回走らせて
見えただけの挙動を指す。

| 道具 | 測れる | 測れない | apm で入れたパッケージに使えるか |
|---|---|---|---|
| `/skill-doctor`（`claude -p "/skill-doctor"`） | スキル一覧での 1 行あたりのトークン数、呼ばれた回数、最後に呼ばれた日時（公式）。`disable-model-invocation` のスキルは一覧に載らず、トークン数が `-` になる（観測） | 数えるのはマシン全体の直近 7 日の履歴なので、consumer どうしの比較にならない（観測: 2 つの consumer で `show-me` や `find-skills` の回数がまったく同じだった）。スキルを Read で読んだ場合は数えないので、poteto-mode の原則スキルはいつも 0 回になる（観測） | 使える。consumer のディレクトリで走らせれば、`.claude/skills` を projectSettings として読む（観測） |
| `claude plugin validate <dir>` | プラグインまたはスキルのディレクトリの構造（公式） | 壊れた frontmatter を見逃した（観測: `description: [unclosed` でも `✔ Validation passed`）。厳密な YAML として読めない `description` も通った | 使える。`.apm/skills` をそのまま渡せる |
| `claude plugin eval` | ケースごとに、隔離したセッションで `tool_used: Skill` がそのスキルを呼んだか、trace の正規表現、LLM 採点（公式）。プラグインなしの baseline との差（公式） | Read で読まれたスキルは `tool_used` では拾えないので、trace の正規表現で見る（観測）。hook とルールは載らない（公式: プラグイン以外の設定は何も読まない） | **そのままでは使えない**。対象は `plugin.json` を持つプラグインか、skills-dir プラグインに限られる（公式）。`.claude/skills` や `.apm/` を渡すと「No eval cases found」になる（観測）。scaffold で `.claude/` をワークスペースに置いても、プロジェクトのスキルは読まれなかった（観測）。**代わりに**、apm が展開した skills と agents をプラグインのディレクトリにコピーし、ルールを `append_system_prompt` で渡すと動いた（観測） |
| skill-creator（`run_eval.py`、`quick_validate.py`） | description だけで発火するかを、クエリの集合で測る（skill-creator の SKILL.md）。frontmatter を厳密に検査する | `quick_validate` は Agent Skills 仕様のキーしか許さないので、Claude Code 固有の `disable-model-invocation` や `argument-hint` が全部エラーになる（観測）。`run_eval.py` はプロジェクトの `.claude/commands/` に一時ファイルを書き、`claude -p` を並列に走らせる（コードを読んで確認） | 使える。ただし並列実行が前提なので今回は走らせていない |

## 所見

深刻度の順に並べる。

| # | 深刻度 | 所見 | 根拠 | 対処 |
|---|---|---|---|---|
| 1 | 高 | poteto-mode の下では、一覧に載っているだけのスキルは開かれない。ponytail を 6 スキル足した構成で、`/pstack:poteto-mode` を付けた過剰設計のレビュー依頼を 2 回走らせた。どちらも ponytail の SKILL.md は開かれず、poteto-mode の原則スキル（21〜24 本）と playbook だけが Read された | `claude plugin eval`、trace の正規表現。比較実験（[ponytail.md](ponytail.md)）の 0/6 と一致した | スキルを「入れる」だけでは効かない。poteto-mode に使わせたいスキルは overlay で使う場面を名指しする。[PR #13](https://github.com/yamakura-yuma/dotfiles/pull/13) がこの形になっている |
| 2 | 高 | core-principal の自動発火が 0 だった。`core-tools`（「索引ツールがあれば使って探して」）、`core-communication`（「図か表で説明して」）、`ponytail`（「過剰設計になってない？」）のどれも、description だけではスキルが呼ばれなかった（各 2 回、計 6/6 で未発火）。ルール（`core-principal.md`）を `append_system_prompt` で渡しても、`core-tools` と `ponytail` は 4/4 で未発火だった。名前を出して頼めば呼ばれる（1/1）ので、Skill ツール自体は動いている | `claude plugin eval`、`tool_used: Skill` | 提案に留める。core-principal は変えない約束なので。直すなら、description の最初に使う場面の語を置く（公式 docs は「key use case first」と書いている）。また、ルールの「`core-tools` を使う」を「コードを探す前に `core-tools` スキルを開く」のような動作の指示に変える |
| 3 | 中 | pstack-claude では、`core-tools` は同じ依頼で発火した（1/1）。ルールが Skill 呼び出しで overlay を開かせ、その流れで `core-tools` にも手が伸びたとみられる（推測）。一方で、overlay は poteto-mode の下では開かれないことがある。`/pstack:poteto-mode` で 2 回走らせると、2 回とも `pstack-on-claude-code` を開かずに進んだ。別の 1 回では開いた | `claude plugin eval` | `make skill-eval` の `overlay-read` 採点で見張る。n が少ないので、まだ直さない |
| 4 | 中 | `core-tools`（両パッケージ）と `core-communication` の `description` は、引用符なしのまま `: ` を含む。厳密な YAML パーサー（PyYAML）では読めない。Claude Code は読めている（`/skill-doctor` と `/context` に description の長さが出る）ので、今は実害がない。skill-creator など、ほかの道具では読めない | PyYAML、`quick_validate.py` | 提案。core-principal 側で直し、pstack-claude はバイト一致のコピーなので `tests/check.sh` の都合で同時に直す |
| 5 | 低 | pstack-claude のスキル 71 本のうち 51 本は `disable-model-invocation: true` で、一覧に載らない。一覧に載る 20 本の合計は約 2,100 トークン。core-principal は 31 本すべてが一覧に載り、約 3,200 トークン。うち ponytail の 6 本が約 890 トークンを占める | `/skill-doctor` | なし。pstack の作り（原則は poteto-mode 経由で読む）どおり |
| 6 | 低 | `/poteto-mode` は、プラグインとして読み込むと `/<plugin>:poteto-mode` になる。eval のプロンプトに `/poteto-mode` と書くと「このセッションには無いコマンド」として素通りした | `claude plugin eval` | `tests/skill-eval` のケースは名前空間付きで書いた。apm で入れた通常の利用には影響しない |

## 定常的に回す形

| 何を | どこに | 理由 |
|---|---|---|
| 発火の eval（`pstack-claude/tests/skill-eval/`） | `make skill-eval`（`ARGS=--runs 1` で軽く） | 実際に API を呼ぶので `make ci` には入れない。`make eval` と同じ扱い。今のケースは 2 つで、`locate`（`core-tools` が呼ばれるか）と `overeng-poteto`（poteto-mode の下で `principle-laziness-protocol` と overlay が開かれるか）。1 回あたり約 $0.4 |
| `claude plugin validate` | 入れない | 壊れた frontmatter を通したので、`make ci` に入れても何も守らない |
| `/skill-doctor` | 入れない | マシン全体の履歴を数えるので、決定的な検査にならない。スキルを足したり削ったりするときに手で見る |

`run.sh` は、apm で一時 consumer に展開した `.claude/skills` と `.claude/agents` をプラグインの
形に包み、`pstack-claude.md` ルールの本文を各ケースの `append_system_prompt` に入れてから
`claude plugin eval` に渡す。hook は載らないので、guard 類の検査には使えない。

## 再現

```sh
make skill-eval ARGS="--runs 1"
```

今回の調査で使った core-principal のケースと ponytail 入りの構成は、一時ディレクトリで作って
捨てた。組み方は `run.sh` と同じで、違うのはプラグインに包む consumer だけ。
