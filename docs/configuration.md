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
| `claude/telemetry-env.json` | OpenTelemetry（トレース・メトリクス・ログ）の環境変数。`reload` が `~/.claude/settings.json` の `env` にマージする。[トレース](#トレース) |
| `claude/advisor.json` | advisor のモデル（`advisorModel: "fable"`、お試し）。`reload` が `~/.claude/settings.json` のトップレベルにマージする。[advisor](#advisor) |
| `claude/home-CLAUDE.md` | `~/CLAUDE.md` の coordinator 節の正。`reload` が `~/CLAUDE.md` のマーカー間に流し込む |
| `starship.toml` | シェルプロンプトの設定。`kubernetes` モジュールを有効にし、`git_status` を記号ではなく件数で出す。`reload` が `~/.config/starship.toml` にリンクする |
| `shell/prompt.sh` | プロンプトのシェル側。`~/.nix-profile/bin` を `PATH` に入れて `starship init bash` を走らせる。`starship` が未インストールなら何もしないので、途中まで組んだホストでもシェルは壊れない |
| `bin/claude-haiku-direct.sh` | Haiku 5.5 を headroom を通さず（`--settings` で `ANTHROPIC_BASE_URL` を `https://api.anthropic.com` に）起動する薄いラッパー。`reload` が `~/.local/bin/claude-haiku-direct` に張る。理由は [setup.md](setup.md#ツールごとの1回きりの設定) |
| `host-apm.yml` | ホスト全体のマニフェスト。`reload` が `~/.apm/apm.yml` にコピーする。`codegraph` と `headroom` の MCP サーバだけを宣言する（`~/.claude.json` の `mcpServers` はここが正で、あちらを手で編集しない） |
| `apm.yml` | このリポジトリだけに効くマニフェスト。依存は `./core-principal` ひとつ |
| `core-principal/` | エージェント設定一式の独立パッケージ。常時読み込みのルール1つ、ブロックするガードフック3つと助言フック1つ、`/retro`・`/workers`・`/worktree`、`core-*` スキル、完了前レビューのサブエージェント `completion-reviewer`、そして固定コミットで取り込んだ公開スキル群。詳しくは [agent-harness.md](agent-harness.md) |
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
| `~/.claude/settings.json` の `advisorModel` | `claude/advisor.json` のマージ（`/advisor` で変えても次の `reload` で戻る） | `reload` |
| `~/CLAUDE.md` のマーカー（`<!-- >>> dotfiles >>> -->`）の間 | `claude/home-CLAUDE.md`（外側は graphify が書くので触らない） | `reload` |
| `./.claude/` と `./.mcp.json` | `apm install`（生成物。gitignore 済み） | `reload` |
| `~/.claude/settings.json` の `PreToolUse` | `graphify install --platform claude` | `agents-init` |
| `~/.claude/settings.json` の `ANTHROPIC_BASE_URL`・`ENABLE_TOOL_SEARCH`、headroom の init-user のフックとプラグインの無効化 | `setup.sh headroom-init` | `agents-init` |
| 常駐プロキシ（cache モード、systemd の `headroom-default`）と `.bashrc` などの headroom の env ブロック | `headroom install apply --mode cache` | `agents-init` |

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
トレース（beta）・メトリクス・ログを `http://localhost:4318` に OTLP/HTTP で送ります。値は
`claude/telemetry-env.json` にあり、`reload` が `~/.claude/settings.json` の `env` に
マージします。

- 送るもの: トレースは `claude_code.interaction` を根に `llm_request`・`tool` の span。
  メトリクス（cost・token・lines_of_code・commit・pull_request・active_time・session.count
  など）とログ（user_prompt・tool_result・api_request 等のイベント）。メトリクスは
  Prometheus 向けに `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`。
  `OTEL_METRICS_INCLUDE_REPOSITORY=true` でリポジトリを、`OTEL_METRICS_INCLUDE_SESSION_ID=true`
  でセッション ID を、メトリクスとイベント（ログ）に付ける（スパンには元から付いている）。
  grafana.com 25255 などのセッション系パネルが `session_id` のラベルで数えるので、外すと
  誤った値になる（home-k8s #19）。ラベルの濃度は実測で小さい: worktree とセッションがほぼ
  1 対 1 なので、系列は 1 日に約 1,800 本から約 2,000 本に増える程度で、Loki では
  structured metadata に入るためストリームは増えない。キーを消さずに `true` と書くのは、
  `merge_claude_settings` が足すだけで消さず、消すと settings.json に古い `"false"` が
  残るため。反映は `reload` の後に起動したセッションから有効。
- ワーカー識別: `shell/prompt.sh` が Orca の `ORCA_WORKTREE_ID`（`<uuid>::<path>`）から
  `OTEL_RESOURCE_ATTRIBUTES=orca.worktree.id=<uuid>,orca.worktree.name=<worktree 名>` を
  シェルで export する。settings.json の `env` は静的で、シェルの値を上書きするので使わない。
  新しいシェルから有効。Orca の外では付かない。メトリクスのラベルでは `orca_worktree_name` になる
- 入れていないもの: `ENABLE_BETA_TRACING_DETAILED` / `BETA_TRACING_ENDPOINT`。公式では
  これを有効にすると `tool_input`・`system_prompt_preview` などの中身が span に載り、
  対話 CLI は組織の許可リスト入りが要る。ツール入力の中身までは要らないので見送った。
  `claude_code.hook` span もこの beta の側にある
- 送るもの（内容）: `OTEL_LOG_USER_PROMPTS=1`（依頼文）、`OTEL_LOG_TOOL_DETAILS=1`（Bash の
  コマンド、ファイルパス、skill 名、MCP のサーバ名・ツール名）、`OTEL_LOG_ASSISTANT_RESPONSES=1`
  （応答文。公式ではプロンプトの設定に従うとされるので、明示的に同じ値にした）、
  `OTEL_LOG_TOOL_CONTENT=1`（ツール出力の中身。トレースの `tool.output` span イベントに載る。
  トレースが有効なことが前提で、1 件の上限は 60KB）。
  どの依頼が高くついたか・手戻りしたか、どのコマンドや skill が使われ失敗したかを見て、
  ハーネス・指示・モデル選択を改善する材料にするため。送り先はこの PC の中の
  `localhost:4318` だけで、外には出ない。内容の長さの上限
  （`CLAUDE_CODE_OTEL_CONTENT_MAX_LENGTH`、既定 60KB）は既定のまま。
  秘密の値を伏せる処理は home-k8s 側の Collector の `transform/redact` が担う（このリポジトリの範囲外）。
  `observe-share` で共有している間は、ログインした人に依頼文が見える
- 送らないもの: API の生の本文（`OTEL_LOG_RAW_API_BODIES`）。秘密が入りやすいので設定せず、
  既定のままにしている
- 受け口が無くても Claude Code は普通に動く。送れなかった span は捨てられる
- 受け側（OTel Collector → Tempo → Grafana）の構築は home-k8s リポジトリの docs を参照
- 話題別・役割別のトークン集計は home-k8s の orca-orchestration ダッシュボードにある。役割と話題を
  worktree 名で決めるので、命名を変えると集計が崩れる（`docs/observability/orca-orchestration.md`）

ホスト全体に効く設定は MCP サーバだけ、という方針の例外です。MCP サーバと同じく、
振る舞いを変えず観測という能力を足すだけなので認めています。

止めるには `claude/telemetry-env.json` の `OTEL_TRACES_EXPORTER` を `none` にして
`reload`。内容だけ止めるなら `OTEL_LOG_USER_PROMPTS`・`OTEL_LOG_TOOL_DETAILS`・
`OTEL_LOG_ASSISTANT_RESPONSES`・`OTEL_LOG_TOOL_CONTENT` を `0` にして `reload`。
マージはキーを足して上書きするだけで消さないので、ファイルからキーを消しても
`~/.claude/settings.json` には残ります。完全に外すなら、あちらの `env` からも手で消して
ください。

## advisor

このホストの Claude Code はすべて、Fable を advisor にして動きます（お試し。効果は未確認）。
いつ呼ぶかは主モデルが決め、回数を指定する設定はありません。値は `claude/advisor.json` に
あり、`reload` が `~/.claude/settings.json` のトップレベルにマージします。

役割は作業の前半（方針を決める前、行き詰まったとき）に限ります。完了時点の確認は
`completion-reviewer` サブエージェントが担います。

- advisor は会話全体を自動で渡され、道具を使わず短い助言だけを返す。同じ前提を引き継ぐ
- サブエージェントは依頼文だけを受け取り、自分で調べ、経緯を知らないまま独立して見る
- 完了時点では両者が重なるので、独立していて必ず走るレビューのほうに任せる

Claude Code 組み込みの advisor の説明には「完了を宣言する前にも呼ぶ」が含まれていて、
設定では消せません。実装系のワーカーには、公式の推奨文面から完了時の項目だけを削ったものを
spec に貼り、そちらへ誘導します（`core-dispatch` の「advisor の誘導」）。止めるのではなく
誘導なので、完了時に呼ばれることはあります。

公式（[advisor](https://code.claude.com/docs/en/advisor)）で確かめた制約:

- Fable を advisor にできる主モデル: Sonnet 5.5、Opus 5.5、Fable。Haiku 4.5 も呼べる
- プランによっては、Fable の利用を usage credits に請求することへの 1 回きりの同意が要る。
  同意が無いと advisor なしで動き、エラーにはならない。同意は `/model fable` で続行を選ぶ
- `ANTHROPIC_BASE_URL` 経由（headroom）では、プロキシが要求をそのまま Anthropic API に
  渡すかどうかで使えるかが決まる。`DISABLE_TELEMETRY` などフラグ取得を止める変数があると
  advisor は有効にならない。このホストでは headroom 経由・テレメトリ有効のまま有効になった
  （2026-10-01 に観測）
- 費用: advisor は呼ばれるたびに会話全体をキャッシュなしで読み直す。会話が長いほど 1 回が
  高い（実測で会話 2 万トークン時に約 $0.09）

- 助言は読めない: Fable 5.1・Opus 5.5 などを advisor にすると、結果は暗号化された
  `advisor_redacted_result` で返る（[API ドキュメント](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)の仕様）。
  主モデルはサーバ側で読むが、ログやトランスクリプトからは中身が見えない

お試しの評価は次の 3 つで行います。

| 見るもの | どこで |
| --- | --- |
| 呼ばれた回数 | `claude -p --debug-file <path>` のログの `Advisor tool called` の行数 |
| Fable の費用 | Grafana のモデル別コストの `claude-fable-*` の行。ホスト設定なので `completion-reviewer` が呼んだ分も含む |
| 完了前レビューの必須指摘が減ったか | ワーカーの報告ファイルに貼られた各ラウンドの `required` |

有効になったかは `claude -p --debug-file <path>` のログに `[AdvisorTool] Server-side tool
enabled with claude-fable-5-1 as the advisor model` が出るかで分かります。

止めるには、そのセッションだけなら `/advisor off`、ホスト全体で無効にするなら
`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`。お試しをやめるなら `claude/advisor.json` と
`setup.sh` の `merge_claude_settings` にあるそのマージを消し、`~/.claude/settings.json` の
`advisorModel` も手で消します（マージはキーを消さないので）。

ホスト全体に効く設定は MCP サーバだけ、という方針のもう 1 つの例外です。テレメトリと
違って振る舞いを変えますが、ワーカーごとに入れる手段が無い（`orca orchestration
worker-start` に advisor の指定が無い）ので、お試しの間だけホスト全体に置きます。

## 生成物

次はすべて生成物です。手で編集しても次の実行で消えます。

| パス | 作るもの | git |
| --- | --- | --- |
| `.claude/`、`.mcp.json` | `apm install` | gitignore |
| `apm_modules/` | `apm install` | gitignore |
| `graphify-out/` | `graphify update .` | gitignore |
| `AGENTS.md` | `apm compile --target agents` | コミットする。`make ci` が再生成と突き合わせる |
| `apm.lock.yaml` | `apm install` / `apm update` | コミットする |
