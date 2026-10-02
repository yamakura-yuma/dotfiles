# PR のゲート。人もエージェントも Actions も `just ci` だけを打つ。
# 型は docs/gates.md。検査の中身は Makefile の `ci`（新しい検査はここに足さない）。
# `make ci` は作業ツリーを変えず、ツールが無ければ落ちる。

set shell := ["bash", "-euo", "pipefail", "-c"]

[private]
default:
    just --list

# PR のゲートと同じ検査（lint とテスト）。中身は `make ci`
ci:
    make ci
