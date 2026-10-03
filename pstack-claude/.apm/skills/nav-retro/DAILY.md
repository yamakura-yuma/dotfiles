# nav-retro の日次の手順

リポジトリごとに直近 10 セッションを振り返り、ナビゲーションの改善案（探索が長い、古い
ドキュメント）を Issue の候補にする。automation のプロンプトは 1 行:
`.claude/skills/nav-retro/DAILY.md を読み、最後まで従ってください。`

このファイルは公開リポジトリにある。書いてよいのは手順とルールの形だけで、所見は書かない。

## モード

プロンプトで決まる。何も書かれていなければ **report**。

| モード | 何をする | GitHub | 連続日数（state.json） |
|---|---|---|---|
| report（既定） | 手元のレポートと Issue の計画を作る | 読まない・書かない | 進める |
| once（プロンプトに「手動 1 回」とある） | REPEAT と「新しいセッション」の条件を外して計画を作り、**人に見せてから**起票する | 重複の確認で読む。人が承認した分だけ書く | 触らない |

日次の自動起票（REPEAT=3 を満たしたら人を挟まず起票）は、ゲートが動いてから足す。この手順には
入っていない。起票上限は 1 リポ 2 件・全体 3 件（`nav-candidates` が守る）。

## 流れ

```
precheck ── nav-digest ── claude -p /nav-retro（リポごと） ── nav-candidates ── [once のみ] 人に見せて起票
```

以下、`S=.claude/skills/nav-retro/scripts`、`D=$(date +%F)`、
`OUT=~/.claude/worker-reports/nav-retro/$D`（`mkdir -p`）とする。

1. **precheck。** `.claude/skills/pstack-on-claude-code/scripts/routing-facts | jq -r .zone` が
   `red`（使用量 90% 以上）なら、何も書かずにそう報告して終わる。連続日数は進めない。
2. **ダイジェスト。** `$S/nav-digest --out $OUT`。リポごとに 1 行の要約（`repo`、`name`、
   `sessions`、`new_sessions`）が出る。以降は、report では `new_sessions` が 1 以上のリポだけ、
   once では `sessions` が 1 以上のリポだけ扱う。他は飛ばす（飛ばしても連続日数は途切れない）。
3. **振り返り。** 扱うリポごとに 1 回（`root` は `$OUT/<name>.digest.json` の `root`）:

   ```sh
   timeout 900 claude -p "/nav-retro $OUT/<name>.digest.json" \
     --no-session-persistence --model claude-sonnet-5-5 --max-budget-usd 1 \
     --permission-mode dontAsk --allowedTools "Agent Read Grep Glob" \
     --disallowedTools "Edit Write NotebookEdit Bash" \
     --add-dir "$OUT" --add-dir "<root>" --output-format json < /dev/null > $OUT/<name>.claude.json
   ```

   automation の作業ディレクトリ（nav-retro が入っている coordinator の checkout）から打つ。
   対象のリポは `--add-dir` で読むだけにする。`--no-session-persistence` を外さない
   （外すと、この実行自体が翌日の振り返りの材料になる）。失敗したリポは飛ばして続け、
   最後に報告する。
4. **計画。** report: `$S/nav-candidates --date $D --dir $OUT --no-lookup > $OUT/plan.json`。
   once: `$S/nav-candidates --date $D --dir $OUT --once > $OUT/plan.json`。
   `nav-candidates` は `<name>.md`（所見）と `<name>.candidates.json` も `$OUT` に書く。
   やることは、候補の検証と機密の濾過、連続日数の更新（`~/.claude/worker-reports/nav-retro/state.json`）、
   `[nav] <キー>` の重複確認、起票上限の適用、題と本文の組み立て。
5. **報告。** リポごとに状態（`repos[].status`）、候補（キー、連続回数）、捨てた候補と理由、
   `plan.json` の `cost_usd`（最初の 1 週間は費用を見るために必ず書く）を、短い表にして返す。
   report はここで終わる。

## once: 人に見せてから起票する

`plan.json` の `actions` のうち `create` と `comment` を、リポ・題・本文・対象のファイル・件数の
表にして人に見せ、どれを起票するかを聞く（`AskUserQuestion`。Orca の worker なら
`orca orchestration ask`）。承認が無い分は起票しない。**公開リポに書くのは承認の後だけ。**

承認された `create` ごとに（リポは `action.repo`。それ以外のリポに書かない）:

```sh
jq -r '.actions[<i>].body' $OUT/plan.json > $OUT/<name>.<key>.body.md
gh label list -R <repo> --json name -q '.[].name' | grep -qx nav-retro && label='--label nav-retro'
gh issue create -R <repo> --title "<action.title>" --body-file $OUT/<name>.<key>.body.md $label
```

`nav-retro` ラベルがまだ無いリポでは `--label` を付けない（作るのはこの手順の仕事ではない）。
`comment` は `gh issue comment <action.issue> --body "<action.comment>"`。題と本文は `plan.json` の
文字列をそのまま使い、書き足さない・言い換えない。作った Issue の URL を報告に載せる。

coordinator（private）のセッションから出た候補は、`action.repo` が coordinator なので
coordinator にだけ起票される。公開リポの Issue に coordinator の所見が混ざることはない
（ダイジェストがリポごとに分かれているため）。

## 守ること

- `claude -p` の中身（`nav-retro`）は読むだけ。リポのファイルを書き換えない・コミットしない。
- 公開 Issue に載る文章は `nav-candidates` を通ったものだけ。セッションの抜粋、プロンプト、
  他リポのパス、ID、メールアドレス、トークンは書かない。
- `gh` で書くのは once の承認後だけ。report では `gh` を呼ばない。
- 連続日数は「そのリポを見た実行」の連続。使用量や新セッションの有無で飛ばした日は数えず、途切れもしない。
