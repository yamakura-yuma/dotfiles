#!/usr/bin/env bash
# Invariants of pstack-claude. Lives outside .apm/, so apm never deploys it.
#
#   1. What is copied from core-principal is still the same text: the
#      coordinator decision, core-tools, the two git guards, and the pins of
#      the published skills both packages depend on.
#   2. Each guard refuses what it exists to refuse and lets ordinary work
#      through -- the only behaviour this package adds to upstream.
#   3. japanese-guard is still upstream's script, and blocks an English
#      final answer but not a Japanese one.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

# Byte-for-byte copies.
for f in .apm/hooks/scripts/lib/coordinator-workspace.sh \
  .apm/hooks/scripts/guard-destructive-git.sh .apm/hooks/guard-destructive-git.json \
  .apm/hooks/guard-default-branch.json .apm/skills/core-tools/SKILL.md \
  .apm/agents/completion-reviewer.agent.md; do
  cmp -s "$pkg/$f" "$repo/core-principal/$f" || fail "$f differs from core-principal's copy"
done
# Copied with one word changed: the skill its refusal points at.
f=.apm/hooks/scripts/guard-default-branch.sh
sed 's/core-dispatch/orchestration/' "$repo/core-principal/$f" | cmp -s - "$pkg/$f" ||
  fail "$f differs from core-principal's copy beyond core-dispatch -> orchestration"

# Every dependency both packages declare is pinned to the same place.
python3 - "$pkg/apm.yml" "$repo/core-principal/apm.yml" <<'PY' || fail "a shared dependency drifted from core-principal/apm.yml"
import sys, yaml
ours, theirs = ({d["alias"]: (d["git"], d.get("path"), d["ref"])
                 for d in yaml.safe_load(open(p))["dependencies"]["apm"]} for p in sys.argv[1:])
