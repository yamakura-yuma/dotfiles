#!/usr/bin/env bash
# PreToolUse(Bash) guardrail: refuse `git commit` / `git push` while HEAD sits on
# the repository's default branch. Registered by ../guard-default-branch.json,
# which `apm install -g` merges into ~/.claude/settings.json.
#
# Contract: exit 2 blocks the tool call and hands stderr back to the agent as
# the reason. Exit 0 means "no opinion", NOT "approved" -- so every condition we
# cannot evaluate confidently falls through to exit 0 rather than guessing.
# `set -e` is deliberately absent: a stray non-zero would exit 1, which Claude
# Code surfaces as a hook error instead of quietly letting the command through.
set -uo pipefail

# Hooks inherit Claude Code's environment, which on some hosts has not picked up
# the Nix profile yet. jq and git both live there.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# The escape hatch is an environment variable rather than a marker file so that
# an agent cannot grant it to itself: this hook inherits Claude Code's
# environment, not the one a Bash tool call builds, so writing
# `DOTFILES_ALLOW_MAIN=1 git push` in a command has no effect here. A human
# exports it before starting Claude Code.
if [ "${DOTFILES_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Matching command text is best effort by design; the hooks documentation says
# as much. Skip past git's own leading options so `git -C dir commit` and
# `git --no-pager push` still register -- note that -C and -c take their value
# as a separate word -- and require the subcommand to start a word of its own,
# so `echo "git commit"` is not caught.
printf '%s' "$cmd" |
  grep -qE '(^|[;&|(]|[[:space:]])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+(commit|push)([[:space:]]|$)' ||
  exit 0

# Take the directory from the payload: ${CLAUDE_PROJECT_DIR} stays pinned to
# where the session started and does not follow Claude into a worktree.
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

# Fails outside a repository and stays empty on a detached HEAD -- neither is a
# case this guardrail has an opinion about.
branch="$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)" || exit 0
[ -n "$branch" ] || exit 0

# refs/remotes/origin/HEAD is a local ref, so reading it costs no network round
# trip. `git remote show origin` reports the same branch but contacts the
# remote, which is far too slow to sit in front of every Bash call.
default="$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
default="${default#origin/}"

if [ -n "$default" ]; then
  [ "$branch" = "$default" ] || exit 0
else
  # No origin/HEAD to consult (no remote, or a clone that never set it up).
  case "$branch" in
    main | master) ;;
    *) exit 0 ;;
  esac
fi

cat >&2 <<EOF
Blocked: '$branch' is the default branch of $cwd, and this repo does not take
commits or pushes directly on it.

Give the work a branch of its own first:
  orca worktree create --agent claude --prompt "<what to do>"
  git worktree add -b <branch> ../<dir>     # when not going through Orca

The human at the terminal can export DOTFILES_ALLOW_MAIN=1 before starting
Claude Code to lift this. You cannot set it yourself -- prefixing the command
with it does not reach this hook.

Command: $cmd
EOF
exit 2
