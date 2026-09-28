# ponytail を pstack-claude に入れるか

結論（仮）: **B を採る。** ponytail から `ponytail-review` だけを取り、architect の
設計案を叩く役に限って使う。常時の規範として入れる C は、poteto-mode の下では一度も
読まれず効果が出なかった。試行は各構成・各課題 2 回ずつで、数字は傾向を示すにとどまる。

| 構成 | 中身 | 受け入れテスト | 本体の追加行（平均） | 本体に足された型 | 所要時間（平均） | 費用（平均） |
|---|---|---|---|---|---|---|
| A | pstack-claude のみ | 5/6 | +25 | 2（`NamedTuple` ×2） | 487 秒 | $2.07 |
| **B** | A ＋ `ponytail-review` を設計案のレビューに使う | **6/6** | **+18** | **0** | 456 秒 | $1.91 |
| C | A ＋ ponytail 6 スキルを core-principal と同じ入れ方で | 6/6 | +23 | 1（`NamedTuple`）＋列定義の lambda 表 | 337 秒 | $1.78 |

生データは [`ponytail-comparison/`](ponytail-comparison/) にある。

## 役割の突き合わせ

| ponytail | 何をするか | pstack で近いもの | 重なり | ponytail にしか無いもの |
|---|---|---|---|---|
| `ponytail`（規範） | 要否 → 既存コード → 標準ライブラリ → プラットフォーム機能 → 依存、の順に止まる梯子。頼まれていない抽象を足さない | `principle-laziness-protocol`（削除優先、最小 diff、浅い呼び出し階層）、`principle-subtract-before-you-add` | 大きい | 標準ライブラリとプラットフォーム機能を先に当たる梯子の順序。「最小版を出し、残りの要件を同じ返答で問い返す」 |
| `ponytail-review` | diff から削れるものだけを 1 行 1 件で挙げる（`delete:` `stdlib:` `native:` `yagni:` `shrink:`） | `interrogate` のコード品質の観点（大きな単純化、薄い抽象や素通しの関数の指摘）、`architect` の `design-red-flags.md`（浅いモジュール、素通しのメソッド）、`deslop`（余計なコメントや防御的な検査） | 中くらい | 「使われない設定」「実装が 1 つしかない抽象」という**まだ無い要件への備え**を名指しで削る観点。設計案にもそのまま当てられる短い形式 |
| `ponytail-audit` | リポジトリ全体を対象にした同じレビュー | なし（`interrogate` は diff 単位） | なし | リポジトリ全体の走査 |
| `ponytail-debt` | コード中の `ponytail:` コメントを集めて台帳にする | なし | なし | ある。ただし規範側の `ponytail:` コメントが前提 |
| `ponytail-gain`、`ponytail-help` | 効果の表示、早見表 | なし | なし | 作業には寄与しない |

## 実験

課題は 3 つで、どれも過剰設計を誘う一文を入れてある。

| 課題 | 誘い | 受け入れテスト（エージェントには見せない） |
|---|---|---|
| notify | 「来期には SMS や LINE も増えるかもしれない」 | `SLACK_WEBHOOK_URL` があるときだけ Slack にも POST し、無ければメールだけ |
| export | 「来月 XML も足すので、形式を足しやすく」 | 出力がバイト単位で変わらないこと（非 ASCII、カンマ、空入力） |
| retry | 「回数や待ち時間は後で調整したくなるかも」 | 5xx・タイムアウト・接続エラーはリトライ、4xx はしない、3 回で諦める |

プロンプトは 3 構成で同じで、`/poteto-mode` に「設計は architect スキルで行ってから実装すること」を
添えた。

### 課題別

| 課題 | 構成 | 受け入れ | 本体 +/- | テスト + | 所要時間 | 費用 | 出力トークン |
|---|---|---|---|---|---|---|---|
| export | A | 2/2 | +27/−29 | +20 | 270 秒 | $1.61 | 37.9k |
| export | B | 2/2 | **+12/−21** | +18 | 268 秒 | $1.52 | 34.0k |
| export | C | 2/2 | +25/−28 | +11 | 218 秒 | $1.44 | 31.1k |
| notify | A | 2/2 | +22/−3 | +54 | 536 秒 | $1.83 | 54.9k |
| notify | B | 2/2 | +21/−3 | +48 | 491 秒 | $1.83 | 56.3k |
| notify | C | 2/2 | +22/−3 | +34 | 338 秒 | $1.67 | 39.5k |
| retry | A | 1/2 | +25/−1 | +86 | 654 秒 | $2.78 | 74.6k |
| retry | B | 2/2 | +20/−1 | +82 | 608 秒 | $2.37 | 68.9k |
| retry | C | 2/2 | +22/−1 | +106 | 455 秒 | $2.25 | 58.1k |

- **notify** は 6 本すべてが同じ形に収束した。`_post_json` を切り出し、`notify_slack` を
  1 関数足すだけで、通知先の登録表や基底クラスはどの構成も作っていない。差は出ない課題だった。
