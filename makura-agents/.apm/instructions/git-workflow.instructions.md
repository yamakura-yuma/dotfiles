---
applyTo: "**"
description: "Work on a branch; leave the four irreversible git commands alone. Details in the git-workflow skill"
---

変更に着手する前に作業用のブランチか worktree を用意し、その上で commit / push する。
デフォルトブランチ上での `git commit` / `git push` は PreToolUse hook が exit 2 で拒否する。

作業がどこにも残らなくなる次の 4 つは、安全な代替に置き換える。もう 1 本の hook
（`guard-destructive-git`）が拒否する。

| 拒否されるもの | 代わりに使う |
| --- | --- |
| `git reset --hard` | `git stash push -u` / `git reset --soft <commit>` |
| `git clean -f`（`-fd` / `-fdx`） | まず `git clean -nd` で消えるものを見る |
| `git checkout -- .` / `git restore .` | パスを 1 つ指定した `git restore <path>` |
| `git push --force` | `git push --force-with-lease` |

hook はプロジェクトスコープで、makura-agents を導入したリポジトリにしか効かない。
導入していないリポジトリでも同じ規律で進めること。

hook がどう判定するか、通る操作との境目、人間が例外を許可する方法は `git-workflow`
スキルにある。拒否されたらそれを読む。
