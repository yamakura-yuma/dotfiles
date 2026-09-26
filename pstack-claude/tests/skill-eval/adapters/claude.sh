#!/usr/bin/env bash
# Claude Code adapter for the agent-neutral cases under ../cases/. Runs them
# through `claude plugin eval`, which only loads plugins, so the apm-deployed
# .claude/ is wrapped into one first: skills and agents copied into a plugin
# directory, the rule passed as append_system_prompt. Hooks do not come
# across. Skill names gain the plugin's namespace (`pstack:`).
#
# A case's `opens` becomes one trace grader per skill: it passes when the
# skill was invoked with the Skill tool or its SKILL.md was read (quotes may
# arrive JSON-escaped in the trace), since
# poteto-mode reads principle skills with Read rather than invoking them.
#
# Real API calls on your own login, one run at a time. Not part of `make ci`.
#
#   ./pstack-claude/tests/skill-eval/adapters/claude.sh [claude plugin eval args]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
python3 - "$here/cases" "$p/evals" .claude/rules/pstack-claude.md <<'PY'
import pathlib, re, sys, yaml
cases, evals, rule = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), open(sys.argv[3]).read()
if rule.startswith("---"):
    rule = rule.split("---", 2)[2]
for f in sorted(cases.glob("*/case.yaml")):
    c = yaml.safe_load(f.read_text())
    out = evals / f.parent.name
    (out / "graders").mkdir(parents=True)
    prompt = c["prompt"].strip()
    if c.get("invoke"):
        prompt = f"/pstack:{c['invoke']} {prompt}"
    fm = {"runs": c.get("runs", 2), "model": "sonnet", "max_turns": c["max_turns"],
          "timeout_seconds": c["timeout_seconds"], "allowed_tools": ["Read", "Glob", "Grep", "Skill"],
          "append_system_prompt": rule.strip()}
    (out / "prompt.md").write_text("---\n" + yaml.safe_dump(fm, allow_unicode=True, sort_keys=False) + "---\n\n" + prompt + "\n")
    for s in c["opens"]:
        n = re.escape(s)
        g = {"type": "regex", "target": "trace",
             "pattern": rf'skill\\?"\s*:\s*\\?"(?:[\w-]+:)?{n}\\?"|/{n}/SKILL\.md'}
        (out / "graders" / f"opens-{s}.md").write_text("---\n" + yaml.safe_dump(g, sort_keys=False) + "---\n")
PY
cd "$p"
claude plugin eval . --trust-plugin --no-publish --ablation none --concurrency 1 \
  --threshold 0 --json "$work/result.json" "$@" | grep -v '^Note' || true
jq -r '.cases[] | .name as $n | .arms.with[] |
  "\($n)\tscore=\(.score)\t\([.graders[] | "\(.name)=\(.passed)"] | join(" "))"' "$work/result.json"
jq -r '"cost: $\(.costUsd)"' "$work/result.json"
