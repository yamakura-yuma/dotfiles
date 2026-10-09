#!/usr/bin/env bash
# Launch Claude Code on Haiku 5.5 without the headroom proxy.
#
# headroom (up to 0.40.0) has no `claude-haiku-5` in its model allow-list in
# proxy/helpers.py, so it moves the system entries Haiku 5.5 sends inside
# `messages[]` (including `tool_addition`) into the top-level `system`, and the
# API answers 400 ("system.4.type: Input should be 'text'"). Every other model
# is unaffected, so only Haiku goes around the proxy.
#
# An exported ANTHROPIC_BASE_URL cannot do this: `env` in ~/.claude/settings.json
# overrides the shell environment (see docs/setup.md, headroom), so the base URL
# has to come in through --settings, which ranks above it.
#
# `./setup.sh reload` links this to ~/.local/bin/claude-haiku-direct. Extra
# arguments go to claude as-is (-p, --resume, ...).
exec claude --model claude-haiku-5-5 \
  --settings '{"env":{"ANTHROPIC_BASE_URL":"https://api.anthropic.com"}}' "$@"