bad = [a for a in ours.keys() & theirs.keys() if ours[a] != theirs[a]]
for a in bad:
    print(f"  {a}: {ours[a]} != {theirs[a]}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# A dependency whose `targets` is narrower than the package's is silently left
# out of the other agents' directories.
python3 - "$pkg/apm.yml" <<'PY' || fail "a dependency's targets differ from the package's"
import sys, yaml
y = yaml.safe_load(open(sys.argv[1]))
bad = [d["alias"] for d in y["dependencies"]["apm"] if d.get("targets", y["targets"]) != y["targets"]]
for a in bad:
    print(f"  {a}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

scripts="$pkg/.apm/hooks/scripts"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q -b main origin-repo
git -C "$tmp/origin-repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$tmp/origin-repo" worktree add -q -b feature "$tmp/child"

edit() {
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/x"}}' "$1" "$1" |
    env -u MAKURA_ALLOW_MAIN "$scripts/guard-coordinator-edit.sh" 2>/dev/null
}
bash_in() {
  jq -nc --arg cwd "$2" --arg cmd "$3" '{cwd:$cwd,tool_input:{command:$cmd}}' |
    env -u MAKURA_ALLOW_MAIN "$scripts/$1.sh" 2>/dev/null
}
expect() {
  local want="$1" what="$2"; shift 2
  "$@"; [ $? -eq "$want" ] || fail "$what"
}

expect 2 "coordinator-edit did not block an edit on main of an original checkout" edit "$tmp/origin-repo"
expect 0 "coordinator-edit blocked an edit in a child worktree" edit "$tmp/child"
expect 2 "default-branch did not block a commit on main" bash_in guard-default-branch "$tmp/origin-repo" "git commit -m x"
expect 0 "default-branch blocked a commit on a feature branch" bash_in guard-default-branch "$tmp/child" "git commit -m x"
expect 0 "default-branch judged cd <child> by the session's cwd" bash_in guard-default-branch "$tmp/origin-repo" "cd $tmp/child && git push"
expect 0 "default-branch blocked deleting a remote branch" bash_in guard-default-branch "$tmp/origin-repo" "git push origin --delete feature"
expect 0 "default-branch fired on words inside a quoted argument" bash_in guard-default-branch "$tmp/origin-repo" 'orca x --spec "git push origin main"'
expect 2 "destructive-git did not block reset --hard" bash_in guard-destructive-git "$tmp/child" "git reset --hard"
expect 0 "destructive-git blocked reset --soft" bash_in guard-destructive-git "$tmp/child" "git reset --soft HEAD~1"

# dispatch-by-topic: UserPromptSubmit is read for its stdout (exit 2 would cancel
# the prompt), so check what it printed. The coordinator gets the rule; a child
# worktree and a payload with no cwd get nothing.
topic() {
  jq -nc --arg cwd "$1" '{hook_event_name:"UserPromptSubmit", prompt:"x", cwd:$cwd}' |
    env -u MAKURA_ALLOW_MAIN "$scripts/dispatch-by-topic.sh" 2>/dev/null
}
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("open-topic-chat")' >/dev/null ||
  fail "dispatch-by-topic printed no topic-chat routing rule in the coordinator workspace"
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("chat-<topic>")' >/dev/null ||
  fail "dispatch-by-topic does not name the chat-<topic> worktree"
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("次にあなたがすること")' >/dev/null ||
  fail "dispatch-by-topic does not point at the reply shape (checklist and next steps)"
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("routing-facts") and contains("red") and contains("--agent-cmd")' >/dev/null ||
  fail "dispatch-by-topic does not tell the main chat to run routing-facts and change --agent-cmd at red"
for w in 'routing-facts' 'ROUTING_FACTS_MAX_AGE' '--effort medium' 'launch.effective'; do
  grep -qF -- "$w" "$pkg/.apm/skills/pstack-on-claude-code/SKILL.md" || fail "pstack-on-claude-code/SKILL.md does not mention $w"
done
for h in 'Reply shape' 'Hand over a Run' 'Main chat' 'Topic chat'; do
  grep -q "$h" "$pkg/.apm/skills/pstack-on-claude-code/SKILL.md" ||
    fail "pstack-on-claude-code lost \"$h\", which the dispatch-by-topic text points at"
done
[ -z "$(topic "$tmp/child")" ] || fail "dispatch-by-topic printed in a child worktree"
[ -z "$(printf '{}' | "$scripts/dispatch-by-topic.sh" 2>/dev/null)" ] || fail "dispatch-by-topic printed for a payload with no cwd"
jq -e '.hooks.UserPromptSubmit[0].hooks[0].command | endswith("/scripts/dispatch-by-topic.sh")' \
  "$pkg/.apm/hooks/dispatch-by-topic.json" >/dev/null || fail "dispatch-by-topic.json does not run the script on UserPromptSubmit"

# open-topic-chat, against stub orca and apm: nothing real is created. The orca
# stub answers with the JSON shapes `orca ... --json` returns, logs each call,
# and runs the command it is given (`terminal create --command`, or the text of
# `terminal send`) with `claude` replaced by a function that records its
# arguments, so the quoting is exercised as well. STUB_TERMINALS sets how many
# terminals the new worktree opened with and STUB_PROMPT what its last line is.
otc="$pkg/.apm/skills/pstack-on-claude-code/scripts/open-topic-chat"
[ -x "$otc" ] || fail "open-topic-chat is not executable"
mkdir -p "$tmp/stub" "$tmp/chat-demo"
cat > "$tmp/stub/orca" <<'STUB'
#!/usr/bin/env bash
echo "orca $*" >> "$STUB_LOG"
run_cmd() { claude() { printf '%s\n' "$@" > "$STUB_LOG.claude"; }; eval "$1"; }
args=("$@")
arg() { local i; for i in "${!args[@]}"; do [ "${args[$i]}" = "$1" ] && { printf '%s' "${args[$((i + 1))]}"; return; }; done; }
case "$1 $2" in
  "worktree list") printf '{"ok":true,"result":{"worktrees":[{"repoId":"R1","path":"%s"}]}}' "$STUB_REPO" ;;
  "worktree create") printf '{"ok":true,"result":{"worktree":{"id":"R1::%s"}}}' "$STUB_CHAT" ;;
  "terminal list")
    n="${STUB_TERMINALS:-1}"
    printf '{"ok":true,"result":{"terminals":[%s]}}' "$(for ((i = 1; i <= n; i++)); do printf '{"handle":"term_shell%s"},' "$i"; done | sed 's/,$//')" ;;
  "terminal read") printf '{"ok":true,"result":{"terminal":{"latestCursor":"2","tail":["","%s"]}}}' "${STUB_PROMPT:-❯}" ;;
  "terminal send") run_cmd "$(arg --text)"; printf '{"ok":true,"result":{"send":{"handle":"%s"}}}' "$(arg --terminal)" ;;
  "terminal rename") printf '{"ok":true,"result":{}}' ;;
  "terminal create") run_cmd "$(arg --command)"; printf '{"ok":true,"result":{"handle":"term_stub"}}' ;;
  *) printf '{"ok":false,"error":"unexpected"}' ;;
