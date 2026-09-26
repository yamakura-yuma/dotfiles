# Verification lives in the development process, not in an agent-only ritual.
# `make ci` is what a human types, what CI runs, and what an agent is told to
# run -- one entry point with one name, instead of a convention only the agent
# knows about.
#
# Every target here is deterministic, offline and fast enough to run on each
# change. The behavioural evals under core-principal/tests/eval/ are not: they
# make real API calls, so they have their own `make eval` and are never part of
# `ci`.
#
# Targets fail fast. Use `make -k ci` to see every failure in one pass.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c

# Tracked files *and* new ones not committed yet, minus anything gitignored.
# Plain `git ls-files` would skip exactly the files a change just added -- the
# case these checks exist to catch -- while a bare `find` would walk into the
# generated .claude/ and apm_modules/ trees.
ls_src = git ls-files --cached --others --exclude-standard --

.PHONY: help ci lint lint-shell lint-exec lint-json lint-yaml lint-frontmatter \
        test test-guards test-harness test-statusline test-metrics \
        metrics eval install

help:
	@echo "make ci       lint + test (deterministic, offline; what CI runs)"
	@echo "make lint     shell syntax, executable bits, JSON, YAML, frontmatter"
	@echo "make test     guard hooks, harness invariants, statusline"
	@echo "make metrics  count sessions, turns, tool calls, hook blocks from local logs"
	@echo "make eval     behavioural evals -- real API calls, costs money"
	@echo "make install  deploy the agent config and dotfiles onto this machine"

ci: lint test
	@echo "all checks passed"

lint: lint-shell lint-exec lint-json lint-yaml lint-frontmatter lint-pins

test: test-guards test-harness test-pstack-claude test-statusline test-metrics

lint-shell:
	@echo "== shell syntax"
	@$(ls_src) '*.sh' 'setup.sh' | while IFS= read -r f; do bash -n "$$f"; done

# A hook that is not executable fails open silently: Claude Code cannot run it,
# so the guardrail is simply absent. Worth catching here rather than in
# production. Eval cases are excluded because run.sh sources them for
# PROMPT/setup/holds rather than executing them, so a +x bit there would claim
# something untrue. hooks/scripts/lib/ is excluded for the same reason -- git
# pathspec wildcards cross directory boundaries, so scripts/*.sh would
# otherwise demand +x on files that exist only to be sourced.
lint-exec:
	@echo "== executable bits"
	@$(ls_src) 'core-principal/.apm/hooks/scripts/*.sh' 'core-principal/tests/*.sh' \
	    'claude/tests/*.sh' 'pstack-claude/.apm/hooks/scripts/*.sh' 'pstack-claude/tests/*.sh' \
	    ':(exclude)core-principal/tests/eval/cases/*' \
	    ':(exclude)core-principal/.apm/hooks/scripts/lib/*' ':(exclude)pstack-claude/.apm/hooks/scripts/lib/*' | \
	  while IFS= read -r f; do \
	    [ -x "$$f" ] || { echo "not executable: $$f" >&2; exit 1; }; \
	  done

lint-json:
	@echo "== json well-formed"
	@$(ls_src) '*.json' | while IFS= read -r f; do jq empty "$$f"; done

# No yq on this host; python comes from the nix profile's uv runtime.
lint-yaml:
	@echo "== yaml well-formed"
	@$(ls_src) '*.yml' '*.yaml' | while IFS= read -r f; do \
	  python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]))' "$$f"; \
	done

# apm needs applyTo to route an instruction and description to label it; a file
# missing either deploys as an empty rule, which is invisible until it matters.
lint-frontmatter:
	@echo "== instruction frontmatter"
	@$(ls_src) '*/.apm/instructions/*.instructions.md' | \
	  while IFS= read -r f; do \
	    head -n 5 "$$f" | grep -q '^applyTo:' || { echo "$$f has no applyTo" >&2; exit 1; }; \
	    head -n 5 "$$f" | grep -q '^description:' || { echo "$$f has no description" >&2; exit 1; }; \
	  done

# Reads pins.tsv rather than the network: `refresh` and `latest` are the modes
# that talk to GitHub, and neither belongs in ci. Age is reported, not enforced.
lint-pins:
	@echo "== pins"
	@./bin/pins.sh check

test-guards:
	@echo "== guard hooks"
	@./core-principal/tests/guards.sh

# Drift between the .apm/ sources, the generated output, and the tools the
# rules quote.
test-harness:
	@echo "== harness invariants"
	@./core-principal/tests/harness-check.sh

test-pstack-claude:
	@echo "== pstack-claude"
	@./pstack-claude/tests/check.sh

test-statusline:
	@echo "== statusline"
	@./claude/tests/statusline.sh

test-metrics:
	@echo "== metrics"
	@./claude/tests/metrics.sh

# Reads ~/.claude/projects, so its output is this machine's history rather than
# a check -- not part of ci. `make metrics ARGS=--json` for the machine form.
metrics:
	@./claude/metrics.py $(ARGS)

eval:
	@./core-principal/tests/eval/run.sh

# Separate from ci on purpose: ci must not change the machine it runs on.
install:
	@./setup.sh
