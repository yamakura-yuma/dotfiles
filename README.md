# dotfiles

複数のホストとリポジトリで共有する「エージェント環境」を、宣言的に組み立てるための
リポジトリ。対象は WSL、ubuntu、ZCU104 など。

プロジェクト固有のツールチェーンはここに置きません。それぞれのプロジェクトの
`flake.nix` や `.devcontainer/` の仕事です。ここにあるのは、どのリポジトリで作業しても
同じであってほしいもの、つまりエージェントの設定、ホスト共通のツール、シェルの見た目
だけ。

## デモ

`make ci` がこのリポジトリの検証。決定的で、ネットワークに出ず、CI と人間が同じ
コマンドを叩きます。

```console
$ make ci
== shell syntax
== executable bits
== json well-formed
== yaml well-formed
== instruction frontmatter
== guard hooks
guard hooks OK
== harness invariants
harness invariants ok
== statusline
statusline tests ok
all checks passed
```

エージェント設定は手で書かず、APM のプリミティブとして書いて `apm` に配らせます。
`core-principal/` の中身が、インストールしたリポジトリの `./.claude/` に展開される。

```
core-principal/.apm/  →  apm install  →  <repo>/.claude/
```

## 機能・特徴

**エージェント設定をパッケージとして配る。** Claude Code の設定ファイルを直接
編集することはありません。ルール、スキル、コマンド、フックはすべて
`core-principal/` という独立した APM パッケージにあり、`apm install` が展開します。
このリポジトリ自身も、他のリポジトリと同じように依存しているだけの最初の利用者です。
だから consumer を壊す変更は、ここのハーネスも壊します。

**取り返しのつかない git 操作を2つのフックが拒否する。** デフォルトブランチ上での
`git commit` / `git push` と、どこにも残っていない作業を消す4つのコマンド
（`reset --hard`、`clean -f`、ツリー全体の `checkout --` / `restore`、`push --force`）。
`--force-with-lease` と `reset --soft` は通します。フックが2つで止まっているのは意図的で、
理由は `core-principal/README.md` に書いてあります。

**コード探索のツールが、意識せず効く。** `codegraph`、`graphify`、`headroom` は、
入れるだけでは半分です。持っていてなお `grep` に手が伸びるエージェントには意味がない。
なので `core-principal` のルールが順番を決めています。どこを見るか決めるのが
`graphify`、ソースそのものを読むのが `codegraph`、索引が無いか外したときが
`Read` / `Grep`。それぞれ何を返すかは `core-tools` スキルに。

**ホストを跨いだ作業は Orca が持つ。** このリポジトリにオーケストレーション層は
ありません。Orca は自前のスキル（`orca-cli`、`orchestration`、`computer-use`、
エミュレータと Linear のもの）を公開していて、どれも `orca skills get <name>` で
`orca` バイナリからバージョンの揃った手順書を読み出す仕組み。だから CLI とずれません。
全部 `core-principal/apm.yml` の依存に入れてあります。オーケストレーションを実行する
リポジトリは、たいていこのリポジトリではないからです。ここに残しているのは
`/worktree` コマンドだけ。

## インストール・セットアップ

```bash
git clone <this-repo> ~/dotfiles   # 置き場所は任意。setup.sh は場所に依存しない
cd ~/dotfiles
./setup.sh                          # 初回の multi-user Nix インストールに sudo が要る
```

`bin/install-nix.sh`、`nix-tools`、`reload`、`agents-init` を順に実行します。個別に叩くのは
どれかをデバッグしたいときだけ。

| サブコマンド | すること |
| --- | --- |
| `./setup.sh install-nix` | Nix 本体を入れる。ホストにつき1回 |
| `./setup.sh nix-tools` | `flake.nix` のバンドル（`jq` / `uv` / `node`）を `nix profile` で入れる |
| `./setup.sh reload` | `nix-tools`、シンボリックリンクの張り直し、`apm` と `versions.env` で固定した `codegraph`・`graphifyy`・`headroom-ai` の導入、`host-apm.yml` からの `apm install -g`、チェックアウト内での `apm install`。いつ再実行しても安全で、リポジトリを別の場所に移した後でも動く |
| `./setup.sh agents-init` | headroom の常駐プロキシと Claude Code ルーティングフック、graphify の Claude Code 統合。長時間動くプロセスを起こすので `reload` には含めない。ホストにつき1回 |
| `./setup.sh`（引数なし） | 上を順に全部。新規ホストのブートストラップ |

