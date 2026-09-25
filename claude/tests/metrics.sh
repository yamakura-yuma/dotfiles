#!/usr/bin/env bash
# Tests claude/metrics.py against hand-built transcripts in fixtures/metrics/.
#
# Each fixture line stands for a record shape seen in real ~/.claude/projects
# logs: a hook block, a permission denial, a plain tool error, the records that
# look like prompts but are not turns (meta, compaction, interrupts, local
# command output, task notifications), a subagent transcript, a tool_use
# repeated across two assistant records, a transcript with no messages, and a
# line that is not JSON. The expected numbers below follow from those lines.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../metrics.py"
fixtures="$here/fixtures/metrics"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

snapshot() { find "$fixtures" -type f -exec sha256sum {} + | sort; }
before="$(snapshot)"

json="$("$script" --dir "$fixtures" --json)" || fail "--json exited non-zero"

# usage: check <description> <jq expression that must be true>
check() {
  jq -e "$2" >/dev/null <<<"$json" || fail "$1: $2"
}

check "sessions exclude subagents and empty transcripts" \
  '.projects == {"-proj-a": {"sessions": 1, "turns": 2}, "-proj-b": {"sessions": 1, "turns": 1}}'
check "tool calls count subagents, dedupe repeated tool_use ids" \
  '.tool_calls == {"Bash": 2, "Read": 1, "Edit": 1, "Write": 1}'
check "hook blocks keyed by script name, quoted or not" \
  '.hook_blocks == {"guard-default-branch.sh": 1, "guard-coordinator-edit.sh": 1}'
check "tool errors split by kind" \
  '.tool_errors.total == 4 and .tool_errors.by_kind == {"hook-blocked": 2, "denied:user-rejected": 1, "other": 1}'
check "tool errors attributed to the tool" \
  '.tool_errors.by_tool == {"Bash": 1, "Edit": 1, "Write": 1, "Read": 1}'
check "malformed lines skipped and counted" '.unparsed_lines == 1'

table="$("$script" --dir "$fixtures")" || fail "table exited non-zero"
for want in "== sessions and turns by project" "TOTAL" "== hook blocks" "tool errors (total 4)"; do
  case "$table" in
    *"$want"*) ;;
    *) fail "table lacks '$want'" ;;
  esac
done

"$script" --dir "$fixtures/does-not-exist" >/dev/null 2>&1 && fail "missing --dir should fail"

# The logs are read, never written.
[ "$(snapshot)" = "$before" ] || fail "metrics.py modified its input"

# Counting needs no model and no network; keep it that way.
if grep -vE '^\s*#' "$script" | grep -nE '\b(urllib|http\.client|socket|requests|subprocess|anthropic)\b'; then
  fail "metrics.py reaches for the network or a subprocess"
fi

if [ "$failures" != 0 ]; then
  printf '\n%s metrics test(s) failed\n' "$failures" >&2
  exit 1
fi
echo "metrics tests ok"
