# PR のゲートと auto merge

AI が書いた PR を、人の手を介さずに auto merge するための型です。各リポジトリはこの型に
沿って自分のゲートを入れます（dotfiles#50 の子チケット）。月額のコストはかけません。

```text
ワーカー ── PR 前に completion-reviewer を 1 回（段階 B）──> PR
                                                          │
                     GitHub Actions（ubuntu-latest）: just ci ──> 必須チェック
                                                          │
                                  通れば auto merge（またはワーカーがマージ）
```

## 段階

変更をパスで段階に分けます。1 つの PR に複数の段階が混ざったら、重いほう（B）として扱います。
どちらも人の承認は要らず、`just ci` が通ればマージされます。

| 段階 | 対象 | PR 前の手順 |
| --- | --- | --- |
| A | docs、ナレッジ、スキル、リンクの修正 | 要らない |
| B | A 以外すべて。home-k8s のマニフェストと Helm の values、Secret・ストレージ・外部公開（`just share`）・ArgoCD の設定、ゲート自身（`.github/workflows/**`、justfile の `ci` レシピ）、コード（Go のコードとテスト、`setup.sh`・フック・`bin/`・`Makefile`、`just/` のスクリプトなど） | completion-reviewer を 1 回通す |

B の「AI レビュー 1 回」は CI では見ません（毎回 API を呼ぶと
コストがかかるため）。ワーカーの手順として PR 前に回します。A と B の違いは手順の側にだけあり、
GitHub の設定は同じです。

## `just ci` の約束

| 項目 | 決めたこと |
| --- | --- |
| レシピ名 | `ci`。リポジトリの直下の `justfile` に置く |
| 終了コード | 全部通れば `0`、1 つでも落ちたら `0` 以外。ツールが無いときも黙って飛ばさず落ちる |
| 同じコマンド | 人もエージェントも Actions も `just ci` だけを打つ。Actions 専用の分岐や手順を足さない |
| 中身 | 静的チェックとテストだけ（yaml lint、`helm template`、kubeconform、kube-linter、`go test` など）。クラスタは立てない。AI レビューは入れない |
| 副作用 | 作業ツリーも外部の状態も変えない。ネットワークは依存の取得だけに使う |
| ツールの入れ方 | `just` はローカルでは各リポジトリの flake か開発用コンテナ、Actions では再利用 workflow が入れる。それ以外のツールは `just ci` 自身が用意する（`nix develop -c`、`docker compose run` など）。Actions の runner には Docker が入っている |

既に `ci` 相当のレシピがあるリポジトリ（temporal-workflow-kit）はそれを使います。dotfiles は
`make ci` を呼ぶだけの `ci` レシピを持ちます（dotfiles#52）。

## 再利用 workflow

`.github/workflows/just-ci.yml`（`workflow_call`）がひな形です。checkout して `just` を入れ、
`just ci` を走らせるだけです。runner は `ubuntu-latest` だけを使います。

| 入力 | 既定 | 意味 |
| --- | --- | --- |
| `install-nix` | `false` | `just ci` が `nix develop` を使うなら `true` |
| `just-version` | `1.45.0` | 入れる `just` の版 |

呼ぶ側は `.github/workflows/ci.yml` に次を置きます。`paths` で絞らないこと（後述）。
`@` の後ろは dotfiles の main のコミット SHA にします。

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  ci:
    uses: yamakura-yuma/dotfiles/.github/workflows/just-ci.yml@<dotfiles の commit SHA>
    # with:
    #   install-nix: true
