#!/usr/bin/env bash
# PreToolUse(Bash) guardrail: refuse `git commit` / `git push` while HEAD sits on
# the repository's default branch. Registered by ../guard-default-branch.json,
# which `apm install` merges into the consuming repo's .claude/settings.json.
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
# `MAKURA_ALLOW_MAIN=1 git push` in a command has no effect here. A human
# exports it before starting Claude Code.
if [ "${MAKURA_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

# "Which branch is the default one" is also what decides whether a workspace is
# the coordinator, so the answer lives in one place and both guards read it from there.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

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

# Non-zero covers "not on the default branch" and "cannot tell" alike -- no
# repository, a detached HEAD, an unreadable cwd. Both fall through to exit 0.
workspace_on_default_branch "$cwd" || exit 0

cat >&2 <<EOF
Blocked: '$WORKSPACE_BRANCH' is the default branch of $cwd, and this repo does
not take commits or pushes directly on it.

Hand the work to a worker in a worktree of its own -- see the \`orchestration\`
skill:
  orca worktree create --repo id:<repoId> --name <kebab-name> --agent claude --prompt "<task, done-when, and: write ~/.claude/worker-reports/<name>.md>"
  git worktree add -b <branch> ../<dir>     # when not going through Orca

The human at the terminal can export MAKURA_ALLOW_MAIN=1 before starting
Claude Code to lift this. You cannot set it yourself -- prefixing the command
with it does not reach this hook.

Command: $cmd
EOF
exit 2
