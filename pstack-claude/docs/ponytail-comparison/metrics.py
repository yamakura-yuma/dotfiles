#!/usr/bin/env python3
"""metrics.py <work-dir>: one TSV row per run under <work-dir>/runs/."""
import json, pathlib, re, sys

E = pathlib.Path(__file__).parent
rows = []
for d in sorted((pathlib.Path(sys.argv[1]) / "runs").iterdir()):
    out = d / "out.jsonl"
    if not (d / "exit.txt").exists():
        continue
    cfg, task, rep = d.name.split("-")
    ex = dict(l.split("=") for l in (d / "exit.txt").read_text().split())
    res, skills, agents, tin, tout, pony = {}, [], 0, 0, 0, 0
    for line in out.read_text().splitlines():
        try: ev = json.loads(line)
        except ValueError: continue
        if ev.get("type") == "result": res = ev
        if ev.get("type") == "assistant":
            for c in ev["message"].get("content", []):
                if c.get("type") != "tool_use": continue
                if c["name"] == "Skill": skills.append(c["input"].get("skill", "?"))
                m = re.search(r"skills/([\w-]+)/SKILL\.md", json.dumps(c["input"]))
                if c["name"] in ("Read", "Bash") and m: skills.append(m.group(1))
                if c["name"] in ("Agent", "Task"): agents += 1
                if "ponytail" in json.dumps(c["input"]): pony += 1
    u = res.get("usage", {})
    patch = (d / "diff.patch").read_text()
    files = set(re.findall(r"^\+\+\+ b/(.+)$", patch, re.M)) | set(re.findall(r"^diff --git a/\S+ b/(\S+)", patch, re.M))
    def count(sign, test):
        n, cur = 0, ""
        for l in patch.splitlines():
            if l.startswith("+++ b/"): cur = l[6:]
            elif l.startswith(sign) and not l.startswith(sign * 3) and cur.startswith("test_") == test: n += 1
        return n
    add = sum(1 for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++"))
    rem = sum(1 for l in patch.splitlines() if l.startswith("-") and not l.startswith("---"))
    src = "".join(l[1:] + "\n" for l in patch.splitlines() if l.startswith("+") and not l.startswith("+++"))
    classes = len(re.findall(r"^\s*class \w+", src, re.M))
    defs = len(re.findall(r"^\s*def \w+", src, re.M))
    rows.append(dict(
        run=d.name, cfg=cfg, task=task,
        hidden="PASS" if ex.get("hidden_exit") == "0" else "FAIL",
        visible="PASS" if ex.get("visible_exit") == "0" else "FAIL",
        src_added=count("+", False), src_removed=count("-", False), test_added=count("+", True), files=len(files),
        new_classes=classes, new_defs=defs,
        wall_s=int(ex.get("wall", 0)), cost_usd=round(res.get("total_cost_usd", 0), 2),
        turns=res.get("num_turns", 0),
        out_tokens=sum(m.get("outputTokens", 0) for m in res.get("modelUsage", {}).values()),
        in_tokens=sum(m.get("inputTokens", 0) + m.get("cacheReadInputTokens", 0) + m.get("cacheCreationInputTokens", 0) for m in res.get("modelUsage", {}).values()),
        subagents=agents, ponytail_calls=pony, skills=",".join(dict.fromkeys(s for s in skills if s not in ("pstack-on-claude-code",))),
        claude_exit=ex.get("exit"),
    ))
if not rows: sys.exit("no runs")
keys = list(rows[0])
print("\t".join(keys))
for r in rows: print("\t".join(str(r[k]) for k in keys))
