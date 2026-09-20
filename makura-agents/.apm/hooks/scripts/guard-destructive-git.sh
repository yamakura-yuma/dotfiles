#!/usr/bin/env bash
# PreToolUse(Bash) guardrail: refuse the handful of git commands that throw away
# work which exists nowhere else -- uncommitted changes and already-pushed
# history. Registered by ../guard-destructive-git.json, which `apm install`
# merges into the consuming repo's .claude/settings.json.
#
# Contract is the same as guard-default-branch.sh: exit 2 blocks the tool call
# and hands stderr back to the agent as the reason, exit 0 means "no opinion"
# rather than "approved", and `set -e` is deliberately absent so a stray
# non-zero cannot turn into a hook error.
#
# The line this draws is *what cannot be recovered*, not "what sounds scary".
# `git reset --soft`, `git checkout <branch>` and `git push --force-with-lease`
# all pass, because each either keeps the work or refuses on its own when the
# remote moved. Blocking those would put a prompt in front of ordinary work,
# which is the fastest way to make a guardrail get switched off.
set -uo pipefail

# Hooks inherit Claude Code's environment, which on some hosts has not picked up
# the Nix profile yet. jq lives there.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

# Same reasoning as MAKURA_ALLOW_MAIN: an environment variable the human exports
# before starting Claude Code, not a marker file, so an agent cannot grant it to
# itself by prefixing the command -- this hook never sees the environment a Bash
# tool call builds.
if [ "${MAKURA_ALLOW_DESTRUCTIVE:-}" = "1" ]; then
  exit 0
fi

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Skip past git's own leading options so `git -C dir reset --hard` still
# registers -- note -C and -c take their value as a separate word -- and require
# the subcommand to start a word of its own, so `echo "git reset --hard"` is not
# caught. Matching command text is best effort by design; the hooks
# documentation says as much.
git_prefix='(^|[;&|(]|[[:space:]])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|-[^[:space:]]+))*[[:space:]]+'

# Flags may appear before or after the operand, so allow any run of non-separator
# words in between rather than pinning the flag to one position.
args='([^;&|]*[[:space:]])?'
end='([[:space:]]|$|[;&|])'

matches() {
  printf '%s' "$cmd" | grep -qE "$1"
}

refuse() {
  cat >&2 <<EOF
Blocked: $1

$2

The human at the terminal can export MAKURA_ALLOW_DESTRUCTIVE=1 before starting
Claude Code to lift this. You cannot set it yourself -- prefixing the command
with it does not reach this hook.

Command: $cmd
EOF
  exit 2
}

if matches "${git_prefix}reset[[:space:]]+${args}--hard${end}"; then
  refuse "\`git reset --hard\` discards every uncommitted change in the worktree." \
"Keep the work and move the branch instead:
  git stash push -u -m \"<why>\"     # then reset, and pop if it was needed
  git reset --soft <commit>         # move HEAD, leave the files alone"
fi

# -f is what makes `clean` delete; without it git only lists. Matching a run of
# short flags covers the usual -fd / -fdx spellings as well as bare -f.
if matches "${git_prefix}clean[[:space:]]+${args}(-[[:alnum:]]*f|--force)"; then
  refuse "\`git clean -f\` deletes untracked files outright -- they are in no commit, so nothing can bring them back." \
"See what would go first, and delete by name if it really should:
  git clean -nd                     # dry run, no -f
  rm <specific paths>"
fi

# A pathspec of . / * / :/ means "the whole tree". Reverting one named file is a
# normal, targeted operation and stays allowed.
if matches "${git_prefix}(checkout|restore)[[:space:]]+${args}(--[[:space:]]+)?(\.|\*|:/)${end}"; then
  refuse "Restoring the whole tree discards every uncommitted change in it." \
"Park the changes somewhere they can come back from, or name the one file:
  git stash push -u -m \"<why>\"
  git restore <specific path>"
fi

# --force-with-lease does not match: the character after --force is '-', not a
# separator. That is the point -- it is the spelling that refuses when the remote
# has moved, so it is the one to leave working.
if matches "${git_prefix}push[[:space:]]+${args}(--force|-f)${end}"; then
  refuse "\`git push --force\` overwrites remote history, including commits pushed by someone else." \
"Use the spelling that checks the remote first:
  git push --force-with-lease"
fi

exit 0