statusline と `starship.toml` は `reload` が自動でリンクします。MCP サーバ
（`codegraph`、`headroom`）も `reload` が `host-apm.yml` から `apm install -g` で適用する
ので、`~/.claude.json` を手で編集する必要はもうありません。

`~/.bashrc` はこのリポジトリで管理していません。あなたのもので、ホスト固有の行が並んで
いるからです。代わりに `reload` が印付きのブロックを1つ追記します。

```bash
# >>> dotfiles >>>
[ -r "$HOME/.config/dotfiles/prompt.sh" ] && . "$HOME/.config/dotfiles/prompt.sh"
# <<< dotfiles <<<
```

このパスは `shell/prompt.sh` へのシンボリックリンクで、`reload` が張り直します。だから
ブロックは1度しか書かれず、リポジトリを移動しても生き残る。再実行しても重複せず、
ブロックを消せばプロンプトだけ外れます。反映は新しいシェルから。配線してあるのは
`bash` だけなので、zsh に移るなら `setup.sh` の `hook_bashrc` を直してください。

## 使用方法

```bash
./setup.sh reload   # 設定やツールを更新したあと。再実行は安全
make ci             # 変更を出す前の検証
```

Claude Code のセッションからは `/retro` と `/worktree` が使えます。`/retro` はセッションを
振り返って、学んだことをチェック・ルール・スキルのどこに置くか決めるもの。`/worktree` は
Orca の新しい worktree にタスクを渡します。

他のリポジトリでこのハーネスを使うには、そのリポジトリの `apm.yml` に足して
`apm install` します。

```yaml
dependencies:
  apm:
  - git: https://github.com/yamakura-yuma/dotfiles.git
    path: core-principal
    ref: <commit>
    alias: core-principal
```

展開先は常にそのリポジトリの `./.claude/` で、`~/.claude/` には何も置きません。生成物
なので `.claude/` と `apm_modules/` は gitignore してください。詳しくは
`core-principal/README.md` に。

## API・設定

### ファイルの役割

| パス | 役割 |
| --- | --- |
| `flake.nix` | nixpkgs にあるツールのまとまり（statusline 用の `jq`、他のツールの土台になる `uv` と `node`、プロンプトの `starship`）。`flake.lock` をコミットしてあるので、どのホストでも同じ nixpkgs リビジョンに解決される。更新は `nix flake update` |
| `bin/install-nix.sh` | Nix 本体のインストール。ホストにつき1回 |
| `bin/install-apm.sh` | `apm` を GitHub リリースのバイナリから入れる（nixpkgs に無いため） |
| `claude/statusline.sh` | Claude Code の statusline |
| `starship.toml` | シェルプロンプトの設定。`kubernetes` モジュールを有効にし、`git_status` を記号ではなく件数で出す。`reload` が `~/.config/starship.toml` にリンクする |
| `shell/prompt.sh` | プロンプトのシェル側。`~/.nix-profile/bin` を `PATH` に入れて `starship init bash` を走らせる。`starship` が未インストールなら何もしないので、途中まで組んだホストでもシェルは壊れない |
| `host-apm.yml` | ホスト全体のマニフェスト。`reload` が `~/.apm/apm.yml` にコピーする。`codegraph` と `headroom` の MCP サーバだけを宣言する（`~/.claude.json` の `mcpServers` はここが正で、あちらを手で編集しない） |
| `apm.yml` | このリポジトリだけに効くマニフェスト。依存は `./core-principal` ひとつ |
| `core-principal/` | エージェント設定一式の独立パッケージ。常時読み込みのルール1つ、git ガードフック2つ、`/worktree` と `/retro`、`core-*` スキル、そして固定コミットで取り込んだ公開スキル群 |
| `Makefile` | `make ci` がこのリポジトリの検証 |
| `AGENTS.md` | `apm compile --target agents` の生成物。元を直すこと |
| `versions.env` | グローバルに入れる3ツール（`codegraph`・`graphifyy`・`headroom-ai`）の固定版。`reload` がこれを読む。上げるのは手で、1行の diff として残る |
| `pins.tsv` | `core-principal/apm.yml` の各ピンのコミット日のスナップショット。`make ci` がオフラインで古さを見るためだけにある。`./bin/pins.sh refresh` の生成物 |
| `bin/pins.sh` | ピンの検査。`check` はオフラインで `make ci` から、`refresh` と `latest` はネットワークを使うので手で走らせる |
| `setup.sh` | 唯一の入口。素のシェルで、タスクランナーは使わない |

