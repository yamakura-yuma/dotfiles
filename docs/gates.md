# PR のゲートと auto merge

AI が書いた PR を、人の手を介さずに auto merge するための型です。各リポジトリはこの型に
沿って自分のゲートを入れます（dotfiles#50 の子チケット）。月額のコストはかけません。

```text
ワーカー ── PR 前に completion-reviewer を 1 回 ──> PR
                                                    │
               GitHub Actions（ubuntu-latest）: just ci ──> 必須チェック
                                                    │
      段階 A・B: チェックが通れば auto merge     段階 C: CODEOWNERS で止まり、人がマージ
```

## 段階

変更をパスで段階に分けます。1 つの PR に複数の段階が混ざったら、いちばん重い段階として扱います。

| 段階 | 対象 | auto merge | 人の承認 |
| --- | --- | --- | --- |
| A | docs、ナレッジ、スキル、リンクの修正 | `just ci` が通れば可 | 要らない |
| B | home-k8s のマニフェストと Helm の values。A にも C にも入らないコードの変更（Go のコードとテスト、`setup.sh`・フック・`bin/`・`Makefile`、`just/` のスクリプトなど） | `just ci` が通り、PR 前に completion-reviewer を 1 回通していれば可 | 要らない |
| C | Secret、ストレージの削除、外部公開（`just share`）、ArgoCD の設定そのもの、ゲート自身（`.github/workflows/**`、justfile の `ci` レシピ、`CODEOWNERS`） | 不可 | 要る |

ゲート自身を C にするのは、AI がゲートを弱める変更を自分で通せないようにするためです。

C は `CODEOWNERS` で表します。B の「AI レビュー 1 回」は CI では見ません（毎回 API を呼ぶと
コストがかかるため）。ワーカーの手順として PR 前に回します。A と B の違いは手順の側にだけあり、
GitHub の設定は同じです。

### リポジトリごとの C のパス

後続のチケットは、次を出発点に自分のリポジトリの `CODEOWNERS` を書きます。パスは
2026-10-03 の main の木から拾ったもので、各チケットで確かめてください。

| リポジトリ | C にするパス |
| --- | --- |
| すべて | `/.github/`（workflow と `CODEOWNERS`）、`/justfile`（`ci` レシピがあるため） |
| home-k8s | `/clusters/kind/argocd/`（ArgoCD の設定）、`/clusters/kind/storage/`、Secret を作るスクリプト（`/just/grafana-secrets.sh` など）、外部公開（`/just/observe-share.sh`、`/just/*.Caddyfile`） |
| dotfiles | `/Makefile`（`make ci` の中身。dotfiles の `just ci` はこれを呼ぶ予定） |
| knowledge-base、temporal-workflow-kit | 共通のものだけ |

`CODEOWNERS` はパス単位なので、「ストレージの削除」のような変更の種類は表せません。
`clusters/kind/storage/` 全体を C にして近似しています。

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
`make ci` を呼ぶだけの `ci` レシピを足す予定です（dotfiles#52）。

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

## GitHub の仕様（Free プランの public リポジトリ）

2026-10-03 に公式ドキュメントで確かめました。対象の 4 リポジトリはどれも個人アカウント
`yamakura-yuma` の public リポジトリです。

### 公式に書いてあること

