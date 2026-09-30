#!/usr/bin/env bash
# Convert one Claude Code session jsonl into a single HTML file and open it in
# the Windows-side browser. Read-only on the jsonl; nothing leaves the machine.
#
# usage: session-to-html.sh [--no-open] [-o out.html] <session.jsonl>
set -euo pipefail

# Pinned: a newer release may change the HTML or drop the subagent expansion.
# Bump deliberately and re-run tests/check.sh.
CCL_VERSION=1.6.0

open=1
out=
while [ $# -gt 0 ]; do
  case "$1" in
    --no-open) open=0; shift ;;
    -o) out="${2:?-o needs a path}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
[ $# -eq 1 ] || { echo "usage: $0 [--no-open] [-o out.html] <session.jsonl>" >&2; exit 2; }
src="$1"
[ -f "$src" ] || { echo "no such file: $src" >&2; exit 1; }

if [ -z "$out" ]; then
  dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-session-html"
  mkdir -p "$dir"
  out="$dir/$(basename "$src" .jsonl).html"
fi

# claude-code-log reads subagents/agent-*.jsonl next to the session on its own.
# Never add an option that uploads the conversation.
uvx "claude-code-log@$CCL_VERSION" "$src" -o "$out"

echo "$out"
[ "$open" = 1 ] || exit 0

# Launch the Windows default browser itself. Going through the .html file
# association (explorer.exe, cmd /c start) lands on an "Open with" dialog on a
# host whose association is stale, and the https association is the one that
# tracks the browser the user actually picked. Its command line is `"exe" ... %1`.
ps="$(command -v powershell.exe || echo /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe)"
CCL_TARGET="$(wslpath -w "$out")" WSLENV=CCL_TARGET "$ps" -NoProfile -Command '
$p = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice").ProgId
$c = (Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$p\shell\open\command")."(default)"
Invoke-Expression ("& " + $c.Replace("%1", "`"$env:CCL_TARGET`""))'