### 配置先

| 元 | 配置先 |
| --- | --- |
| `.apm/instructions/*.instructions.md` | `./.claude/rules/` |
| `.apm/skills/<name>/SKILL.md` | `./.claude/skills/<name>/` |
| `.apm/agents/<name>.agent.md` | `./.claude/agents/<name>.md` |
| `.apm/prompts/<name>.prompt.md` | `./.claude/commands/<name>.md`（`/<name>`） |
| `.apm/hooks/*.json` | `./.claude/settings.json` にマージ |
| `host-apm.yml` の `dependencies.mcp` | `~/.claude.json`（ホスト全体） |

ルートに `./.apm/` を置いていないのは意図的です。中身がどのリポジトリでも真だと分かった
ので、コピーを手元に残しても探す場所が2つに増えるだけでした。本当にこのリポジトリ固有の
ものが出てきたときに、ルートの `./.apm/` を使います。apm はパッケージの一部だけを配らない
ので、何かを外に出さない唯一の方法がこれです。`includes:` でファイルを除外しようとした
ことがあり、黙って配られました。

### ホストスコープの設定は誰が書くか

`~/.claude/settings.json` と `~/.claude.json` には、このリポジトリと外部ツールの両方が
書き込みます。**どの行の持ち主が誰なのかはファイルを見ても分からない**ので、ここに書いて
おきます。表の「書き手」以外がその場所を触ると、次の `reload` か `agents-init` で
黙って上書きされます。

| 対象 | 書き手 | いつ |
| --- | --- | --- |
| `~/.claude.json` の `mcpServers` | `apm install -g`（正は `host-apm.yml`。手で編集しない） | `reload` |
| `~/.apm/apm.yml` | `host-apm.yml` のコピー。毎回消してから置き直す | `reload` |
| `~/.claude/statusline.sh` | このリポジトリの `claude/statusline.sh` へのシンボリックリンク | `reload` |
| `./.claude/` と `./.mcp.json` | `apm install`（生成物。gitignore 済み） | `reload` |
| `~/.claude/settings.json` の `PreToolUse` | `graphify install --platform claude` | `agents-init` |
| `ANTHROPIC_BASE_URL` と常駐プロキシ | `headroom install apply` / `headroom init --global claude` | `agents-init` |

`reload` の列は何度走らせても同じ状態に収束します。`agents-init` の列はホストにつき1回で、
外部ツールが自分の流儀で書くところなので、このリポジトリは中身を管理しません。

### 環境変数

ガードフックは、判断できないとき（`jq` が無い、リポジトリでない、detached HEAD、
ペイロードが読めない）は exit 0 で素通りします。Claude Code のフックプロトコルで
exit 0 は「意見なし」であって「承認」ではないからです。

外したいときは Claude Code を起動する前に export してください。

| 変数 | 効果 |
| --- | --- |
| `MAKURA_ALLOW_MAIN=1` | デフォルトブランチ上での commit / push を許す |
| `MAKURA_ALLOW_DESTRUCTIVE=1` | 破壊的な git コマンドを許す |

マーカーファイルではなく環境変数なのは意図的です。フックは Claude Code の環境を継承する
のであって、Bash ツールの1回の呼び出しが作る環境ではありません。つまりエージェントは
コマンドに変数を前置きしても自分に許可を出せません。

