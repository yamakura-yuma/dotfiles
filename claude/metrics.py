#!/usr/bin/env python3
"""Counts what the agent did, from the session logs Claude Code already keeps.

The first stage of evaluating the agent: plain numbers off local disk, with no
model and no API in the loop. Every figure here is a count of records in
~/.claude/projects/<project>/<session>.jsonl (and the subagent transcripts under
<session>/subagents/), so a number that looks wrong can be checked by grepping
the same files. The logs are only read -- never rewritten, never copied.

  make metrics                       table for a terminal
  ./claude/metrics.py --json         the same numbers for a machine
  ./claude/metrics.py --dir <path>   another projects directory (tests use this)

What each number means:

  sessions      main transcripts in a project with at least one message.
                Subagent transcripts are not sessions of their own.
  turns         prompts a human typed. Tool results, meta and compaction
                records, local command output, interrupt markers and
                notifications injected on the agent's behalf are not turns.
  tool calls    tool_use blocks, main sessions and subagents alike, by name.
  hook blocks   tool results of the form "<Event>:<Tool> hook error: [<cmd>]",
                which is how a hook exiting 2 reaches the transcript, by the
                hook script's file name.
  tool errors   tool results flagged is_error, split into hook blocks,
                permission denials (the log's toolDenialKind) and the rest.
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HOOK_BLOCK = re.compile(r"^(\w+):(\S+) hook error: \[(.*?)\]: ", re.S)
NOT_A_TURN = ("<local-command-", "[Request interrupted")


def text_of(content):
    if isinstance(content, str):
        return content
    return "".join(c.get("text", "") for c in content if isinstance(c, dict))


def result_text(block):
    content = block.get("content")
    return content if isinstance(content, str) else text_of(content or [])


def is_turn(rec):
    if rec.get("isMeta") or rec.get("isCompactSummary") or rec.get("isSidechain"):
        return False
    origin = rec.get("origin")
    if isinstance(origin, dict) and origin.get("kind") not in (None, "human"):
        return False
    content = rec["message"].get("content")
    if isinstance(content, list) and any(
        isinstance(c, dict) and c.get("type") == "tool_result" for c in content
    ):
        return False
    return not text_of(content).lstrip().startswith(NOT_A_TURN)


def collect(root):
    projects = defaultdict(lambda: {"sessions": 0, "turns": 0})
    tools = Counter()
    hooks = Counter()
    errors = Counter()
    errors_by_tool = Counter()
    unparsed = 0

    for path in sorted(root.glob("*/**/*.jsonl")):
        project = path.relative_to(root).parts[0]
        subagent = "subagents" in path.parts
        names = {}  # tool_use id -> tool name, for attributing errors
        has_message = False

        with path.open(encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except ValueError:
                    unparsed += 1
                    continue
                if not isinstance(rec, dict) or rec.get("type") not in ("user", "assistant"):
                    continue
                message = rec.get("message") or {}
                content = message.get("content")
                has_message = True

                if rec["type"] == "assistant":
                    for block in content if isinstance(content, list) else []:
                        if block.get("type") == "tool_use" and block.get("id") not in names:
                            names[block.get("id")] = block.get("name", "?")
                            tools[block.get("name", "?")] += 1
                    continue

                if not subagent and is_turn(rec):
                    projects[project]["turns"] += 1
                for block in content if isinstance(content, list) else []:
                    if block.get("type") != "tool_result" or not block.get("is_error"):
                        continue
                    errors_by_tool[names.get(block.get("tool_use_id"), "?")] += 1
                    hook = HOOK_BLOCK.match(result_text(block))
                    if hook:
                        hooks[os.path.basename(hook.group(3).strip('"'))] += 1
                        errors["hook-blocked"] += 1
                    elif rec.get("toolDenialKind"):
                        errors["denied:" + rec["toolDenialKind"]] += 1
                    else:
                        errors["other"] += 1

        if has_message and not subagent:
            projects[project]["sessions"] += 1

    return {
        "projects": dict(sorted(projects.items())),
        "tool_calls": dict(tools.most_common()),
        "hook_blocks": dict(hooks.most_common()),
        "tool_errors": {
            "total": sum(errors.values()),
            "by_kind": dict(errors.most_common()),
            "by_tool": dict(errors_by_tool.most_common()),
        },
        "unparsed_lines": unparsed,
    }


def table(title, rows, headers):
    rows = [[str(c) for c in r] for r in rows]
    widths = [max(len(h), *(len(r[i]) for r in rows)) if rows else len(h) for i, h in enumerate(headers)]
    fmt = "  ".join(("{:<%d}" if i == 0 else "{:>%d}") % w for i, w in enumerate(widths))
    lines = [f"== {title}", fmt.format(*headers)]
    lines += [fmt.format(*r) for r in rows] or ["(none)"]
    return "\n".join(lines)


def render(m):
    projects = m["projects"]
    sections = [
        table(
            "sessions and turns by project",
            [[p, v["sessions"], v["turns"]] for p, v in projects.items()]
            + [["TOTAL", sum(v["sessions"] for v in projects.values()),
                sum(v["turns"] for v in projects.values())]],
            ["project", "sessions", "turns"],
        ),
        table("tool calls", list(m["tool_calls"].items()), ["tool", "calls"]),
        table("hook blocks", list(m["hook_blocks"].items()), ["hook", "blocks"]),
        table(
            "tool errors (total %d)" % m["tool_errors"]["total"],
            list(m["tool_errors"]["by_kind"].items()),
            ["kind", "errors"],
        ),
        table("tool errors by tool", list(m["tool_errors"]["by_tool"].items()), ["tool", "errors"]),
    ]
    if m["unparsed_lines"]:
        sections.append("unparsed lines skipped: %d" % m["unparsed_lines"])
    return "\n\n".join(sections)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dir", type=Path, default=Path.home() / ".claude" / "projects")
    ap.add_argument("--json", action="store_true", help="print JSON instead of tables")
    args = ap.parse_args()
    if not args.dir.is_dir():
        sys.exit("no such directory: %s" % args.dir)
    m = collect(args.dir)
    print(json.dumps(m, indent=2, ensure_ascii=False) if args.json else render(m))


if __name__ == "__main__":
    main()
