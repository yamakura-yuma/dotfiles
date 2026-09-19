#!/usr/bin/env bash
# This repo's verification entry point, per the `testing` instruction that
# makura-agents ships: if .agent/verify.sh exists and is executable, that is how
# the repo is checked. The name is the only part that is shared between repos --
# the contents are always local, because build and test look different in every
# language.
#
# Deliberately does not run `apm install` or `./setup.sh reload`: verification
# should not change the machine it runs on, so that the verifier subagent (which
# has no Edit or Write) stays unable to alter anything.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

failures=0
step() {
  printf '\n== %s\n' "$1"
}
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Tracked files *and* new ones that are not committed yet, minus anything
# gitignored. Plain `git ls-files` would skip exactly the files a change just
# added -- which is the case this script exists to catch -- while a bare `find`
# would walk into the generated .claude/ and apm_modules/ trees.
ls_src() {
  git ls-files --cached --others --exclude-standard -- "$@"
}

step "shell syntax"
while IFS= read -r f; do
  bash -n "$f" 2>&1 || fail "bash -n $f"
done < <(ls_src '*.sh' 'setup.sh')

step "executable bits"
# A hook that is not executable fails open silently: Claude Code cannot run it,
# so the guardrail is simply absent. Worth catching here rather than in
# production.
while IFS= read -r f; do
  [ -x "$f" ] || fail "$f is not executable"
# Eval cases are excluded: run.sh sources them for PROMPT/setup/holds rather
# than executing them, so a +x bit there would claim something untrue.
done < <(ls_src 'makura-agents/.apm/hooks/scripts/*.sh' '.agent/*.sh' \
  'makura-agents/tests/*.sh' ':(exclude)makura-agents/tests/eval/cases/*')

step "json well-formed"
while IFS= read -r f; do
  jq empty "$f" 2>&1 || fail "invalid JSON: $f"
done < <(ls_src '*.json')

step "yaml well-formed"
# No yq on this host; python is available through the nix profile's uv runtime.
while IFS= read -r f; do
  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>&1 ||
    fail "invalid YAML: $f"
done < <(ls_src '*.yml' '*.yaml')

step "instruction frontmatter"
# apm needs applyTo to route an instruction and description to label it; a file
# missing either deploys as an empty rule, which is invisible until it matters.
while IFS= read -r f; do
  head -n 5 "$f" | grep -q '^applyTo:' || fail "$f has no applyTo"
  head -n 5 "$f" | grep -q '^description:' || fail "$f has no description"
done < <(ls_src 'makura-agents/.apm/instructions/*.instructions.md')

step "guard hooks"
./makura-agents/tests/guards.sh || fail "guard hook tests"

step "harness invariants"
# Drift between the .apm/ sources, the generated output, and the tools the
# rules quote. Deterministic and cheap, so it belongs here. The behavioural
# evals under makura-agents/tests/eval/ deliberately do not: they cost tokens
# and do not give the same answer twice.
./makura-agents/tests/harness-check.sh || fail "harness invariant checks"

printf '\n'
if [ "$failures" != 0 ]; then
  printf '%s check(s) failed\n' "$failures" >&2
  exit 1
fi
echo "all checks passed"
