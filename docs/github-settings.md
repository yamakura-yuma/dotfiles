# GitHub リポジトリの設定とブランチ

`bin/github-settings.sh` は `yamakura-yuma` 配下の GitHub リポジトリに 2 つのことをします。

| サブコマンド | 何をするか |
| --- | --- |
| `settings` | 宣言した設定と各リポジトリの現状を比べ、差分を出す。`--apply` で書き込む |
| `branches` | マージ済みの PR の head ブランチを一覧する。`--apply` で削除する |

どちらも既定は dry-run で、GitHub には何も書きません。ホストの `gh` のログインをそのまま使います。
`make ci` は実行しません（GitHub に出るうえ、`--apply` は状態を変えるので）。テストは偽の `gh` を
相手にします。

```bash
./bin/github-settings.sh settings                # 差分を出す。あれば exit 1
./bin/github-settings.sh settings --apply        # 差分を直す
./bin/github-settings.sh branches                # 削除候補を出す
./bin/github-settings.sh branches --apply        # 候補を消す
./bin/github-settings.sh branches --apply home-k8s   # 1 リポジトリだけ
```

終了コードは `0` が成功、`1` が `settings` の dry-run で差分あり（ドリフト検出に使える）、
`2` が使い方の誤り、`3` が GitHub の読み書きの失敗です。

## 対象と設定を足す

対象のリポジトリと宣言する設定は、スクリプトの冒頭の `repos` と `declared` に書いてあります。
リポジトリを増やすなら `repos` に 1 行、設定を増やすなら `declared` に `キー=値` を 1 行足すだけです。
キーは `gh api repos/{owner}/{repo}` のフィールドで、PATCH で書けるもの。今は
`delete_branch_on_merge=true` だけを宣言していて、マージ方式などほかの設定には触れません。

リポジトリ名を引数に渡すと、宣言済みのものに限って絞り込めます。宣言にないリポジトリは拒否します。

## 削除の条件

`branches` は名前の一致だけでは消しません。候補は、次をすべて満たすブランチです。

- このリポジトリでマージ済みの PR の head ブランチである（fork からの PR は数えない）
- 今のブランチの先端 SHA が、その PR の `headRefOid` と一致する。マージ後に同じ名前で
  コミットを積んだブランチを守るため
- default branch でも保護ブランチでもない
- open な PR の head でも base でもない。base を消すとその PR が閉じられるため

名前に英数字と `._/-` 以外が入るものは、URL に載せる際の解釈を避けるため、削除せず報告だけします。
`gh pr list` は 1000 件で打ち切るので、届いたら警告します。それより古い PR のブランチは候補に入りません。

削除したブランチは、実行ログの SHA から復元できます。

## なぜ OpenTofu でなく gh のスクリプトか

マージ済みのブランチが、自動削除の設定が無いまま残り続けていました。`delete_branch_on_merge` を
有効にすれば今後は増えませんが、すでに残っている分は設定では消えません。対象は 5 リポジトリ、
設定は 1 つです。OpenTofu の `github_repository` はリポジトリ全体を管理下に置くので、宣言しなかった属性が
差分に出ます。この規模では、宣言と比較だけのスクリプトのほうが保守するものが少なく、既存の `gh`
のログインで足ります。設定が増えて扱いきれなくなったら、そのとき移ります。