esac
STUB
cat > "$tmp/stub/apm" <<'STUB'
#!/usr/bin/env bash
echo "apm $* in $PWD" >> "$STUB_LOG"
STUB
chmod +x "$tmp/stub/orca" "$tmp/stub/apm"
otc_run() {
  : > "$tmp/stub.log"; rm -f "$tmp/stub.log.claude"
  (cd "$tmp/origin-repo" && PATH="$tmp/stub:$PATH" STUB_LOG="$tmp/stub.log" STUB_REPO="$tmp/origin-repo" \
    STUB_CHAT="$tmp/chat-demo" OPEN_TOPIC_CHAT_SHELL_WAIT=2 "$otc" "$@" 2>&1)
}
out="$(otc_run --said 'the request, "quoted"' --guess 'guessed target' demo)"
grep -q "^orca worktree create --repo id:R1 --name chat-demo --setup skip --no-parent --json$" "$tmp/stub.log" ||
  fail "open-topic-chat did not create chat-<topic> from the repo id read from worktree list, with --setup skip --no-parent"
grep -q "^apm install in $tmp/chat-demo$" "$tmp/stub.log" || fail "open-topic-chat did not run apm install in the new worktree"
grep -q "^orca terminal send --terminal term_shell1 --text claude --model claude-opus-5-5 --permission-mode plan " "$tmp/stub.log" ||
  fail "open-topic-chat did not type the topic chat's command, on claude-opus-5-5, into the worktree's startup shell"
grep -q "^orca terminal create" "$tmp/stub.log" && fail "open-topic-chat opened a second terminal although the startup shell was waiting"
[ "$(sed -n 1,2p "$tmp/stub.log.claude" 2>/dev/null)" = "$(printf -- '--model\nclaude-opus-5-5')" ] || fail "open-topic-chat passed claude something other than --model claude-opus-5-5 first"
[ "$(sed -n 3,4p "$tmp/stub.log.claude" 2>/dev/null)" = "$(printf -- '--permission-mode\nplan')" ] || fail "open-topic-chat did not start the topic chat in plan mode"
grep -q 'the request, "quoted"' "$tmp/stub.log.claude" || fail "open-topic-chat lost the hand-off text"
grep -q -A1 '^## ユーザーの原文$' "$tmp/stub.log.claude" && grep -A1 '^## ユーザーの原文$' "$tmp/stub.log.claude" | grep -q 'the request, "quoted"' ||
  fail "open-topic-chat did not put --said under 「ユーザーの原文」"
grep -A1 '^## わかっていること$' "$tmp/stub.log.claude" | grep -q '^（なし）$' || fail "open-topic-chat did not write （なし） for an omitted --known"
grep -A1 '^## 推測（要確認）$' "$tmp/stub.log.claude" | grep -q '^guessed target$' || fail "open-topic-chat did not put --guess under 「推測（要確認）」"
grep -q 'plan mode' "$tmp/stub.log.claude" && grep -q 'grounding.md' "$tmp/stub.log.claude" || fail "open-topic-chat's role does not point the chat at plan mode and grounding.md"
grep -q 'topic chat for `demo`' "$tmp/stub.log.claude" || fail "open-topic-chat did not state the topic chat's role"
grep -q 'run-use' "$tmp/stub.log.claude" && fail "open-topic-chat mentioned run-use without --run"
case "$out" in *"terminal: term_shell1"*) ;; *) fail "open-topic-chat did not print the startup shell's handle" ;; esac
otc_run --said x --known 'a fact' demo > /dev/null
grep -A1 '^## わかっていること$' "$tmp/stub.log.claude" | grep -q '^a fact$' || fail "open-topic-chat did not put --known under 「わかっていること」"
otc_run --run run_42 --said x demo > /dev/null
grep -q 'run-use --id run_42' "$tmp/stub.log.claude" || fail "open-topic-chat --run did not tell the chat to bind that Run"
otc_run --repo id:R9 --said x demo > /dev/null
grep -q -- "--repo id:R9 --name chat-demo" "$tmp/stub.log" || fail "open-topic-chat ignored --repo"
grep -q "worktree list" "$tmp/stub.log" && fail "open-topic-chat read worktree list although --repo was given"
# --agent-cmd replaces the command; the hand-off is still its last argument.
otc_run --agent-cmd 'claude --model claude-sonnet-5-5' --said x demo > /dev/null
grep -q "^orca terminal send --terminal term_shell1 --text claude --model claude-sonnet-5-5 " "$tmp/stub.log" || fail "open-topic-chat ignored --agent-cmd"
[ "$(sed -n 1,2p "$tmp/stub.log.claude")" = "$(printf -- '--model\nclaude-sonnet-5-5')" ] && [ "$(grep -c '^## ユーザーの原文$' "$tmp/stub.log.claude")" = 1 ] ||
  fail "open-topic-chat --agent-cmd did not append the hand-off as the last argument"
