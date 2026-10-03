#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) guardrail: refuse to edit files while the
# session is sitting in the coordinator workspace. The coordinator workspace is the
# orchestration layer -- it hands work to a worker in a worktree of its own and
# reads the report back, so an edit made there is work that landed in the wrong
# place. Registered by ../guard-coordinator-edit.json, which `apm install` merges
# into the consuming repo's .claude/settings.json.
#
# Contract is the same as the other guards: exit 2 blocks the tool call and
# hands stderr back to the agent as the reason. Exit 0 means "no opinion", NOT
# "approved" -- so every condition we cannot evaluate confidently falls through
# to exit 0 rather than guessing. `set -e` is deliberately absent: a stray
# non-zero would exit 1, which Claude Code surfaces as a hook error instead of
# quietly letting the call through.
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
# environment, not the one a Bash tool call builds. A human exports it before
# starting Claude Code. It is the same switch as guard-default-branch, because
# it lifts the same decision: "this session may work on main itself".
if [ "${MAKURA_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

# NotebookEdit names its target notebook_path; Edit and Write use file_path.
path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
[ -n "$path" ] || exit 0

workspace_path_is_exempt "$path" && exit 0

# Take the directory from the payload: ${CLAUDE_PROJECT_DIR} stays pinned to
# where the session started and does not follow Claude into a worktree.
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"

is_coordinator_workspace "$cwd" || exit 0

where="${WORKSPACE_BRANCH:+the default branch '$WORKSPACE_BRANCH' of $cwd}"
where="${where:-$cwd, which is not inside a repository}"

cat >&2 <<EOF
Blocked: this session is the coordinator ($where), which hands work out
rather than doing it. Files get edited by a worker in a worktree of its own.

Follow the \`core-dispatch\` skill: decide the repository, then

  orca orchestration run-current --json     # no Run yet: run-create --objective "<topic>: <goal>"
  orca orchestration worker-start --run <run_id> --task-title "<title>" \\
    --spec "<task, done-when, report to ~/.claude/worker-reports/<name>.md>" \\
    --worktree new-top-level --name <kebab-name> --repo id:<repoId> --agent claude

and read the worker's report back when it finishes. Planning, reading and
running commands are all still fine here -- only writing files is not.

The human at the terminal can export MAKURA_ALLOW_MAIN=1 before starting
Claude Code to lift this. You cannot set it yourself -- prefixing a command
with it does not reach this hook.

File: $path
EOF
exit 2