```

呼ぶ側の `env` は呼ばれる側に渡りません（下の公式の記述）。`just ci` が環境変数に頼るなら、
justfile の中で決めてください。

この workflow の job は 1 つです。呼ぶ側の job id が `ci` なら、必須チェックは次の 1 つです。

| 必須チェック | job | 見るもの |
| --- | --- | --- |
| `ci / just ci` | `just-ci` | `just ci` が `0` で終わること |

### 呼ぶ側が SHA を上げるとき

再利用 workflow の job を足したり消したりした版は、`ci.yml` の `@<SHA>` を上げて取り込みます。
必須チェックの名前が変わるときは、**SHA を上げる PR のマージと同時かその前に**、branch protection の
`checks` を新しい名前に合わせてください（後述の更新コマンド）。消えた名前が必須のままだと、
その必須チェックが永遠に `Pending` のままになり、すべての PR が止まります（下の「飛ばされた workflow」）。
足すときは、先に PR を 1 本出して `gh pr checks <番号>` で名前を読んでから `checks` に足します。

## GitHub の仕様（Free プランの public リポジトリ）

2026-10-03 に公式ドキュメントで確かめました。対象の 4 リポジトリはどれも個人アカウント
`yamakura-yuma` の public リポジトリです。

### 公式に書いてあること

| 機能 | 引用 | 出典 |
| --- | --- | --- |
| 保護ブランチ | "Protected branches are available in public repositories with GitHub Free and GitHub Free for organizations" | [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) |
| 必須チェック | "After enabling required status checks, all required status checks must pass before collaborators can merge changes into the protected branch." | 同上 |
| ruleset | "Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations" | [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) |
| auto merge | "Auto-merge for pull requests is available in public repositories with GitHub Free and GitHub Free for organizations" | [Automatically merging a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) |
| auto merge の条件 | "Auto-merge merges a pull request automatically after all required reviews and status checks pass." / "Before you use auto-merge, it must be enabled for the repository." | 同上 |
| auto merge が出る PR | "The option to enable auto-merge is shown only on pull requests that cannot be merged immediately." | 同上 |
| 飛ばされた workflow | path や branch の絞り込みで飛ばされた workflow の必須チェックは "Associated checks stay in a "Pending" state and block merging"。対処は "Avoid requiring workflows that can be skipped." | [Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks) |
| 再利用 workflow の参照 | "`{owner}/{repo}/.github/workflows/{filename}@{ref}` for reusable workflows in public and private repositories" / "Using the commit SHA is the safest option for stability and security." | [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) |
| 再利用 workflow の公開範囲 | 呼ぶ側が public なら呼べるのは public のもの（表 "Caller repository: `public` / Accessible workflows repositories: `public`"） | [Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations) |
| `env` | "Any environment variables set in an `env` context defined at the workflow level in the caller workflow are not propagated to the called workflow." | 同上 |
| runner の課金 | "GitHub Actions usage is **free** for **self-hosted runners** and for **public repositories** that use standard GitHub-hosted runners." | [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| larger runner | larger runner は "GitHub Team or GitHub Enterprise Cloud plan" のもの | [GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners) |

まとめると、必須チェック・auto merge・ruleset は、どれも Free の public
リポジトリで使えると公式に書いてあります。費用は標準 runner なら 0 です。

### 確かめた（2026-10-03、knowledge-base の試しの PR 3 本。マージはしていない）

- **必須チェックの名前**は `<呼ぶ側の job id> / <呼ばれる側の job name>`。`ci / just ci` は
  `gh pr checks` でその名前で出て、必須チェックとして効き、`just ci` を落とす PR（#21）は
  `BLOCKED` になりました。名前の規則を書いた公式の記述は見つけられていません。新しい job の名前を
  必須にするときは、設定する前に PR を 1 本出して `gh pr checks <番号>` で読んでください。

## 各リポジトリでの設定手順（後続チケット用）

dotfiles#51 の作業ではどのリポジトリの設定も変えていません。以下は各チケット（home-k8s#31、
knowledge-base#19、temporal-workflow-kit#12、dotfiles#52）が自分のリポジトリで行う手順です。
**auto merge は最後に、ゲートが落ちる PR を止めると確かめてから有効にします。**

1. `justfile` に `ci` レシピを作り、ローカルで `just ci` が `0` で終わることを確かめる。わざと
   壊して `0` 以外になることも確かめる。
2. 上の `.github/workflows/ci.yml` を足す PR を出す。
3. その PR の上で必須チェックの名前を読む（`ci / just ci` のはず）。

   ```bash
   gh pr checks <PR 番号> -R yamakura-yuma/<repo>
   ```

4. branch protection を入れる（読んだ名前を `context` に）。

   ```bash
   gh api -X PUT repos/yamakura-yuma/<repo>/branches/main/protection --input - <<'EOF'
   {
     "required_status_checks": {
       "strict": false,
       "checks": [{ "context": "ci / just ci" }]
     },
     "enforce_admins": false,
     "required_pull_request_reviews": null,
     "restrictions": null
   }
   EOF
   gh api repos/yamakura-yuma/<repo>/branches/main/protection   # 読み戻す
   ```

   `strict` は `false` にします。`true` だと main が進むたびに PR の更新が要り、auto merge が
   止まりやすくなるためです。

   既に必須チェックを持つリポジトリは、名前だけを更新する。公式は `checks` が置き換えか追加かを
   書いていないので、残したい名前も含めて全部書き、読み戻して揃っていることを確かめる。

   ```bash
   gh api -X PATCH repos/yamakura-yuma/<repo>/branches/main/protection/required_status_checks --input - <<'EOF'
   { "strict": false, "checks": [{ "context": "ci / just ci" }] }
   EOF
   gh api repos/yamakura-yuma/<repo>/branches/main/protection/required_status_checks --jq '.checks[].context'
   ```

5. 確かめる。`just ci` を落とす PR と、通る PR を 1 本ずつ出し、前者は
   `gh pr view <番号> --json mergeStateStatus` が `BLOCKED`、後者は `CLEAN` になることを見る。見たら閉じる。
6. ここまで確かめてから auto merge を有効にする。

   ```bash
   gh repo edit yamakura-yuma/<repo> --enable-auto-merge
   ```

7. ワーカーが completion-reviewer の合格後に、自分で `gh pr merge <番号> --squash --delete-branch`
   を打つ。話題チャットは回収時に `MERGED` を確かめるだけで、代わりにマージしない。

設定を外すときは `gh api -X DELETE repos/yamakura-yuma/<repo>/branches/main/protection` と
`gh repo edit yamakura-yuma/<repo> --disable-auto-merge` です。

## 壊れたときの戻し方

main に入った変更が壊していたら、その変更を打ち消すコミットを PR で入れます。直接 push はしません。

```bash
git switch -c revert-<sha> origin/main
git revert -m 1 <マージコミットの SHA>   # squash マージなら -m 1 は要らない
git push -u origin HEAD
gh pr create --fill
```

revert の PR も同じゲートを通ります。

home-k8s では、ArgoCD の root Application が GitHub の main を `automated`（`prune`・`selfHeal`）で
同期しているので、revert がマージされれば次の同期で元に戻ります。待てないときは同期を手で起こします。

```bash
argocd app sync <Application 名>   # または ArgoCD の UI で Sync
```

ArgoCD の設定そのものを壊して同期が止まっているときは、自動では戻りません。`just up` が
最初に入れる `clusters/kind/argocd/root.yaml` を `kubectl apply` し直します。
