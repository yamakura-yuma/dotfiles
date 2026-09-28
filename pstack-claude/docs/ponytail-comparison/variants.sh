#!/usr/bin/env bash
# variants.sh <work-dir>
# Builds the B and C variants of pstack-claude under <work-dir>/pkgs/.
# B: + ponytail-review, and one overlay row that runs it on architect's sketch.
# C: + every ponytail skill core-principal takes, installed the same way.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/../.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"
work="$1"
for c in B C; do
  rm -rf "$work/pkgs/$c"; mkdir -p "$work/pkgs/$c"
  (cd "$pkg" && git ls-files -- . ':(exclude)docs' | tar -cf - -T -) | tar -xf - -C "$work/pkgs/$c"
done
python3 - "$repo/core-principal/apm.yml" "$work/pkgs" <<'PY'
import sys, yaml
pony = [d for d in yaml.safe_load(open(sys.argv[1]))["dependencies"]["apm"]
        if d["alias"].startswith("ponytail")]
for c, keep in (("B", {"ponytail-review"}), ("C", {d["alias"] for d in pony})):
    p = f"{sys.argv[2]}/{c}/apm.yml"
    y = yaml.safe_load(open(p))
    y["name"] = f"pstack-claude-{c}"
    y["dependencies"]["apm"] += [d for d in pony if d["alias"] in keep]
    yaml.safe_dump(y, open(p, "w"), sort_keys=False, allow_unicode=True)
PY
f="$work/pkgs/B/.apm/skills/pstack-on-claude-code/SKILL.md"
row='| **architect** Phase C (the synthesized sketch, before Phase D) | Run `ponytail-review` over the sketch as an adversarial reviewer, reading the sketch as the diff. Act on each `delete:` / `yagni:` finding before implementing, or state in one line why the requirement keeps it |'
python3 - "$f" "$row" <<'PY'
import sys
p, row = sys.argv[1:]
s = open(p).read()
anchor = next(l for l in s.splitlines() if l.startswith("| Cursor cloud agent |"))
open(p, "w").write(s.replace(anchor, anchor + "\n" + row, 1))
PY