| 機能 | 引用 | 出典 |
| --- | --- | --- |
| 保護ブランチ | "Protected branches are available in public repositories with GitHub Free and GitHub Free for organizations" | [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) |
| 必須チェック | "After enabling required status checks, all required status checks must pass before collaborators can merge changes into the protected branch." | 同上 |
| 管理者 | "By default, the restrictions of a branch protection rule don't apply to people with admin permissions to the repository" | 同上 |
| code owner のレビュー | "If you do, any pull request that affects code with a code owner must be approved by that code owner before the pull request can be merged into the protected branch." | 同上 |
| ruleset | "Rulesets are available in public repositories with GitHub Free and GitHub Free for organizations" | [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) |
| auto merge | "Auto-merge for pull requests is available in public repositories with GitHub Free and GitHub Free for organizations" | [Automatically merging a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request) |
| auto merge の条件 | "Auto-merge merges a pull request automatically after all required reviews and status checks pass." / "Before you use auto-merge, it must be enabled for the repository." | 同上 |
| auto merge が出る PR | "The option to enable auto-merge is shown only on pull requests that cannot be merged immediately." | 同上 |
| CODEOWNERS | "The people you choose as code owners must have write permissions for the repository." / 置き場は `.github/`、ルート、`docs/` の順に探す | [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) |
| 自分の PR | "Pull request authors cannot approve their own pull requests." | [Approving a pull request with required reviews](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/reviewing-changes-in-pull-requests/approving-a-pull-request-with-required-reviews) |
| 飛ばされた workflow | path や branch の絞り込みで飛ばされた workflow の必須チェックは "Associated checks stay in a "Pending" state and block merging"。対処は "Avoid requiring workflows that can be skipped." | [Troubleshooting required status checks](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks) |
| 再利用 workflow の参照 | "`{owner}/{repo}/.github/workflows/{filename}@{ref}` for reusable workflows in public and private repositories" / "Using the commit SHA is the safest option for stability and security." | [Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows) |
| 再利用 workflow の公開範囲 | 呼ぶ側が public なら呼べるのは public のもの（表 "Caller repository: `public` / Accessible workflows repositories: `public`"） | [Reusing workflow configurations](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations) |
| `env` | "Any environment variables set in an `env` context defined at the workflow level in the caller workflow are not propagated to the called workflow." | 同上 |
| runner の課金 | "GitHub Actions usage is **free** for **self-hosted runners** and for **public repositories** that use standard GitHub-hosted runners." | [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) |
| larger runner | larger runner は "GitHub Team or GitHub Enterprise Cloud plan" のもの | [GitHub-hosted runners](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners) |
| 承認数 | `required_approving_review_count`: "Use a number between 1 and 6 or 0 to not require reviewers." | [REST: Branch protection](https://docs.github.com/en/rest/branches/branch-protection) |

まとめると、必須チェック・auto merge・CODEOWNERS・ruleset は、どれも Free の public
リポジトリで使えると公式に書いてあります。費用は標準 runner なら 0 です。

### 推測（公式の記述が見つからない。各チケットで確かめる）

- **必須チェックの名前**は `<呼ぶ側の job id> / <呼ばれる側の job name>`、つまり上の例なら
  `ci / just ci` になるはず。名前の規則を書いた公式の記述は見つけられませんでした。設定する前に、
  PR を 1 本出して `gh pr checks <番号>` で実際の名前を読んでください。
- **段階 C は人が管理者としてマージする**ことになるはず。PR の作者は（ワーカーも人と同じ `gh`
  のログインを使うので）`yamakura-yuma` で、code owner も `yamakura-yuma` だけです。作者は自分の PR を
  承認できないので、C の PR は承認を満たせず、auto merge でも通常のマージでも止まります。人は
  `enforce_admins` を外したままにして、管理者として要件を飛ばしてマージします。
- **auto merge は管理者の飛ばしを使わない**はず。auto merge の条件は "after all required reviews
  and status checks pass" とあり、管理者が有効にしても C の PR は止まったままのはずです。各チケットで
  C のパスに触る PR を 1 本出して確かめてください。
- **`required_approving_review_count: 0` と `require_code_owner_reviews: true` の組み合わせ**で、
  A・B は承認なし、C は code owner の承認ありになるはず。API の説明は 0 を「レビューを要求しない」
  としているので、code owner のレビューまで外れるかどうかは書かれていません。外れるなら 1 にし、
  A・B が通らなくなる代わりに ruleset で同じことを試します。
- **`enforce_admins` を外していると、エージェントも `gh pr merge --admin` で飛ばせる。**
  GitHub の設定では防げないので、ワーカーの手順で禁じます。

## 各リポジトリでの設定手順（後続チケット用）

dotfiles#51 の作業ではどのリポジトリの設定も変えていません。以下は各チケット（home-k8s#31、
knowledge-base#19、temporal-workflow-kit#12、dotfiles#52）が自分のリポジトリで行う手順です。
**auto merge は最後に、ゲートが落ちる PR を止めると確かめてから有効にします。**

1. `justfile` に `ci` レシピを作り、ローカルで `just ci` が `0` で終わることを確かめる。わざと
   壊して `0` 以外になることも確かめる。
2. 上の `.github/workflows/ci.yml` と、C のパスを書いた `.github/CODEOWNERS` を足す PR を出す。
   `CODEOWNERS` の先頭は `* ` で全体を持たない（持つと A・B も承認が要る）。例:

   ```text
   /.github/   @yamakura-yuma
   /justfile   @yamakura-yuma
   ```

3. その PR の上で必須チェックの名前を読む。

   ```bash
   gh pr checks <PR 番号> -R yamakura-yuma/<repo>
   ```

4. branch protection を入れる（読んだ名前を `context` に）。

   ```bash
   gh api -X PUT repos/yamakura-yuma/<repo>/branches/main/protection --input - <<'EOF'
   {
     "required_status_checks": { "strict": false, "checks": [{ "context": "ci / just ci" }] },
     "enforce_admins": false,
     "required_pull_request_reviews": {
       "required_approving_review_count": 0,
       "require_code_owner_reviews": true
     },
     "restrictions": null
   }
   EOF
   gh api repos/yamakura-yuma/<repo>/branches/main/protection   # 読み戻す
   ```

   `strict` は `false` にします。`true` だと main が進むたびに PR の更新が要り、auto merge が
   止まりやすくなるためです。
5. 確かめる。`just ci` を落とす PR と、C のパスに触る PR を 1 本ずつ出し、どちらも
   `gh pr view <番号> --json mergeStateStatus` が `BLOCKED` になることを見る。見たら閉じる。
6. ここまで確かめてから auto merge を有効にする。

   ```bash
   gh repo edit yamakura-yuma/<repo> --enable-auto-merge
   ```

7. A・B の PR では、ワーカーが `gh pr merge <番号> --auto --squash` を打つ。C の PR では打たず、
   人がマージする。

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

revert の PR も同じゲートを通ります。打ち消す対象が C なら、revert も C です。

home-k8s では、ArgoCD の root Application が GitHub の main を `automated`（`prune`・`selfHeal`）で
同期しているので、revert がマージされれば次の同期で元に戻ります。待てないときは同期を手で起こします。

```bash
argocd app sync <Application 名>   # または ArgoCD の UI で Sync
```

ArgoCD の設定そのものを壊して同期が止まっているときは、自動では戻りません。`just up` が
最初に入れる `clusters/kind/argocd/root.yaml` を `kubectl apply` し直します。
