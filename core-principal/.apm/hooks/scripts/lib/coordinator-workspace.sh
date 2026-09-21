# shellcheck shell=bash
# One answer to "where am I?", shared by the guard hooks so they cannot drift
# apart. Sourced, never executed: it defines functions and runs nothing, which
# is why it carries no shebang and no executable bit (`make lint-exec` skips
# this directory for that reason).
#
# Contract for every function here: return 0 for yes, non-zero for both "no"
# and "cannot tell". Callers exit 0 -- "no opinion" -- on non-zero, so an
# unanswerable question must never look like a yes. Nothing here exits, calls
# `set -e`, or writes to stdout; the caller owns both.

# Is HEAD sitting on this repository's default branch?
#
# Sets WORKSPACE_BRANCH and WORKSPACE_DEFAULT_BRANCH as a side effect, so a
# caller can name them in the message it prints. Both are cleared first, so a
# stale value from an earlier call cannot leak into a later refusal.
workspace_on_default_branch() {
  local dir="$1" branch default
  WORKSPACE_BRANCH=""
  WORKSPACE_DEFAULT_BRANCH=""

  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1

  # Fails outside a repository and stays empty on a detached HEAD -- neither is
  # a case the guards have an opinion about.
  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)" || return 1
  [ -n "$branch" ] || return 1
  WORKSPACE_BRANCH="$branch"

  # refs/remotes/origin/HEAD is a local ref, so reading it costs no network
  # round trip. `git remote show origin` reports the same branch but contacts
  # the remote, which is far too slow to sit in front of every tool call.
  default="$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  default="${default#origin/}"

  if [ -n "$default" ]; then
    WORKSPACE_DEFAULT_BRANCH="$default"
    [ "$branch" = "$default" ] || return 1
    return 0
  fi

  # No origin/HEAD to consult (no remote, or a clone that never set it up).
  case "$branch" in
    main | master)
      WORKSPACE_DEFAULT_BRANCH="$branch"
      return 0
      ;;
  esac
  return 1
}

# Is this the original checkout rather than a `git worktree add` child?
#
# The distinction is on disk: the original has a .git *directory*, a linked
# worktree has a .git *file* pointing back into it. Asking git directly
# (`rev-parse --git-common-dir`) would also work, but the file-versus-directory
# test needs no version-dependent flag.
workspace_is_original_checkout() {
  local dir="$1" top
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  [ -d "$top/.git" ]
}

# Is this the coordinator workspace -- the place that dispatches work instead of
# doing it?
#
# Two shapes count, and they are the two places a session starts when nobody
# has handed it a branch of its own:
#
#   (a) the original checkout of a repository, sitting on its default branch;
#   (b) a directory in no repository at all, such as $HOME.
#
# A child worktree is never the coordinator, even on the default branch: that is where
# dispatched work is supposed to land.
is_coordinator_workspace() {
  local dir="$1"
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  command -v git >/dev/null 2>&1 || return 1

  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    return 0
  fi

  workspace_on_default_branch "$dir" && workspace_is_original_checkout "$dir"
}

# Paths an agent may write to even in the coordinator workspace: its own scratchpad
# and the plans a human reads before approving work. Neither is repository
# content, and blocking them would stop the dispatcher from doing its job.
workspace_path_is_exempt() {
  local path="$1"
  [ -n "$path" ] || return 1
  case "$path" in
    /tmp/claude-*) return 0 ;;
    "${HOME:-/nonexistent}"/.claude/plans/*) return 0 ;;
  esac
  return 1
}
