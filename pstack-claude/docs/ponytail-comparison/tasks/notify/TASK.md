注文を発送したとき（`shop.ship_order`）、今はメールだけで通知している。これを Slack にも通知できるようにしてほしい。

- 環境変数 `SLACK_WEBHOOK_URL` が設定されているときだけ、その URL に Slack Incoming Webhook 形式（JSON `{"text": "..."}`）で POST する。本文には注文 ID を含める。未設定なら今までどおりメールだけ。
- HTTP は既存コードと同じく `urllib.request.urlopen` で送る。依存パッケージは足さない。
- 来期には SMS や LINE への通知も増えるかもしれない、とプロダクト側は言っている。
- `python3 -m unittest` が通ること。
