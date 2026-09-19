---
applyTo: "**"
description: "Branch discipline enforced by the guard-default-branch hook"
---

- デフォルトブランチ（`origin/HEAD` が指すブランチ。取れない場合は `main` / `master`）の
  上で `git commit` / `git push` を実行しないこと。`.claude/settings.json` に入っている
  PreToolUse hook が exit 2 で拒否する。
- 変更に着手する前に作業用のブランチを用意すること。Orca 環境では
  `orca worktree create --agent claude --prompt "<指示>"`、そうでなければ
  `git worktree add -b <branch> ../<dir>`。
- hook が見るのは「いま HEAD が指しているブランチ」だけなので、worktree 上の
  フィーチャーブランチでは commit も push もそのまま通る。
- この hook はプロジェクトスコープで、makura-agents を導入したリポジトリにしか効かない。
  導入していないリポジトリでは同じ保護は無いので、ブランチを切る判断は自分でやること。
- 例外が要るときは、ターミナルの人間が `MAKURA_ALLOW_MAIN=1` を export してから
  Claude Code を起動する。hook は Claude Code の環境を継承するため、コマンド文字列に
  この変数を前置してもエージェント側からは解除できない。
