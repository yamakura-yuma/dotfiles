#!/usr/bin/env bash
# PreToolUse(Bash) guardrail: refuse `git commit` / `git push` while HEAD of the
# repository the command targets sits on its default branch. Registered by
# ../guard-default-branch.json, which `apm install` merges into the consuming
# repo's .claude/settings.json.
#
# Contract: exit 2 blocks the tool call and hands stderr back to the agent as
# the reason. Exit 0 means "no opinion", NOT "approved" -- so every condition we
# cannot evaluate confidently falls through to exit 0 rather than guessing.
# `set -e` is deliberately absent: a stray non-zero would exit 1, which Claude
# Code surfaces as a hook error instead of quietly letting the command through.
set -uo pipefail

# Hooks inherit Claude Code's environment, which on some hosts has not picked up
# the Nix profile yet. jq and git both live there.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac

# Drain stdin before any early exit so the caller never writes into a closed pipe.
payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

# The escape hatch is an environment variable rather than a marker file so that
# an agent cannot grant it to itself: this hook inherits Claude Code's
# environment, not the one a Bash tool call builds, so writing
# `MAKURA_ALLOW_MAIN=1 git push` in a command has no effect here. A human
# exports it before starting Claude Code.
if [ "${MAKURA_ALLOW_MAIN:-}" = "1" ]; then
  exit 0
fi

# "Which branch is the default one" is also what decides whether a workspace is
# the coordinator, so the answer lives in one place and both guards read it from there.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
# shellcheck source=lib/coordinator-workspace.sh
. "$here/lib/coordinator-workspace.sh" || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Most commands mention neither word; spare them the parse below.
case "$cmd" in *git*) ;; *) exit 0 ;; esac
case "$cmd" in *commit* | *push*) ;; *) exit 0 ;; esac
command -v awk >/dev/null 2>&1 || exit 0

