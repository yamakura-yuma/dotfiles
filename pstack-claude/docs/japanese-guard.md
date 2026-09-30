# japanese-guard

Claude Code の Stop hook。そのターンの最終回答が英語主体なら、終了を止めて日本語で
書き直させる。差し戻しは 1 ターンに 1 回だけ。

| | |
|---|---|
| 上流 | https://github.com/minorun365/claude-code-japanese-guard |
| 固定したコミット | `e68864a6709768e14d437800ba1bad1cea3cd1a8` |
| ライセンス | Apache-2.0。`LICENSE` と `NOTICE` をスクリプトの隣に `japanese-guard.LICENSE`、`japanese-guard.NOTICE` として置き、hook と一緒に配布する |
| 写したもの | `hooks/japanese-guard.py` → `.apm/hooks/scripts/japanese-guard.py`、`tests/test_japanese_guard.py` → `tests/japanese-guard/`。どちらも改変しない。`tests/check.sh` が sha256 で確かめ、上流のテストも走らせる |

上流 README の手順（`~/.claude/hooks/` と `~/.claude/settings.json` に書く）には従わない。
上流にはマニフェストが無く apm の依存にできないので、写して `.apm/hooks/japanese-guard.json`
から呼ぶ。`apm install` でこのパッケージに依存するリポジトリの `.claude/settings.json`
にだけ入る。

上流を上げるときは、`ref` の代わりに 2 ファイルを写し直し、この表と `tests/check.sh`
の sha256 を書き換える。

## 閾値

使う側のリポジトリの環境（`.claude/settings.json` の `env` など）で変える。

| 変数 | 既定 | 意味 |
|---|---|---|
| `JAPANESE_GUARD_MIN_LATIN` | `25` | 英字がこれ未満の本文は判定しない |
| `JAPANESE_GUARD_RATIO` | `3` | 英字の数が日本語の文字数のこの倍を超えたら英語主体とみなす |
| `JAPANESE_GUARD_WAIT` | `3` | 最終回答が transcript に書き込まれるのを待つ秒数 |

## 無効にする

上流に切り替えスイッチは無く、apm は依存の hook を 1 つだけ外せない。
`JAPANESE_GUARD_MIN_LATIN=999999` にすれば判定に届かず常に通る。
`.claude/settings.json` から hook を手で消しても、次の `apm install` で戻る。

## 判定を手で試す

```bash
python3 .claude/hooks/pstack-claude/.apm/hooks/scripts/japanese-guard.py --check <transcript.jsonl>
```
