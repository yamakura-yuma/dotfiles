#!/usr/bin/env bash
# Does a skill in pstack-claude actually get used? Runs the cases under
# cases/ through `claude plugin eval`, which only loads plugins, so the
# apm-deployed .claude/ is wrapped into one first: skills and agents copied
# into a plugin directory, the rule passed as append_system_prompt. Hooks do
# not come across. Skill names gain the plugin's namespace (`pstack:`).
#
# Real API calls on your own login, one run at a time. Not part of `make ci`.
#
#   ./pstack-claude/tests/skill-eval/run.sh [extra claude plugin eval args]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/consumer" "$work/plugin/.claude-plugin"
cd "$work/consumer"
git init -q .
printf 'name: skill-eval\nversion: 0.0.0\ntargets:\n- claude\ndependencies:\n  apm:\n  - path: %s\n' "$pkg" >apm.yml
apm install --target claude >/dev/null 2>&1 || { echo "apm install failed" >&2; exit 1; }

p="$work/plugin"
echo '{"name":"pstack","version":"0.0.0","description":"pstack-claude as apm deploys it"}' >"$p/.claude-plugin/plugin.json"
cp -rL .claude/skills "$p/skills"
cp -rL .claude/agents "$p/agents"
cp -r "$here/cases" "$p/evals"
python3 - "$p/evals" .claude/rules/pstack-claude.md <<'PY'
import pathlib, sys, yaml
evals, rule = pathlib.Path(sys.argv[1]), open(sys.argv[2]).read()
if rule.startswith("---"):
    rule = rule.split("---", 2)[2]
for f in evals.glob("*/prompt.md"):
    _, fm, body = f.read_text().split("---", 2)
    d = yaml.safe_load(fm)
    d["append_system_prompt"] = rule.strip()
    f.write_text("---\n" + yaml.safe_dump(d, allow_unicode=True, sort_keys=False) + "---" + body)
PY

cd "$p"
claude plugin eval . --trust-plugin --no-publish --ablation none --concurrency 1 \
  --threshold 0 --json "$work/result.json" "$@" | grep -v '^Note' || true
jq -r '.cases[] | .name as $n | .arms.with[] |
  "\($n)\tscore=\(.score)\t\([.graders[] | "\(.name)=\(.passed)"] | join(" "))"' "$work/result.json"
jq -r '"cost: $\(.costUsd)"' "$work/result.json"
