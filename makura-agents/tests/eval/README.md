# Behavioural evals

`harness-check.sh` asks whether the harness is internally consistent.
This asks the harder question: **does installing it change what an agent does?**

The only honest way to ask is to run the same prompt in two fixture repos —
one that depends on `makura-agents`, one that does not — and require the
behaviour to appear in the first and not the second. `run.sh` fails a case that
passes in *both* arms, because that is not evidence the rule works. It is
evidence the model would have done it anyway.

```bash
./makura-agents/tests/eval/run.sh            # every case
./makura-agents/tests/eval/run.sh language   # one case
```

Each arm is a real API call. A case costs roughly $0.3–0.7 and takes 15–90
seconds, so this is not wired into `.agent/verify.sh`. Run it when the rules
change.

## Writing a case

A case is a shell file in `cases/` defining `PROMPT`, an optional
`setup <dir>` that populates the fixture, and `holds <dir>` which returns 0
when the expected behaviour is present. `run.sh` provides `final_text`,
`bash_commands`, and `tool_sequence` to read the event stream with.

Two things decide whether a case is worth having:

- **The prompt must not give the answer away.** `language` asks its question in
  English on purpose. Asked in Japanese, a model answers in Japanese whether or
  not a rule told it to, and the case would pass in both arms.
- **The control must plausibly fail.** A rule is only worth testing where it
  overrides what the model would otherwise do.

## Cases that were tried and rejected

**`verify-convention`** — fixture with a `.agent/verify.sh`, prompt asking
whether the repo is in good shape, expecting the agent to run it. Rejected:
the control ran it too. Asked to check a repo, an agent explores, finds the
script, and runs it without being told the convention. The `testing` rule's
value is therefore not in making that script get found; it is in the reporting
discipline around the result, which needs a judge rather than a grep.

**`code-navigation`** — expecting `graphify`/`codegraph` to be reached for
before `Grep`. Not isolable here: `~/.claude/settings.json` has `graphify
hook-guard` on `PreToolUse` for `Bash|Grep` and `Read|Glob`, so as soon as the
fixture has an index, *both* arms are told to use graphify on every tool call.
Testing this needs an arm that can run without the host's hooks.