# Matching command text is best effort by design; the hooks documentation says
# as much. Rather than grep the raw string -- which fired on a heredoc body or
# a quoted `--spec "..."` that merely mentioned the words, and judged
# `cd other-repo && git push` by the session's cwd -- split the command the way
# a shell roughly would and print one line per `git commit` / `git push` it
# would run:
#
#   <directory>\t<subcommand>\t<argument>...
#
# Handled: quotes and backslashes, comments, heredoc bodies (skipped unread),
# `;` `&&` `||` `|` `&` and newlines between commands, redirections, `( ... )`
# subshells and `$( ... )` / backticks, whose `cd` does not leak out. The
# directory starts at the payload's cwd, follows `cd` / `pushd`, and takes
# git's own `-C`. `~`, `$HOME` and `${HOME}` expand; any other expansion makes
# the word unknown, printed as \001 -- a directory or refspec we cannot read
# gets no opinion, like everything else this hook cannot evaluate. Not seen at
# all: commands inside `bash -c "..."`, `eval`, or `xargs`, and a git that is
# not the command word (`echo git push`).
split_commands='
function reset(d) { dq[d] = 0; w[d] = ""; win[d] = 0; wq[d] = 0; wdyn[d] = 0; redir[d] = 0; nw[d] = 0; prev[d] = "" }
function open(t) { D++; kind[D] = t; reset(D); dir[D] = dir[D - 1] }
function word_end() {
  if (!win[D]) return
  if (redir[D]) redir[D] = 0
  else { nw[D]++; sw[D, nw[D]] = w[D]; sd[D, nw[D]] = wdyn[D] }
  w[D] = ""; win[D] = 0; wq[D] = 0; wdyn[D] = 0
}
function command_end(sep) { word_end(); if (nw[D]) judge(sep); nw[D] = 0; redir[D] = 0; prev[D] = sep }
function resolve(base, p) { if (p ~ /^\//) return p; if (base == U) return U; return base "/" p }
function clean(v) { gsub(/[\t\n]/, " ", v); return v }
function judge(sep,   k, v, nd, gd, out, j) {
  for (k = 1; k <= nw[D]; k++) {
    v = sw[D, k]
    if (v ~ /^[A-Za-z_][A-Za-z0-9_]*=/ || v ~ /^(env|sudo|command|exec|nohup|time|!|\{|\}|then|do|else|elif|if|while|until)$/) continue
    if (k > 1 && v ~ /^-/) continue
    break
  }
  if (k > nw[D]) return
  v = sw[D, k]
  if (v == "cd" || v == "pushd") {
    for (k++; k <= nw[D] && sw[D, k] ~ /^-[LPe@]*-?$/ && sw[D, k] != "-"; k++) ;
    if (k > nw[D]) nd = ENVIRON["HOME"]
    else if (sd[D, k] || sw[D, k] == "-") nd = U
    else nd = resolve(dir[D], sw[D, k])
    # A cd inside a pipeline or in the background runs in a subshell of its own.
    if (sep != "|" && sep != "&" && prev[D] != "|") dir[D] = nd
    return
  }
  if (v == "popd") { dir[D] = U; return }
  if (v != "git" && v !~ /\/git$/) return
  gd = dir[D]
  for (k++; k <= nw[D]; k++) {
    v = sw[D, k]
    if (v == "-C") { k++; if (k > nw[D]) return; gd = sd[D, k] ? U : resolve(gd, sw[D, k]); continue }
    if (v == "--git-dir" || v == "--work-tree") { k++; gd = U; continue }
    if (v ~ /^--(git-dir|work-tree)=/) { gd = U; continue }
    if (v == "-c" || v == "--namespace" || v == "--config-env") { k++; continue }
    if (v ~ /^-/) continue
    break
  }
  if (k > nw[D] || (sw[D, k] != "commit" && sw[D, k] != "push")) return
  out = (gd ~ /[\t\n]/ ? U : gd) "\t" sw[D, k]
  for (j = k + 1; j <= nw[D]; j++) out = out "\t" (sd[D, j] ? U : "") clean(sw[D, j])
  print out
}
function dollar(i,   nx, j) {
  nx = substr(s, i + 1, 1)
  win[D] = 1
  if (nx == "(") { wdyn[D] = 1; open("sub"); return i + 1 }
  if (substr(s, i + 1, 4) == "HOME" && substr(s, i + 5, 1) !~ /[A-Za-z0-9_]/) { w[D] = w[D] ENVIRON["HOME"]; return i + 4 }
  if (substr(s, i + 1, 6) == "{HOME}") { w[D] = w[D] ENVIRON["HOME"]; return i + 6 }
  if (nx == "{") { wdyn[D] = 1; j = index(substr(s, i + 2), "}"); return j ? i + 1 + j : n }
  if (nx ~ /[A-Za-z_]/) { wdyn[D] = 1; for (j = i + 1; substr(s, j + 1, 1) ~ /[A-Za-z0-9_]/; j++) ; return j }
  if (nx != "" && index("0123456789@*#?$!-", nx)) { wdyn[D] = 1; return i + 1 }
  if (nx == "\047" && !dq[D]) { j = index(substr(s, i + 2), "\047"); wq[D] = 1
    if (!j) { w[D] = w[D] substr(s, i + 2); return n }
    w[D] = w[D] substr(s, i + 2, j - 1); return i + 1 + j }
  w[D] = w[D] "$"; return i
}
function heredoc(i,   c, d) {
  for (; substr(s, i + 1, 1) ~ /[ \t]/; i++) ;
  d = ""
  for (; i < n; i++) {
    c = substr(s, i + 1, 1)
    if (c ~ /[ \t\n;&|<>()]/) break
    if (c == "\047" || c == "\"") { j = index(substr(s, i + 2), c); if (!j) { d = d substr(s, i + 2); i = n; break }; d = d substr(s, i + 2, j - 1); i += j }
    else if (c == "\\") { d = d substr(s, i + 2, 1); i++ }
    else d = d c
  }
  nh++; hd[nh] = d
  return i
}
function bodies(i,   p, h, e, line) {
  p = i + 1
  for (h = 1; h <= nh; h++)
    while (p <= n) {
      e = index(substr(s, p), "\n")
      line = e ? substr(s, p, e - 1) : substr(s, p)
      p = e ? p + e : n + 1
      if (ht[h]) sub(/^\t+/, "", line)
      if (line == hd[h]) break
    }
  nh = 0
  return p - 1
}
{ s = s (NR > 1 ? "\n" : "") $0 }
END {
  U = "\001"; n = length(s); D = 0; kind[0] = "top"; reset(0); nh = 0
  dir[0] = ENVIRON["GUARD_CWD"] == "" ? U : ENVIRON["GUARD_CWD"]
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (dq[D]) {
      if (c == "\"") dq[D] = 0
      else if (c == "\\") { if (nx == "\n") i++; else if (nx != "" && index("$`\"\\", nx)) { w[D] = w[D] nx; i++ } else w[D] = w[D] c }
      else if (c == "$") i = dollar(i)
      else if (c == "`") { wdyn[D] = 1; open("bq") }
      else w[D] = w[D] c
      continue
    }
    if (c == " " || c == "\t") word_end()
    else if (c == "\n") { command_end("\n"); if (nh) i = bodies(i) }
    else if (c == "#" && !win[D]) { j = index(substr(s, i), "\n"); i = j ? i + j - 2 : n }
    else if (c == "\047") { j = index(substr(s, i + 1), "\047"); win[D] = 1; wq[D] = 1
      if (!j) { w[D] = w[D] substr(s, i + 1); i = n } else { w[D] = w[D] substr(s, i + 1, j - 1); i += j } }
    else if (c == "\"") { dq[D] = 1; win[D] = 1; wq[D] = 1 }
    else if (c == "\\") { if (nx != "\n") { w[D] = w[D] nx; win[D] = 1 }; i++ }
    else if (c == "$") i = dollar(i)
    else if (c == "`") { if (kind[D] == "bq") { command_end("`"); D-- } else { wdyn[D] = 1; win[D] = 1; open("bq") } }
    else if (c == ";") { if (nx == ";" || nx == "&") i++; command_end(";") }
    else if (c == "&") {
      if (nx == "&") { command_end("&&"); i++ }
      else if (nx == ">") { word_end(); i++; if (substr(s, i + 1, 1) == ">") i++; redir[D] = 1 }
      else command_end("&")
    }
    else if (c == "|") { if (nx == "|") { command_end("||"); i++ } else { if (nx == "&") i++; command_end("|") } }
    else if (c == "(") { command_end("("); open("sub") }
    else if (c == ")") { command_end(")"); if (D > 0 && kind[D] == "sub") D-- }
    else if (c == "<" || c == ">") {
      # The digits in 2>&1 name a descriptor, not an argument.
      if (win[D] && !wq[D] && w[D] ~ /^[0-9]+$/) { w[D] = ""; win[D] = 0; wdyn[D] = 0 } else word_end()
      if (c == "<" && nx == "<" && substr(s, i + 2, 1) != "<") {
        i++; t = substr(s, i + 1, 1) == "-"; if (t) i++
        i = heredoc(i); ht[nh] = t
      } else {
        if (c == "<" && nx == "<") i += 2
        else if (nx == ">" || nx == "&" || nx == "|" || (c == "<" && nx == ">")) i++
        redir[D] = 1
      }
    }
    else if (c == "~" && !win[D] && (nx == "" || nx ~ /[\/ \t\n;&|<>()]/)) { w[D] = ENVIRON["HOME"]; win[D] = 1 }
    else { w[D] = w[D] c; win[D] = 1 }
  }
  for (; D > 0; D--) command_end("")
  command_end("")
}
'

# Take the starting directory from the payload: ${CLAUDE_PROJECT_DIR} stays
# pinned to where the session started and does not follow Claude into a worktree.
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
commands="$(printf '%s' "$cmd" | GUARD_CWD="$cwd" LC_ALL=C awk "$split_commands" 2>/dev/null)" || exit 0

# Whether `git push <argument>...`, run with HEAD on the default branch, can
# land on it. Naming the destination is the only way out: a push with no
# refspec follows push.default, `--all` and wildcards may cover it, and HEAD is
# the default branch here. Deleting a remote branch other than the default one
# (`--delete b`, `:b`) never lands on it. A refspec we cannot read has no
# opinion, the same as an unknown directory.
push_lands_on_default() {
  local a remote="" del=0 opts=1 dst
  local -a specs=()
  while [ $# -gt 0 ]; do
    a="$1"
    shift
    if [ "$opts" = 1 ]; then
      case "$a" in
        --) opts=0; continue ;;
        -d | --delete) del=1; continue ;;
        --all | --mirror | --branches) return 0 ;;
        -o | --push-option) shift; continue ;;
        -*) continue ;;
      esac
    fi
    if [ -z "$remote" ]; then remote="$a"; else specs+=("$a"); fi
  done
  [ "${#specs[@]}" -gt 0 ] || { [ "$del" = 1 ] && return 1; return 0; }
  for a in "${specs[@]}"; do
    case "$a" in $'\001'*) continue ;; esac
    a="${a#+}"
    if [ "$del" = 1 ]; then dst="$a"; else dst="${a#*:}"; fi
    [ -n "$dst" ] || dst="${a%%:*}"
    case "$dst" in HEAD | @) dst="$WORKSPACE_BRANCH" ;; esac
    dst="${dst#refs/heads/}"
    case "$dst" in *'*'* | "$WORKSPACE_DEFAULT_BRANCH") return 0 ;; esac
  done
  return 1
}

