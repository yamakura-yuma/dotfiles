# 設定リファレンス

どのファイルが何のためにあるか、そしてホスト全体の設定ファイルのどの行を誰が書くかの
一覧です。全体の組み立てを先に見たいときは [architecture.md](architecture.md) から。

## ファイルの役割

| パス | 役割 |
| --- | --- |
| `flake.nix` | nixpkgs にあるツールのまとまり（statusline 用の `jq`、他のツールの土台になる `uv` と `node`、プロンプトの `starship`、図の書き出し用の `drawio` と `xvfb-run`）。`flake.lock` をコミットしてあるので、どのホストでも同じ nixpkgs リビジョンに解決される。更新は `nix flake update` |
| `bin/install-nix.sh` | Nix 本体のインストール。ホストにつき1回 |
| `bin/install-apm.sh` | `apm` を GitHub リリースのバイナリから入れる（nixpkgs に無いため） |
| `claude/statusline.sh` | Claude Code の statusline |
| `claude/telemetry-env.json` | OpenTelemetry トレースの環境変数。`reload` が `~/.claude/settings.json` の `env` にマージする。[トレース](#トレース) |
| `claude/home-CLAUDE.md` | `~/CLAUDE.md` の coordinator 節の正。`reload` が `~/CLAUDE.md` のマーカー間に流し込む |
| `starship.toml` | シェルプロンプトの設定。`kubernetes` モジュールを有効にし、`git_status` を記号ではなく件数で出す。`reload` が `~/.config/starship.toml` にリンクする |
| `shell/prompt.sh` | プロンプトのシェル側。`~/.nix-profile/bin` を `PATH` に入れて `starship init bash` を走らせる。`starship` が未インストールなら何もしないので、途中まで組んだホストでもシェルは壊れない |
| `host-apm.yml` | ホスト全体のマニフェスト。`reload` が `~/.apm/apm.yml` にコピーする。`codegraph` と `headroom` の MCP サーバだけを宣言する（`~/.claude.json` の `mcpServers` はここが正で、あちらを手で編集しない） |
| `apm.yml` | このリポジトリだけに効くマニフェスト。依存は `./core-principal` ひとつ |
| `core-principal/` | エージェント設定一式の独立パッケージ。常時読み込みのルール1つ、ブロックするガードフック3つと助言フック1つ、`/retro`・`/workers`・`/worktree`、`core-*` スキル、そして固定コミットで取り込んだ公開スキル群。詳しくは [agent-harness.md](agent-harness.md) |
| `Makefile` | `make ci` がこのリポジトリの検証 |
| `AGENTS.md` | `apm compile --target agents` の生成物。元を直すこと |
| `versions.env` | グローバルに入れる3ツール（`codegraph`・`graphifyy`・`headroom-ai`）の固定版。`reload` がこれを読む。上げるのは手で、1行の diff として残る |
| `pins.tsv` | `core-principal/apm.yml` の各ピンのコミット日のスナップショット。`make ci` がオフラインで古さを見るためだけにある。`./bin/pins.sh refresh` の生成物 |
| `bin/pins.sh` | ピンの検査。`check` はオフラインで `make ci` から、`refresh` と `latest` はネットワークを使うので手で走らせる |
| `setup.sh` | 唯一の入口。素のシェルで、タスクランナーは使わない |
| `docs/` | この文書群 |

## ホストスコープの設定は誰が書くか

`~/.claude/settings.json` と `~/.claude.json` には、このリポジトリと外部ツールの両方が
書き込みます。**どの行の持ち主が誰なのかはファイルを見ても分からない**ので、ここに書いて
おきます。表の「書き手」以外がその場所を触ると、次の `reload` か `agents-init` で
黙って上書きされます。

| 対象 | 書き手 | いつ |
| --- | --- | --- |
| `~/.claude.json` の `mcpServers` | `apm install -g`（正は `host-apm.yml`。手で編集しない） | `reload` |
| `~/.apm/apm.yml` | `host-apm.yml` のコピー。毎回消してから置き直す | `reload` |
| `~/.claude/statusline.sh` | このリポジトリの `claude/statusline.sh` へのシンボリックリンク | `reload` |
| `~/.claude/settings.json` の `env` のうち `claude/telemetry-env.json` にあるキー | `claude/telemetry-env.json` のマージ（他のキーは触らない） | `reload` |
| `~/CLAUDE.md` のマーカー（`<!-- >>> dotfiles >>> -->`）の間 | `claude/home-CLAUDE.md`（外側は graphify が書くので触らない） | `reload` |
| `./.claude/` と `./.mcp.json` | `apm install`（生成物。gitignore 済み） | `reload` |
| `~/.claude/settings.json` の `PreToolUse` | `graphify install --platform claude` | `agents-init` |
| `ANTHROPIC_BASE_URL` と常駐プロキシ | `headroom install apply` / `headroom init --global claude` | `agents-init` |

`reload` の列は何度走らせても同じ状態に収束します。`agents-init` の列はホストにつき1回で、
外部ツールが自分の流儀で書くところなので、このリポジトリは中身を管理しません。

## 環境変数

ガードフックを外すための2つだけです。Claude Code を起動する前に export してください。
効果と、なぜマーカーファイルではないのかは
[agent-harness.md](agent-harness.md#ガードフック) に。

| 変数 | 効果 |
| --- | --- |
| `MAKURA_ALLOW_MAIN=1` | デフォルトブランチ上での commit / push と、coordinator でのファイル編集を許す |
| `MAKURA_ALLOW_DESTRUCTIVE=1` | 破壊的な git コマンドを許す |

## トレース

このホストの Claude Code はすべて（coordinator もワーカーも）、公式の OpenTelemetry
トレース（beta）を `http://localhost:4318` に OTLP/HTTP で送ります。値は
`claude/telemetry-env.json` にあり、`reload` が `~/.claude/settings.json` の `env` に
マージします。

- 送るもの: `claude_code.interaction` を根に、`llm_request`・`tool`・`hook` の span。
  メトリクスとログは送らない（`OTEL_METRICS_EXPORTER=none`、`OTEL_LOGS_EXPORTER=none`）
- 送らないもの: プロンプト、応答、ツールの入出力。`OTEL_LOG_USER_PROMPTS`・
  `OTEL_LOG_TOOL_DETAILS`・`OTEL_LOG_TOOL_CONTENT` は設定せず、既定の伏せ字のまま
- 受け口が無くても Claude Code は普通に動く。送れなかった span は捨てられる
- 受け側（OTel Collector → Tempo → Grafana）の構築は home-k8s リポジトリの docs を参照

ホスト全体に効く設定は MCP サーバだけ、という方針の例外です。MCP サーバと同じく、
振る舞いを変えず観測という能力を足すだけなので認めています。

止めるには `claude/telemetry-env.json` の `OTEL_TRACES_EXPORTER` を `none` にして
`reload`。マージはキーを足して上書きするだけで消さないので、ファイルからキーを消しても
`~/.claude/settings.json` には残ります。完全に外すなら、あちらの `env` からも手で消して
ください。

## 生成物

次はすべて生成物です。手で編集しても次の実行で消えます。

| パス | 作るもの | git |
| --- | --- | --- |
| `.claude/`、`.mcp.json` | `apm install` | gitignore |
| `apm_modules/` | `apm install` | gitignore |
| `graphify-out/` | `graphify update .` | gitignore |
| `AGENTS.md` | `apm compile --target agents` | コミットする。`make ci` が再生成と突き合わせる |
| `apm.lock.yaml` | `apm install` / `apm update` | コミットする |
