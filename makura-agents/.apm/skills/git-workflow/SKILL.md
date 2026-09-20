---
name: git-workflow
description: Git branch discipline and the four irreversible commands the guard hooks refuse -- reset --hard, clean -f, whole-tree checkout/restore, push --force -- with the safe alternative for each, how the hooks decide, and how a human lifts one. Use when starting work, before committing or pushing, or when a git command is blocked.
---

# git の作業規律

- デフォルトブランチ（`origin/HEAD` が指すブランチ。取れない場合は `main` / `master`）の
  上で `git commit` / `git push` を実行しないこと。`.claude/settings.json` に入っている
  PreToolUse hook が exit 2 で拒否する。
- 変更に着手する前に作業用のブランチを用意すること。Orca 環境では
  `orca worktree create --name <名前> --agent claude --prompt "<指示>"`、そうでなければ
  `git worktree add -b <branch> ../<dir>`。
- hook が見るのは「いま HEAD が指しているブランチ」だけなので、worktree 上の
  フィーチャーブランチでは commit も push もそのまま通る。
- この hook はプロジェクトスコープで、makura-agents を導入したリポジトリにしか効かない。
  導入していないリポジトリでは同じ保護は無いので、ブランチを切る判断は自分でやること。
- 例外が要るときは、ターミナルの人間が `MAKURA_ALLOW_MAIN=1` を export してから
  Claude Code を起動する。hook は Claude Code の環境を継承するため、コマンド文字列に
  この変数を前置してもエージェント側からは解除できない。

## 取り返しのつかない git 操作

もう 1 本の PreToolUse hook（`guard-destructive-git`）が、**どこにも残っていない作業を
消すコマンド**だけを exit 2 で拒否する。対象は次の 4 つ。

- `git reset --hard` — 未コミットの変更が全部消える。代わりに `git stash push -u` で
  退避するか、ファイルには触らない `git reset --soft <commit>` を使う。
- `git clean -f`（`-fd` / `-fdx` を含む）— 未追跡ファイルはどのコミットにも無いので、
  消したら戻せない。まず `-f` 無しの `git clean -nd` で何が消えるか確認する。
- `git checkout -- .` / `git restore .` — ツリー全体を戻すもの。ファイルを 1 つ指定した
  `git restore <path>` は通常の操作なので通る。
- `git push --force` — 他人が push したコミットごと上書きする。リモートが動いていたら
  失敗してくれる `git push --force-with-lease` を使うこと。

逆に `git reset --soft`、`git checkout <branch>`、`git push --force-with-lease` は
いずれも作業が残るか自分で失敗するので、hook は素通しする。

散らかった作業ツリーを「掃除」したくなったときが一番危ない。消すのではなく
`git stash push -u -m "<理由>"` で退避してから進めること。例外が要るときは、
ターミナルの人間が `MAKURA_ALLOW_DESTRUCTIVE=1` を export する。