# Non-zero from workspace_on_default_branch covers "not on the default branch"
# and "cannot tell" alike -- no repository, a detached HEAD, an unreadable
# directory. Both let that command through.
blocked=""
while IFS=$'\t' read -r -a f; do
  dir="${f[0]:-}"
  [ -n "$dir" ] && [ "$dir" != $'\001' ] || continue
  workspace_on_default_branch "$dir" || continue
  [ "${f[1]:-}" = commit ] || push_lands_on_default "${f[@]:2}" || continue
  blocked="$dir"
  break
done <<<"$commands"
[ -n "$blocked" ] || exit 0

cat >&2 <<EOF
Blocked: '$WORKSPACE_BRANCH' is the default branch of $blocked, and this repo does
not take commits or pushes directly on it.

Hand the work to a worker in a worktree of its own -- see the \`orchestration\`
skill:
  orca orchestration run-current --json     # no Run yet: run-create --objective "<topic>: <goal>"
  orca orchestration worker-start --run <run_id> --task-title "<title>" \\
    --spec "<task, done-when, report to ~/.claude/worker-reports/<name>.md>" \\
    --worktree new-top-level --name <kebab-name> --repo id:<repoId> --agent claude
  git worktree add -b <branch> ../<dir>     # when not going through Orca

The human at the terminal can export MAKURA_ALLOW_MAIN=1 before starting
Claude Code to lift this. You cannot set it yourself -- prefixing the command
with it does not reach this hook.

Command: $cmd
EOF
exit 2