# Fall back to a terminal of our own when the startup shell cannot be used: more
# than one terminal (a configured default layout), or no prompt to type at.
for stub in "STUB_TERMINALS=2" "STUB_TERMINALS=0" "STUB_PROMPT=Running-a-build..."; do
  : > "$tmp/stub.log"; rm -f "$tmp/stub.log.claude"
  out="$(cd "$tmp/origin-repo" && env "$stub" PATH="$tmp/stub:$PATH" STUB_LOG="$tmp/stub.log" STUB_REPO="$tmp/origin-repo" \
    STUB_CHAT="$tmp/chat-demo" OPEN_TOPIC_CHAT_SHELL_WAIT=1 "$otc" --said x demo 2>&1)"
  grep -q "^orca terminal create --worktree path:$tmp/chat-demo --title demo --command claude --model claude-opus-5-5 " "$tmp/stub.log" ||
    fail "open-topic-chat did not fall back to terminal create ($stub)"
  grep -q "^orca terminal send" "$tmp/stub.log" && fail "open-topic-chat typed into a shell it could not verify ($stub)"
  [ -f "$tmp/stub.log.claude" ] || fail "open-topic-chat's fallback did not start the chat ($stub)"
  case "$out" in *"terminal: term_stub"*) ;; *) fail "open-topic-chat's fallback did not print the new terminal's handle ($stub)" ;; esac
done
otc_run --said x 'Bad Topic' > /dev/null && fail "open-topic-chat accepted a topic that is not kebab-case"
case "$(otc_run --said x 'Bad Topic')" in *kebab-case*) ;; *) fail "open-topic-chat refused a bad topic for a reason other than kebab-case" ;; esac
# The old two-positional form and a missing --said stop at usage: no worktree is created.
for bad in "demo x" "demo" "--known k demo" "--said x"; do
  # shellcheck disable=SC2086 # the words of $bad are the arguments
  case "$(otc_run $bad)" in usage:\ open-topic-chat*) ;; *) fail "open-topic-chat did not stop at usage for: $bad" ;; esac
  grep -q 'worktree create' "$tmp/stub.log" && fail "open-topic-chat created a worktree for: $bad"
done
[ -f "$pkg/.apm/skills/pstack-on-claude-code/grounding.md" ] || fail "pstack-on-claude-code/grounding.md is missing"
grep -q 'grounding.md' "$pkg/.apm/skills/pstack-on-claude-code/SKILL.md" || fail "pstack-on-claude-code's Topic chat no longer points at grounding.md"

