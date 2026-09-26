#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit): refuse to edit files while the session
# sits in a coordinator workspace -- the default branch of an original
# checkout, or a directory in no repository. Work there is handed to a worker
# in a worktree of its own.
#
# The decision is lib/coordinator-workspace.sh, copied byte for byte from
# core-principal so both harnesses agree on where a coordinator is; the tests
# fail if the copies drift. Only the message differs: this package routes
# dispatch to Orca's own orchestration skill instead of core-dispatch.
#
# Exit 2 blocks and hands stderr to the agent. Exit 0 means "no opinion", so
# anything this cannot evaluate lets the call through.
set -uo pipefail

case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

payload="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# Same switch as core-principal's guard: set by the human, before Claude Code.
[ "${MAKURA_ALLOW_MAIN:-}" = "1" ] && exit 0

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
[ -n "$path" ] || exit 0
workspace_path_is_exempt "$path" && exit 0

cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
is_coordinator_workspace "$cwd" || exit 0

where="${WORKSPACE_BRANCH:+the default branch '$WORKSPACE_BRANCH' of $cwd}"
where="${where:-$cwd, which is not inside a repository}"
cat >&2 <<MSG
Blocked: this session is a coordinator ($where), which hands work out rather
than doing it. Files get edited by a worker in a worktree of its own.

Dispatch it through Orca (the \`orchestration\` skill), for example:

  orca worktree create --repo id:<repoId> --name <kebab-name> --agent claude --prompt "<task, done-when>"

Planning, reading and running commands are all still fine -- only file edits
are not. A human can export MAKURA_ALLOW_MAIN=1 before starting Claude Code
to lift this.

File: $path
MSG
exit 2
