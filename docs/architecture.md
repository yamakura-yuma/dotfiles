# アーキテクチャ

このリポジトリが組み立てるのは「エージェント環境」です。対象は 複数のホストで、どのホストでも同じ設定・同じツール・同じシェルになることを狙って
います。プロジェクト固有のツールチェーンは扱いません。それぞれのプロジェクトの
`flake.nix` や `.devcontainer/` の仕事です。

## 3つのスコープ

置かれるものは、生きる範囲で3つに分かれます。どれが誰の持ち物かを見失わないための区切り
であり、このリポジトリの構造はほぼこの3列でできています。

| スコープ | 正はどこか | 配置先 | 適用する操作 |
| --- | --- | --- | --- |
| ホスト全体 | `flake.nix`、`versions.env`、`host-apm.yml`、`starship.toml`、`shell/`、`claude/` | `~/.nix-profile/`、`~/.apm/`、`~/.claude.json`、`~/.config/`、`~/.claude/settings.json` の OpenTelemetry の `env` | `./setup.sh reload` |
| ホストに1回きり | 外部ツール（headroom、graphify）自身が書く | `~/.claude/settings.json`、常駐サービス | `./setup.sh agents-init` |
| リポジトリごと | `core-principal/`（APM パッケージ） | そのリポジトリの `./.claude/` | そのリポジトリでの `apm install` |

`~/.claude/` にエージェント設定を置かないのが方針です。設定は常に、作業しているリポジトリ
の `./.claude/` に展開されます。だから `core-principal` を入れていないリポジトリでの
セッションは、このリポジトリの影響を一切受けません。

## ホストに何が置かれるか

`setup.sh` が唯一の入口です。左が正（このリポジトリの中の、人が編集するファイル）、
右が結果としてホストに現れるもの。

```
   dotfiles（正）                配る仕組み              ホスト（結果）
   ────────────────────────   ──────────────────   ─────────────────────────────
   flake.nix + flake.lock  ──  nix profile      ──  ~/.nix-profile/bin
                                                    （jq / uv / node / starship）
   versions.env            ──  uv tool / npm -g ──  codegraph・graphify・headroom
   host-apm.yml            ──  apm install -g   ──  ~/.apm/apm.yml
                                                    → ~/.claude.json の mcpServers
   starship.toml           ──  symlink          ──  ~/.config/starship.toml
   shell/prompt.sh         ──  symlink + 追記   ──  ~/.config/dotfiles/prompt.sh
                                                    → ~/.bashrc の印付きブロック
   claude/statusline.sh    ──  symlink          ──  ~/.claude/statusline.sh
   claude/telemetry-env.json ── jq でマージ ──  ~/.claude/settings.json の env
   claude/advisor.json     ──  jq でマージ      ──  ~/.claude/settings.json の advisorModel
   apm.yml                 ──  apm install      ──  ./.claude/（このチェックアウト）
```

`~/.bashrc` はこのリポジトリで管理していません。あなたのもので、ホスト固有の行が並んで
いるからです。代わりに `reload` が印付きのブロックを1つ追記します。手順は
[setup.md](setup.md) に。

## エージェント設定の配り方

エージェント設定は手で書かず、APM のプリミティブとして書いて `apm` に配らせます。
`core-principal/` は、このリポジトリの中にありながら、独立した APM パッケージです。

```
   core-principal/.apm/instructions/  ─┐                     ┌─ .claude/rules/
   core-principal/.apm/skills/         ├─ apm install ─→ <repo>/├─ .claude/skills/
   core-principal/.apm/prompts/        │                     ├─ .claude/commands/
   core-principal/.apm/hooks/         ─┘                     └─ .claude/settings.json
```

このリポジトリ自身も、他のリポジトリと同じように依存しているだけの最初の利用者です。
参照の仕方だけが違います。

```
   dotfiles                          他のリポジトリ
   apm.yml:                          apm.yml:
     - path: ./core-principal          - git:  .../dotfiles.git
                                         path: core-principal
                                         ref:  <commit>
        │                                    │
        └────── apm install ─────────────────┘
                     ↓
              <そのリポジトリ>/.claude/
```

つまり consumer を壊す変更は、ここのハーネスも壊します。中身と配置先の対応は
[agent-harness.md](agent-harness.md) に、導入手順は [setup.md](setup.md) にあります。

## ホスト全体とリポジトリの役割分担

マニフェストが2つあるのは、スコープが2つあるからです。

| | `host-apm.yml` | `apm.yml`（リポジトリのルート） |
| --- | --- | --- |
| 宣言するもの | MCP サーバ（`codegraph`、`headroom`）だけ | 依存パッケージ（`./core-principal` ひとつ） |
| 適用するコマンド | `apm install -g`（`reload` が実行） | `apm install` |
| 経由地 | `~/.apm/apm.yml` へコピー | なし |
| 結果 | `~/.claude.json` の `mcpServers` | `./.claude/` |

`~/.claude.json` の `mcpServers` は `host-apm.yml` が正です。あちらを手で編集しても、
次の `reload` で上書きされます。誰がどこを書くかの一覧は
[configuration.md](configuration.md#ホストスコープの設定は誰が書くか) に。

## バージョンの固定

「2つのホストが同じコミットをチェックアウトしたら、同じツールチェーンになる」ことを
4つのファイルで担保しています。

| ファイル | 何を固定するか | 更新の仕方 |
| --- | --- | --- |
| `flake.lock` | nixpkgs のリビジョン（`jq` / `uv` / `node` / `starship`） | `nix flake update` |
| `versions.env` | グローバルに入れる3ツールの版（`graphifyy`・`headroom-ai`・`codegraph`） | 手で1行編集。候補は `./bin/pins.sh latest` |
| `apm.lock.yaml` | `apm install` が解決した依存の実体 | `apm install` / `apm update` の生成物 |
| `pins.tsv` | `core-principal/apm.yml` の各ピンのコミット日 | `./bin/pins.sh refresh`（ネットワークを使う） |

`pins.tsv` は `make ci` がオフラインでピンの古さを見るためだけにあります。古さは報告
するだけで、失敗にはしません。`versions.env` を「最新」にしない理由は、上流がタグを
公開しておらず（`graphifyy` だけで200リリース超）、追従すると `reload` のたびに黙って
アップグレードが起きるからです。

## 外部ツールとの境界

このリポジトリが持たないものを、持たないと決めた理由つきで並べます。

| 持ち主 | 何を | なぜここに無いか |
| --- | --- | --- |
| Orca | worktree の作成、ワーカーの起動、オーケストレーション | Orca が自前のスキル（`orca-cli`、`orchestration` など）を公開していて、`orca skills get <name>` が実行中のバイナリと同じ版の手順書を返す。写すとずれる |
| graphify / codegraph / headroom | 索引の作成、大きな出力の圧縮、MCP サーバの実体 | ツール自身が `agents-init` で自分の流儀で設定を書く。このリポジトリが管理するのは「入れる版」と「使う順番のルール」だけ |
| 各プロジェクト | 言語ランタイム、ビルドツール、依存 | そのリポジトリの `flake.nix` や `.devcontainer/` の仕事 |
| あなた | `~/.bashrc` | ホスト固有の行が並ぶ、あなたのファイル |

オーケストレーション層をここに置かないのは、オーケストレーションを実行するリポジトリが
たいていこのリポジトリではないからです。残しているのは `/worktree` と `/workers` の
コマンドだけで、中身は Orca のスキルに委ねています。