# wait-worker-events, against a stub orca: no Run is touched. The stub logs
# each call's arguments, counts its calls in a file (every call is a new
# process), writes a keepalive line to stderr as the real check does, and
# answers as WEV_MODE says.
wev="$pkg/.apm/skills/pstack-on-claude-code/scripts/wait-worker-events"
[ -x "$wev" ] || fail "wait-worker-events is not executable"
bash -n "$wev" || fail "wait-worker-events does not parse"
mkdir -p "$tmp/wev-stub" "$tmp/wev-min"
cat > "$tmp/wev-stub/orca" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$WEV_LOG"
n=$(( $(cat "$WEV_LOG.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$WEV_LOG.n"
echo '{"_keepalive":true}' >&2
hb='{"type":"heartbeat","from":"w1","subject":"alive","payload":"{\"phase\":\"working\"}"}'
done_='{"type":"worker_done","from":"w1","subject":"finished","payload":"{}"}'
status_='{"type":"status","from":"w1","subject":"[triage] report","payload":"{}"}'
case "$WEV_MODE/$n" in
  hb_done/1) echo "{\"deliveryId\":\"d1\",\"messages\":[$hb],\"count\":1}" ;;
  hb_done/*) echo "{\"deliveryId\":\"d2\",\"messages\":[$hb,$done_],\"count\":2}" ;;
  hb_status/*) echo "{\"deliveryId\":\"d4\",\"messages\":[$hb,$status_],\"count\":2}" ;;
  wrapped/*) echo "{\"ok\":true,\"result\":{\"deliveryId\":\"d3\",\"messages\":[$done_],\"count\":1}}" ;;
  hb_late/1) sleep 0.3; echo "{\"deliveryId\":\"d1\",\"messages\":[$hb],\"count\":1}" ;;
  hb_late/*) echo '{"deliveryId":null,"messages":[],"count":0,"timedOut":true}' ;;
  no_id/*) echo "{\"deliveryId\":null,\"messages\":[$hb],\"count\":1}" ;;
  empty/*) sleep 0.01; echo '{"deliveryId":null,"messages":[],"count":0,"timedOut":true}' ;;
  refuse0/*) echo '{"ok":false,"error":{"code":"waiter_exists"}}' ;;
  refuse/*) echo '{"ok":false,"error":{"code":"waiter_exists"}}'; exit 1 ;;
  garbage/*) echo 'boom' ;;
esac
STUB
chmod +x "$tmp/wev-stub/orca"
# A PATH with only what the script needs, so orca is found (or not) by its fallback.
for b in jq date dirname mkdir sleep cat env bash; do ln -sf "$(command -v "$b")" "$tmp/wev-min/$b"; done
wev_run() {
  local mode="$1"; shift
  : > "$tmp/wev.log"; rm -f "$tmp/wev.log.n"
  PATH="$tmp/wev-stub:$PATH" WEV_MODE="$mode" WEV_LOG="$tmp/wev.log" XDG_STATE_HOME="$tmp/wev-state" "$wev" "$@" 2>"$tmp/wev.err"
}

out="$(wev_run hb_done --ack D0 --run run_1)"; rc=$?
[ "$rc" -eq 0 ] || fail "wait-worker-events did not exit 0 on a batch with a worker_done"
[ "$(wc -l < "$tmp/wev.log")" -eq 2 ] || fail "wait-worker-events did not wait again after a heartbeat-only batch"
sed -n 1p "$tmp/wev.log" | grep -q -- '--run run_1 --ack D0 ' || fail "wait-worker-events did not pass --run and the first --ack to its first check"
sed -n 2p "$tmp/wev.log" | grep -q -- '--ack d1 ' || fail "wait-worker-events did not ack the heartbeat batch on its next check"
sed -n 2p "$tmp/wev.log" | grep -q -- 'D0' && fail "wait-worker-events sent the first --ack twice"
[ "$(grep -c -- '--wait --types worker_done,escalation,question,status,heartbeat --timeout-ms 900000 --json$' "$tmp/wev.log")" -eq 2 ] ||
  fail "wait-worker-events did not wait on worker_done,escalation,question,status,heartbeat in 900000 ms slices"
[ "$(printf '%s\n' "$out" | jq -s length)" -eq 1 ] || fail "wait-worker-events printed more or less than one JSON"
printf '%s' "$out" | jq -e '.deliveryId == "d2" and (.messages | map(.type) == ["worker_done"]) and .count == 1' >/dev/null ||
  fail "wait-worker-events did not return the worker_done batch (heartbeat dropped, deliveryId kept)"
grep -q keepalive <<<"$out" && fail "wait-worker-events let the stderr keepalive into stdout"
[ -e "$tmp/wev-state" ] && fail "wait-worker-events wrote a heartbeat log"

# A status is news, not a heartbeat: it comes back (heartbeat dropped), not acked here.
out="$(wev_run hb_status)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(wc -l < "$tmp/wev.log")" -eq 1 ] &&
  printf '%s' "$out" | jq -e '.deliveryId == "d4" and (.messages | map(.type) == ["status"]) and .count == 1' >/dev/null ||
  fail "wait-worker-events did not return a status batch (heartbeat dropped, deliveryId kept)"

out="$(wev_run wrapped)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and .result.deliveryId == "d3"' >/dev/null ||
  fail "wait-worker-events did not return a batch wrapped in .result"
grep -q -- '--ack\|--run' "$tmp/wev.log" && fail "wait-worker-events passed --ack or --run that it was not given"

out="$(wev_run empty --deadline-ms 50)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.timedOut == true and .messages == []' >/dev/null ||
  fail "wait-worker-events did not return an empty batch at its deadline"
grep -q -- '--timeout-ms 1000 ' "$tmp/wev.log" && ! grep -q -- '--timeout-ms 900000' "$tmp/wev.log" ||
  fail "wait-worker-events did not shorten --timeout-ms to the time left (1000 ms at least)"

# A heartbeat batch that lands after the deadline is still acked.
out="$(wev_run hb_late --deadline-ms 100)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.timedOut == true' >/dev/null &&
  [ "$(wc -l < "$tmp/wev.log")" -eq 2 ] && sed -n 2p "$tmp/wev.log" | grep -q -- '--ack d1 ' ||
  fail "wait-worker-events left a heartbeat batch un-acked at its deadline"
out="$(wev_run no_id)"; rc=$?
[ "$rc" -eq 1 ] || fail "wait-worker-events did not stop on a heartbeat batch it cannot ack"

out="$(wev_run refuse)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | jq -e '.ok == false and .error.code == "waiter_exists"' >/dev/null ||
  fail "wait-worker-events hid or swallowed a refused wait (ok:false, waiter_exists)"
out="$(wev_run refuse0 --deadline-ms 3000)"; rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | jq -e '.ok == false and .error.code == "waiter_exists"' >/dev/null &&
  [ "$(wc -l < "$tmp/wev.log")" -eq 1 ] ||
  fail "wait-worker-events took ok:false with exit 0 for an empty batch and waited again"
out="$(wev_run garbage)"; rc=$?
[ "$rc" -eq 1 ] && [ "$out" = boom ] || fail "wait-worker-events did not pass non-JSON output through with exit 1"
wev_run hb_done --bogus >/dev/null; [ $? -eq 2 ] || fail "wait-worker-events accepted an unknown option"

# orca off PATH: found under ORCA_REMOTE_CLI_BIN_DIR, and an error when nowhere.
out="$(PATH="$tmp/wev-min" ORCA_REMOTE_CLI_BIN_DIR="$tmp/wev-stub" WEV_MODE=wrapped WEV_LOG="$tmp/wev.log" \
  XDG_STATE_HOME="$tmp/wev-state" "$(command -v bash)" "$wev" 2>/dev/null)"
printf '%s' "$out" | jq -e '.ok == true' >/dev/null || fail "wait-worker-events did not fall back to ORCA_REMOTE_CLI_BIN_DIR/orca"
PATH="$tmp/wev-min" ORCA_REMOTE_CLI_BIN_DIR="$tmp/none" "$(command -v bash)" "$wev" >/dev/null 2>&1
[ $? -eq 1 ] || fail "wait-worker-events did not fail when orca is nowhere"

# The spec every worker gets updates its card without a notification.
grep -q 'worktree set' "$pkg/.apm/skills/pstack-on-claude-code/SKILL.md" &&
  grep -q -- '--workspace-status in-review' "$pkg/.apm/skills/pstack-on-claude-code/SKILL.md" ||
  fail "pstack-on-claude-code lost the worker spec line that updates the card (worktree set --comment, in-review)"

# routing-facts, against a stub orca and a temp ~/.claude.json: no real usage is
# read. The stub answers as RF_MODE says and writes a handshake line to stderr as
# the real relay does, so stdout has to stay clean JSON.
rf="$pkg/.apm/skills/pstack-on-claude-code/scripts/routing-facts"
[ -x "$rf" ] || fail "routing-facts is not executable"
bash -n "$rf" || fail "routing-facts does not parse"
grep -q 'curl\|wget' "$rf" && fail "routing-facts calls the network (curl or wget)"
mkdir -p "$tmp/rf-stub" "$tmp/rf-min"
cat > "$tmp/rf-stub/orca" <<'STUB'
#!/usr/bin/env bash
echo "orca $*" >> "$RF_LOG"
echo '[relay-connect] Handshake OK' >&2
now_ms=$(( $(date +%s) * 1000 ))
case "$RF_MODE" in
  ok) printf '{"ok":true,"result":{"rateLimits":{"claude":{"status":"ok","error":null,"updatedAt":%s,"session":{"usedPercent":2,"resetsAt":1790990399846},"weekly":{"usedPercent":%s,"resetsAt":1791032399846},"fableWeekly":{"usedPercent":0}},"codex":{"status":"unavailable","error":"Codex not signed in"},"flag":true}}}' "$(( now_ms - 120000 ))" "${RF_WEEKLY:-65}" ;;
  stale) printf '{"ok":true,"result":{"rateLimits":{"claude":{"status":"ok","error":null,"updatedAt":%s,"session":{"usedPercent":2},"weekly":{"usedPercent":65}}}}}' "$(( now_ms - 7200000 ))" ;;
  billing) printf '{"ok":true,"result":{"rateLimits":{"claude":{"status":"unavailable","error":"No subscription plan — API key billing","session":null,"weekly":null}}}}' ;;
  garbage) echo boom ;;
  fail) exit 1 ;;
esac
STUB
chmod +x "$tmp/rf-stub/orca"
# A PATH with the tools the script needs and no orca.
for b in bash env jq date timeout; do ln -sf "$(command -v "$b")" "$tmp/rf-min/$b"; done
# A ~/.claude.json snapshot fetched $1 seconds ago, in the shape the status line reads.
rf_cfg() {
  local at=$(( ($(date +%s) - $1) * 1000 ))
  cat > "$tmp/rf-claude.json" <<EOF
{"cachedUsageUtilization":{"fetchedAtMs":$at,"utilization":{"limits":[
{"kind":"session","group":"session","percent":$2,"resets_at":"2026-09-30T20:39:59.949979+00:00"},
{"kind":"weekly_all","group":"weekly","percent":$3,"resets_at":"2026-10-03T12:59:59.950006+00:00"},
{"kind":"weekly_scoped","group":"weekly","percent":4,"resets_at":"2026-10-03T13:00:00+00:00","scope":{"model":{"display_name":"Fable"}}}]}}}
EOF
}
# rf_run <orca mode | none> [VAR=value ...]: stdout of routing-facts, stderr to a file.
rf_run() {
  local mode="$1"; shift
  local path="$tmp/rf-stub:$PATH"; [ "$mode" = none ] && path="$tmp/rf-min"
  : > "$tmp/rf.log"
  env -u ORCA_REMOTE_CLI_BIN_DIR PATH="$path" RF_MODE="$mode" RF_LOG="$tmp/rf.log" CLAUDE_CONFIG_FILE="$tmp/rf-claude.json" "$@" \
    "$(command -v bash)" "$rf" 2>"$tmp/rf.err"
}
rf_cfg 60 10 20
out="$(rf_run ok)"
printf '%s' "$out" | jq -e '.source == "orca" and .claude.session_pct == 2 and .claude.weekly_pct == 65 and .claude.fable_weekly_pct == 0
    and .claude.weekly_resets_at == 1791032399 and (.age_s | . >= 100 and . < 200) and .zone == "yellow"' >/dev/null ||
  fail "routing-facts did not read Orca's numbers (source orca, 2/65/0, age in seconds, zone yellow): $out"
printf '%s' "$out" | jq -e '(.agents | map(select(.id == "codex")) | .[0] | .signed_in == false and .error == "Codex not signed in")
    and (.agents | map(select(.id == "claude")) | .[0] | .signed_in == true and .error == null)' >/dev/null ||
  fail "routing-facts agents[] did not carry Orca's status and error"
[ "$(rf_run ok RF_WEEKLY=75 | jq -r .zone)" = orange ] && [ "$(rf_run ok RF_WEEKLY=90 | jq -r .zone)" = red ] &&
  [ "$(rf_run ok RF_WEEKLY=49 | jq -r .zone)" = green ] || fail "routing-facts zone is not cut at 50/75/90 on the larger of session and weekly"
# Orca not usable: stale, API-key billing, garbage, a failing call, or no orca at all
# -> ~/.claude.json.
for m in stale billing garbage fail none; do
  out="$(rf_run "$m")"
  printf '%s' "$out" | jq -e '.source == "claude-json" and .claude.session_pct == 10 and .claude.weekly_pct == 20 and .claude.fable_weekly_pct == 4
      and .claude.session_resets_at == 1790800799 and .zone == "green"' >/dev/null ||
    fail "routing-facts did not fall back to ~/.claude.json when Orca was: $m ($out)"
done
grep -q 'account list' "$tmp/rf.log" && fail "routing-facts called orca although orca was not on PATH"
# orca off PATH: found under ORCA_REMOTE_CLI_BIN_DIR.
out="$(env PATH="$tmp/rf-min" ORCA_REMOTE_CLI_BIN_DIR="$tmp/rf-stub" RF_MODE=ok RF_LOG="$tmp/rf.log" CLAUDE_CONFIG_FILE="$tmp/rf-claude.json" \
  "$(command -v bash)" "$rf" 2>/dev/null)"
printf '%s' "$out" | jq -e '.source == "orca"' >/dev/null || fail "routing-facts did not fall back to ORCA_REMOTE_CLI_BIN_DIR/orca"
# An old reading is not a number: percentages null, zone unknown, age still shown.
# ROUTING_FACTS_MAX_AGE moves the line.
rf_cfg 7200 10 20
out="$(rf_run none)"
printf '%s' "$out" | jq -e '.source == "claude-json" and .age_s >= 7200 and .claude.session_pct == null and .claude.weekly_pct == null
    and .claude.fable_weekly_pct == null and .zone == "unknown"' >/dev/null ||
  fail "routing-facts did not turn a 2-hour-old ~/.claude.json into unknown: $out"
rf_run stale | jq -e '.claude.weekly_pct == null and .zone == "unknown"' >/dev/null || fail "routing-facts took a stale Orca reading as a number"
rf_run none ROUTING_FACTS_MAX_AGE=86400 | jq -e '.zone == "green" and .claude.weekly_pct == 20' >/dev/null ||
  fail "routing-facts ignored ROUTING_FACTS_MAX_AGE"
# Neither source: none, unknown, still valid JSON.
rm -f "$tmp/rf-claude.json"
rf_run none | jq -e '.source == "none" and .age_s == null and .zone == "unknown" and (.agents | length) > 0' >/dev/null ||
  fail "routing-facts did not report source none and zone unknown with no usage anywhere"
[ -s "$tmp/rf.err" ] && fail "routing-facts wrote to stderr in a normal run: $(cat "$tmp/rf.err")"

# The text the chats read names the script, and the main chat is told to stay silent on heartbeats.
for f in .apm/skills/pstack-on-claude-code/SKILL.md .apm/skills/pstack-on-claude-code/scripts/open-topic-chat .apm/hooks/scripts/dispatch-by-topic.sh; do
  grep -q wait-worker-events "$pkg/$f" || fail "$f does not point at wait-worker-events"
done
topic "$tmp/origin-repo" | jq -e '.hookSpecificOutput.additionalContext | contains("heartbeat")' >/dev/null ||
  fail "dispatch-by-topic does not tell the main chat to stay silent on heartbeats"

# japanese-guard is vendored from minorun365/claude-code-japanese-guard at
# e68864a (docs/japanese-guard.md): script and test are upstream's bytes.
jg="$scripts/japanese-guard.py"
echo "42a77c34a47a88fcfa2106252c7007f479539eef786c6cab91c0330f0e915547  $jg" | sha256sum -c --quiet - ||
  fail "japanese-guard.py differs from upstream e68864a"
echo "caa1cea475429ee3169447792ab6d622766240c233fe54ee55c1996cb2c126d3  $here/japanese-guard/test_japanese_guard.py" |
  sha256sum -c --quiet - || fail "test_japanese_guard.py differs from upstream e68864a"
jq -e '.hooks.Stop[0].hooks[0].command | endswith("/scripts/japanese-guard.py")' \
  "$pkg/.apm/hooks/japanese-guard.json" >/dev/null || fail "japanese-guard.json does not run the script on Stop"
[ -x "$jg" ] || fail "japanese-guard.py is not executable"

stop() { printf '%s' "$1" | "$jg" 2>/dev/null; }
en='{"last_assistant_message":"I have updated the configuration and all the tests pass now."}'
[ "$(stop '{}')" = "" ] || fail "japanese-guard printed something for an empty input"
stop "$en" | jq -e '.decision == "block"' >/dev/null || fail "japanese-guard let an English final answer through"
[ "$(stop '{"last_assistant_message":"設定を更新し、テストがすべて通りました。"}')" = "" ] ||
  fail "japanese-guard blocked a Japanese final answer"
[ "$(stop "$(jq -c '.stop_hook_active = true' <<<"$en")")" = "" ] ||
  fail "japanese-guard blocked twice in one turn"

# Upstream's own tests, in upstream's layout: they find the hook at ../hooks/.
mkdir -p "$tmp/jg/hooks" "$tmp/jg/tests"
cp "$jg" "$tmp/jg/hooks/" && cp "$here/japanese-guard/test_japanese_guard.py" "$tmp/jg/tests/"
python3 "$tmp/jg/tests/test_japanese_guard.py" >/dev/null || fail "upstream test_japanese_guard.py failed"

[ "$failures" -eq 0 ] && echo "pstack-claude: ok"
exit "$failures"
