設計案3つ（opus / sonnet / haiku）を並列で作成中です。完了を待ちます。

Throughput checkpoint（Feature step 3）:
- **Blocking first steps.** 設計の合成が終わるまで実装は始めない。
- **Independent workstreams.** n/a。変更は `shop.py` と `test_shop.py` の2ファイルだけで、互いに依存している。
- **Shared mutable state.** n/a。書き込むのは実装担当の1人だけ。
- **Smallest safe decomposition.** ワーカーは1人。20行ほどの変更を分けると、調整の手間が得られるものを上回るため。
1件目の設計案（opus）が届きました。SMS/LINE 向けの抽象化は今は作りません。代わりに非公開の `_post_json` と `notify_slack` を足し、メールを先に送ります。Slack の失敗はログを出すだけで、出荷処理は止めません。残りの2案（sonnet と haiku）はまだ作成中です。
3件目の設計案（haiku）も届きました。形は1件目とほぼ同じです。違いは Slack の失敗の扱いだけです。haiku は例外を黙って握りつぶし、opus は WARNING ログを出します。残りは sonnet の1案です。
3案すべてを通読しました。cross-judge の結果を待っています。

私の採点では candidate-1（opus）が base です。candidate-2 は `email_notifier` や `notify` が pass-through になっています。そのうえ、SMS/LINE がまだ来ていない段階で required/best_effort の2層構造を先取りしているため、design-red-flags の shallow module に当たります。candidate-3 は Slack の失敗を黙って握りつぶすため、障害に誰も気づけません。
発送時の Slack 通知を実装し、`feature` ブランチにコミットしました（`8924638`）。`python3 -m unittest` は5件とも通ります。

**利用者から見た変化。** `SLACK_WEBHOOK_URL` を設定すると、発送のたびに Slack へ `Order 42 shipped` のような通知が届きます。未設定または空文字のときは、これまでどおりメールだけです。Slack が落ちていても発送処理は止まらず、WARNING ログが残ります。メールの送信エラーは今までどおり呼び出し側に伝わり、その場合 Slack には送りません。

**次に触る人が引き継ぐもの。** `shop.py` は3つの部分に分かれました。
- `_post_json` は JSON の組み立て、ヘッダ、`timeout=10` を一か所で持つ。
- `send_email` と `notify_slack` は通知先ごとに1つずつある関数。
- `ship_order` は通知先を順に呼ぶだけ。

SMS や LINE を足すときは、関数を1つ書いて `ship_order` に1行加えれば済みます。

## 設計の選択（architect の arena、3案）

| 案 | 形 | 判定 |
|---|---|---|
| 1（opus） | 共通の送信関数と、通知先ごとの関数 | 採用 |
| 2（sonnet） | 通知用データクラス、`Notifier` 型、必須と任意の2層で振り分ける仕組み | 不採用。中身の薄い層と素通しの関数ばかりで、来るか分からない SMS/LINE を先取りしている |
| 3（haiku） | 案1とほぼ同じ | 不採用。環境変数が空文字でも設定ありとして扱ってしまう。Slack の失敗を黙って握りつぶす |

別モデルの審査役（sonnet）も案1を選びました。ただし審査員はすべて Claude 系なので、この一致の重みは割り引いて見ています。案1には2点だけ手を入れました。
- Slack の本文から顧客のメールアドレスを外し、注文 ID だけにした。Slack はチームのチャンネルなので、個人情報を流さないため。
- `notify_slack` の戻り値をなくした。読む呼び出し元がないため。

## 判断に効いた原則

- **Laziness Protocol。** SMS/LINE は「増えるかもしれない」段階なので、通知先の一覧や共通インターフェースは作りませんでした。
- **Model the Domain。** 送信の細部は `_post_json` に1つだけ置き、通知先ごとに関数を分けました。通知先を増やしても if 文の分岐は増えません。
- **Exhaust the Design Space。** 構造の違う設計を最低2つ比べるルールに従い、案2の多層構造と案1の関数だけの形を並べて比べました。
- **Test Behavior, Not Implementation。**
  - 「最後の呼び出しの URL」だけを確かめていた既存テストを、全リクエストの URL と本文を固定値と比べる形に直した。
  - 環境変数は毎回空にしてから設定する（`clear=True`）。手元のシェルに `SLACK_WEBHOOK_URL` があっても、テストが通ることを実測で確かめた。
  - 実装担当が `notify_slack` の送信処理をわざと外すと、2件のテストが落ちることも確認した。
- **Prove It Works。** モックだけでなく、ローカルに立てた HTTP サーバーに `ship_order` から実際に送りました（`/tmp/arena-notify/e2e.py`）。未設定、設定あり、送信先が落ちている、の3つの場合とも期待どおりでした。

## Throughput checkpoint

- **Blocking first steps.** 設計の合成が終わるまで実装を始めなかった。
- **Independent workstreams.** n/a。変更は互いに依存する2ファイルだけ。
- **Shared mutable state.** n/a。書き込んだのは1人だけ。
- **Smallest safe decomposition.** 実装は sonnet のワーカー1人に任せた。差分は私が読み、テストも自分で再実行した。

## 省いた手順

- `how` は省きました。対象の2ファイルは全文を読み、その内容を grounding にまとめています。
- `interrogate` は省きました。設計で意見が割れなかったためです。
- PR は作っていません。コミットまでと指示されていたためです。
- `deslop` と `no-comments` は skill として実行せず、手作業で見直しました。アサーションを言い直しているだけのコメントを1つと、使っていない変数を消しています。

## 未決事項（既定値で進めたもの）

- **Slack の失敗時。** WARNING ログを出すだけで、再送はしません。気づけるだけで足りないなら、再送やアラートは別の作業として扱います。
- **`status` を書き換える順番。** 既存コードどおり、メールを送る前に `shipped` にしています。そのため、メールが失敗しても `status` は `shipped` のまま残ります。今回の範囲外として触っていません。
