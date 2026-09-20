#!/usr/bin/env bash
# Does a rule actually change what an agent does?
#
# harness-check.sh answers "is the harness internally consistent", which is a
# different and much cheaper question. This answers "does installing it make a
# difference", and the only honest way to ask that is to run the same prompt
# twice -- once in a fixture that depends on makura-agents and once in one that
# does not -- and require the behaviour to appear only in the first. A case
# that passes in both arms is not evidence the rule works; it is evidence the
# model would have done it anyway, and the case needs rewriting.
#
# Deliberately NOT part of `make ci`: each arm is a real API call,
# so a two-case run costs real money and does not give the same answer twice.
# Run it when the rules change, not on every commit.
#
#   ./makura-agents/tests/eval/run.sh              # all cases
#   ./makura-agents/tests/eval/run.sh language     # one case
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/../.." && pwd)"

command -v claude >/dev/null 2>&1 || { echo "eval needs the claude CLI" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "eval needs jq" >&2; exit 1; }
command -v apm >/dev/null 2>&1 || { echo "eval needs apm" >&2; exit 1; }

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

failures=0
total_cost=0

# Builds one throwaway repo. $2 = "makura" to install the package into it.
build_fixture() {
  local dir="$1" arm="$2"
  mkdir -p "$dir"
  git -C "$dir" init -q .
  if [ "$arm" = makura ]; then
    cat >"$dir/apm.yml" <<YAML
name: eval-fixture
version: 0.0.0
targets:
- claude
dependencies:
  apm:
  - path: $pkg
    alias: makura-agents
YAML
    (cd "$dir" && apm install --target claude) >/dev/null 2>&1 ||
      { echo "apm install failed in the $arm fixture" >&2; return 1; }
  fi
}

# Runs the prompt and leaves the event stream at $dir/out.jsonl.
run_arm() {
  local dir="$1" prompt="$2"
  (cd "$dir" && timeout 300 claude -p \
    --output-format stream-json --verbose \
    --permission-mode bypassPermissions \
    "$prompt") >"$dir/out.jsonl" 2>"$dir/err.txt"
}

cost_of() {
  jq -r 'select(.type=="result") | .total_cost_usd // 0' "$1/out.jsonl" 2>/dev/null | tail -1
}

# --- helpers the cases use against an event stream ---------------------------

# The assistant's final answer.
final_text() {
  jq -r 'select(.type=="result") | .result // ""' "$1/out.jsonl" 2>/dev/null
}

# Every Bash command the agent ran, one per line.
bash_commands() {
  jq -r 'select(.type=="assistant") | .message.content[]?
         | select(.type=="tool_use" and .name=="Bash") | .input.command // ""' \
    "$1/out.jsonl" 2>/dev/null
}

# Tool names in the order they were used.
tool_sequence() {
  jq -r 'select(.type=="assistant") | .message.content[]?
         | select(.type=="tool_use") | .name' "$1/out.jsonl" 2>/dev/null
}

for case_file in "$here"/cases/*.sh; do
  name="$(basename "$case_file" .sh)"
  [ $# -gt 0 ] && { [[ " $* " == *" $name "* ]] || continue; }

  PROMPT=""
  setup() { :; }
  holds() { return 1; }
  # shellcheck source=/dev/null
  . "$case_file"

  printf '\n== %s\n' "$name"
  ok=1
  for arm in makura control; do
    dir="$root/$name-$arm"
    build_fixture "$dir" "$arm" || { ok=0; break; }
    setup "$dir"
    run_arm "$dir" "$PROMPT" || { echo "  claude failed in the $arm arm" >&2; ok=0; break; }

    c="$(cost_of "$dir")"
    total_cost="$(awk -v a="$total_cost" -v b="${c:-0}" 'BEGIN{printf "%.4f", a+b}')"

    if holds "$dir"; then
      printf '  %-8s behaviour present\n' "$arm"
      [ "$arm" = control ] && {
        echo "  -> the control did it too, so this case proves nothing" >&2
        ok=0
      }
    else
      printf '  %-8s behaviour absent\n' "$arm"
      [ "$arm" = makura ] && {
        echo "  -> the rule did not take effect" >&2
        ok=0
      }
    fi
  done
  [ "$ok" = 1 ] || failures=$((failures + 1))
done

printf '\nspent $%s\n' "$total_cost"
if [ "$failures" != 0 ]; then
  printf '%s eval case(s) failed\n' "$failures" >&2
  exit 1
fi
echo "eval ok"
