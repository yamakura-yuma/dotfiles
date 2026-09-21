---
description: "Hand a task to a Claude worker in a fresh Orca worktree"
argument-hint: "<ワーカーにやらせる作業>"
---

次の作業を、Orca の新しい worktree 上のワーカーに任せてください。自分でこの作業を
始めないこと。

作業: $ARGUMENTS

手順は `core-dispatch` スキルの「2. 振り分け」にあります。そちらに従ってください。

プライマリ workspace では hook が同じことを毎プロンプト言うので、このコマンドが
要るのは、**プライマリではない場所から明示的に出したいとき**です。