- **export** は B だけが、行を作る `_rows` 関数 1 つ（と列名の定数）で済ませた（32 行）。A は 2 回とも、C は 1 回、
  行を表す `NamedTuple` を足した（39〜42 行）。C のもう 1 回は列名と整形関数の対応表を置いた。
- **retry** では、B-retry-1 の設計案から `ponytail-review` が 3 つを削った（失敗時にソケットを
  閉じる補助関数、タイムアウトの定数、判定用の関数）。B-retry-2 では「Lean already. Ship.」で、
  削るものは無かった。A-retry-2 の受け入れ失敗は、理由が文字列の `URLError` を一時的な失敗と
  みなさなかったため。実装側は「理由が `OSError` の `URLError` だけが接続エラー」と判断して
  おり、仕様の読み方の差でもある。

### ponytail が実際に使われたか

| 構成 | ponytail を読んだ・走らせた run | 使われ方 |
|---|---|---|
| B | 6/6 が読み、5/6 が設計案に当てた | 設計案を `ponytail-review` の形式で叩いた。うち 1 本は別の Explore サブエージェントに走らせた |
| C | **0/6** | ponytail のどのスキルも、本体もサブエージェントも一度も開かなかった |

C で読まれなかったのは、poteto-mode が「適用する原則は leaf の SKILL.md を読め」と原則スキルを
名指しで読ませる作りだからだと考えている（推測）。スキル一覧に ponytail が載っていても、
poteto-mode に従う限り手に取る場面が無い。

### 衝突

| 起きたこと | 構成・run |
|---|---|
| `ponytail-review` の判定を理由に、arena の相互採点（cross-judge）を省いた | B-notify-2 |
| overlay の行を読んだのに、`ponytail-review` をスキルとして走らせず「基準だけ自分で当てた」 | B-export-2 |

C では ponytail が読まれなかったので、実行時の衝突は起きていない。ただし本文どうしは次の点で
ぶつかる。規範として効き始めれば表に出るはず。

| ponytail の指示 | pstack の指示 |
|---|---|
| 返答はコードが先、説明は 3 行まで。設計メモを書かない | poteto-mode の「Writing reply」。詳細・トレードオフ・判断を省かず、主張ごとに根拠の種類を書く |
| 手を抜いた箇所に `ponytail:` コメントを残す | poteto-mode の Comments 節と `no-comments`。コードで示せない理由以外のコメントは残さない |
| 自己検査は `assert` の `demo()` 1 つで足り、関数ごとのテストは YAGNI | `principle-test-behavior-not-implementation`、`principle-prove-it-works` |
| 「ACTIVE EVERY RESPONSE」の常時モード | poteto-mode 自身がモード |

## 隔離

- **ユーザー単位の設定**: 各 run に専用の `CLAUDE_CONFIG_DIR` を作り、`~/.claude/.credentials.json`
  だけをコピーした。`~/.claude` のスキル・フック・プラグイン・CLAUDE.md は入らない。起動時の
  init イベントで、プラグインが builtin の 2 つだけ、MCP サーバーが 0 であることを確かめた。
- **環境変数**: `env -i` で `HOME`、`PATH`、`TERM`、`LANG`、`CLAUDE_CONFIG_DIR` 以外を落とした。
  このマシンの `ANTHROPIC_BASE_URL`（headroom による出力圧縮プロキシ）も経由していない。
- **上位ディレクトリ**: fixture は `~` の外に置いたので、`~/CLAUDE.md` は読まれない。
- **/tmp**: arena は `/tmp/arena-<課題>` のような決まったパスに書くので、同じ課題を並列に
  走らせると互いの設計案を読み合う。run ごとに user namespace と mount namespace を切り、
  専用の `/tmp` を bind mount した。
- **認証**: 並列の run がコピーした認証情報を同時に更新し、途中で OAuth が失効した。4 本が
  認証エラーで途中終了したので、認証し直してその 4 本だけを走らせ直した。表の数字は再実行分。

## 再現

```sh
WORK=$(mktemp -d)
pstack-claude/docs/ponytail-comparison/variants.sh "$WORK"   # B と C のパッケージを作る
for c in A B C; do for t in notify export retry; do for r in 1 2; do
  echo "$c $t $r"; done; done; done |
  WORK=$WORK xargs -P 9 -L 1 pstack-claude/docs/ponytail-comparison/run-one.sh
pstack-claude/docs/ponytail-comparison/metrics.py "$WORK"
```

実際の API を呼ぶので費用がかかる（今回は 18 本で約 $34）。`make ci` には入れていない。

`ponytail-comparison/` の中身は次のとおり。

| パス | 中身 |
|---|---|
| `tasks/<課題>/` | 各 run の開始時のコードと `TASK.md` |
| `hidden/<課題>.py` | 受け入れテスト |
| `runs/<構成>-<課題>-<回>/` | `diff.patch`（エージェントの変更）、`reply.md`（最終返答）、`exit.txt`、`hidden.txt` |
| `metrics.tsv` | run ごとの数字。`new_classes` と `new_defs` はテストのクラス・関数も数える |

イベントストリーム全体（run あたり 1 MB 前後）はリポジトリに入れていない。