### ツールごとの1回きりの設定

- **codegraph** は `apm.yml` の MCP サーバが入っていれば、`UserPromptSubmit` フック
  （`codegraph prompt-hook`）が毎プロンプトで動きます。他に設定は要りません。
- **headroom** はホストにつき1回 `./setup.sh agents-init` が要ります。
  `headroom install apply --target claude` が最適化プロキシを常駐サービス
  （systemd / launchd）として入れ、`headroom init --global claude` が恒久フックを入れる
  ので、素の `claude` でも必ずプロキシを通ります。`.bashrc` のシェル関数では拾えない
  非対話の起動（Orca が worktree のターミナルで直接 `claude` を起こす場合など）も
  これで通る。確認は `headroom doctor`。
- **graphify** も `agents-init` が要ります。`graphify install --platform claude` が
  `/graphify` スキルをグローバルに入れ、`graphify claude install` が自動化の部分
  （CLAUDE.md の節と `.claude/settings.json` の `PreToolUse` フック）を足します。後者は
  実行したディレクトリからの相対で書くので、`agents-init` は `$HOME` から実行します。

### シェルの activate が要らない理由

Nix のシステムインストールは `~/.nix-profile/bin` を、対話・非対話を問わず全シェルの
`PATH` に入れます（`/etc/bashrc` か profile.d 経由）。`nix profile install` が置くのは
ただのシンボリックリンクで、activate を要求する shim ではありません。以前使っていた
mise とはここが違いました。`mise activate` は `~/.bashrc` を読むシェルでしか効かず、
非対話の自動化パスを黙って外していた。

プロンプトだけは例外です。`shell/prompt.sh` は `~/.bashrc` から読まれ、非対話シェルでは
早期に return します。プロンプトはそこでは無意味ですし、エスケープシーケンスが
キャプチャした出力を壊すからです。

なお `codegraph` と `headroom` は `~/.claude.json` に裸のコマンド名で登録されています。
つまり `PATH` に同名のバイナリが先にあれば、そちらに落ちます。元のインストールを消す前に
思い出してください。

## 貢献方法

```bash
make ci          # 決定的なもの全部（lint + test）
make -k ci       # 最初の失敗で止めず、全部報告する
make eval        # 振る舞いの eval。実 API を叩くので課金される
```

`make ci` はシェル構文、フックスクリプトの実行ビット、JSON / YAML のパース、instruction の
frontmatter を確認し、`core-principal/tests/guards.sh`（ガードフック）、
`core-principal/tests/harness-check.sh`（ハーネスのドリフト）、`claude/tests/statusline.sh`
を走らせます。個別のターゲットは `make help` に。

`make ci` は何も変更しません。`apm install` も `./setup.sh reload` もしない。だから
`make install` が別のターゲットになっています。

### core-principal を編集するとき

`apm` は path 依存を `apm_modules/_local/` にコピーし、推移的依存をそのコピーから読みます。
`core-principal/apm.yml` にスキルを足しても、install は成功と表示するのに
`.claude/skills/` にも `apm.lock.yaml` にも現れず、エラーも出ません。`version` を上げても
剥がれない。古いコピーを消してから入れ直してください。

```sh
rm -rf apm_modules/_local/core-principal
apm install
```

このパッケージを git ref で取っている側のリポジトリには起きません。

### 知っておくとよいこと

ガードフックがこのリポジトリの `main` を守るのは、ここに限った話です。
`core-principal` を入れていないリポジトリで開いたセッションには何の保護もありません。
また `apm` はフックのコマンドを `${CLAUDE_PROJECT_DIR}/.claude/hooks/...` に書き換え、
これはセッションを開始したディレクトリに解決されます。つまりこのリポジトリの worktree
は、フックを持ち回るために自前の `apm install` が要ります。

## ライセンス・作者情報

作者は yyamakura。個人のホスト環境を組むためのリポジトリなので、LICENSE ファイルは
置いていません。

取り込んでいる公開スキルはそれぞれ上流のライセンスに従います。依存とそのコミットは
`core-principal/apm.yml` にあり、上流の出どころは同じファイルのコメントに書いてあります。
