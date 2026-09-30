# インストールと更新

## 新しいホストに入れる

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
| `./setup.sh reload` | `nix-tools`、シンボリックリンクの張り直し、`apm` と `versions.env` で固定した `codegraph`・`graphifyy`・`headroom-ai` の導入、`host-apm.yml` からの `apm install -g`、チェックアウト内での `apm install`。いつ再実行しても安全で、リポジトリを別の場所に移した後でも動く。別のチェックアウトから打つと、`nix profile` にある `agent-tools*` のうちそのチェックアウトを指さないものを外してから入れ直す（profile はホストに1つなので、worktree から打つと profile がその worktree を指す） |
| `./setup.sh agents-init` | headroom の常駐プロキシと Claude Code ルーティングフック、graphify の Claude Code 統合。長時間動くプロセスを起こすので `reload` には含めない。ホストにつき1回 |
| `./setup.sh`（引数なし） | 上を順に全部。新規ホストのブートストラップ |

statusline と `starship.toml` は `reload` が自動でリンクします。MCP サーバ
（`codegraph`、`headroom`）も `reload` が `host-apm.yml` から `apm install -g` で適用する
ので、`~/.claude.json` を手で編集する必要はもうありません。

## `~/.bashrc` への追記

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

## 更新するとき

```bash
./setup.sh reload   # 設定やツールを更新したあと。再実行は安全
```

`reload` は何度走らせても同じ状態に収束します。`agents-init` はホストにつき1回で、
外部ツールが自分の流儀で書くところなので、このリポジトリは中身を管理しません。どちらが
どこを書くかは [configuration.md](configuration.md#ホストスコープの設定は誰が書くか) に。

## ツールごとの1回きりの設定

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

- **draw.io CLI** は `drawio-skill` が図を PNG / SVG / PDF に書き出すときの前提で、
  nixpkgs の `drawio` と `xvfb-run` として `agent-tools` に入っています。ヘッドレスでは
  `xvfb-run -a drawio -x -f png -o out.png in.drawio` のように `xvfb-run -a` を前置します
  （スキルの troubleshooting と同じ）。`drawio-headless` は使いません。中で呼ぶ
  `xvfb-run --auto-display` が WSL2 でハングしたためです（観測。`-a` なら通る）。CLI が
  無くても、`.drawio` の XML 生成・同期・検査は Python 3 だけで動きます。書き出しだけが
  できません。

## 他のリポジトリでこのハーネスを使う

そのリポジトリの `apm.yml` に足して `apm install` します。

```yaml
dependencies:
  apm:
  - git: https://github.com/yamakura-yuma/dotfiles.git
    path: core-principal
    ref: <commit>
    alias: core-principal
```

展開先は常にそのリポジトリの `./.claude/` で、`~/.claude/` には何も置きません。生成物
なので `.claude/` と `apm_modules/` は gitignore してください。`apm.yml` がまだ無い
リポジトリに1コマンドで入れる方法や、ローカルパスで取る場合の注意は
[`core-principal/README.md`](../core-principal/README.md) に書いてあります。

`apm` はフックのコマンドを `${CLAUDE_PROJECT_DIR}/.claude/hooks/...` に書き換え、これは
セッションを開始したディレクトリに解決されます。つまりこのリポジトリの worktree は、
フックを持ち回るために自前の `apm install` が要ります。

## シェルの activate が要らない理由

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
