#!/usr/bin/env bash
# Invariants of the harness itself: the things that are supposed to stay true
# between the .apm/ sources, the generated output, and the outside world the
# rules describe.
#
# The motivating failure is drift that nothing notices. A rule that quotes
# `orca worktree create --prompt` without --name is wrong in a way no test
# caught until an agent ran it; AGENTS.md regenerates from the instructions, so
# editing one without recompiling leaves a stale copy that still gets loaded.
# None of that is about behaviour, so none of it needs a model to check.
#
# Like guards.sh this lives outside .apm/, so apm never deploys it to a
# consuming repo. Run it directly, or via dotfiles' .agent/verify.sh.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$(cd "$here/.." && pwd)"           # makura-agents/
repo="$(cd "$pkg/.." && pwd)"           # the repo that maintains it

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
skip() {
  printf 'skip: %s\n' "$1"
}

# --- 1. AGENTS.md is what the instructions currently compile to --------------
# Compiles into a throwaway copy rather than in place: this script is reached
# through .agent/verify.sh, which the verifier subagent runs, and verification
# must not modify the repo it is verifying.
check_agents_md() {
  command -v apm >/dev/null 2>&1 || { skip "no apm, not checking AGENTS.md"; return; }
  [ -f "$repo/AGENTS.md" ] || { skip "no AGENTS.md to check"; return; }

  local tmp
  tmp="$(mktemp -d)" || { fail "mktemp"; return; }
  tar -C "$repo" -cf - --exclude=.git --exclude=graphify-out . 2>/dev/null |
    tar -C "$tmp" -xf - 2>/dev/null
  if (cd "$tmp" && apm compile --target agents) >/dev/null 2>&1; then
    diff -u "$repo/AGENTS.md" "$tmp/AGENTS.md" ||
      fail "AGENTS.md is stale -- run: apm compile --target agents"
  else
    fail "apm compile --target agents did not succeed on a clean copy"
  fi
  rm -rf "$tmp"
}

# --- 2. Paths the harness quotes about itself exist --------------------------
# Only paths the harness owns and ships. Two kinds are deliberately out of
# scope:
#
#   - Conditional paths belonging to another tool. code-navigation points at
#     graphify-out/wiki/index.md guarded by "if it exists", and treating that
#     as a promise would make this check cry wolf.
#   - Anything under .agent/. That directory is the per-repo convention area
#     where makura-agents shares the *name* and each repo supplies the file --
#     and .agent/report.md is written by a worker at runtime, so its normal
#     state is absent.
check_owned_paths() {
  local doc p target seen
  while IFS= read -r doc; do
    seen=""
    while IFS= read -r p; do
      case "$p" in
        *'<'* | *'>'* | *'*'*) continue ;;          # placeholders and globs
        .agent/*) continue ;;                       # names, not shipped files
        # These docs live inside the package, so an unprefixed path is relative
        # to it; only a path that names the package is relative to the repo.
        .apm/* | tests/*) target="$pkg/$p" ;;
        .claude/*) [ -d "$repo/.claude" ] || continue; target="$repo/$p" ;;
        *) target="$repo/$p" ;;
      esac
      case " $seen " in *" $p "*) continue ;; esac
      seen="$seen $p"
      [ -e "$target" ] || fail "$(basename "$doc") points at $p, which does not exist"
    done < <(grep -o '`[^`]*`' "$doc" |
      tr -d '`' |
      grep -E '^(makura-agents/|\.apm/|\.claude/|tests/)[^ ]*$')
  done < <(find "$pkg/.apm" -name '*.md' -type f; ls "$pkg/README.md" 2>/dev/null)
}

# --- 3. CLI flags the harness documents still exist --------------------------
# Only for the tools the harness tells an agent to run. A flag is checked by
# asking the tool itself, so this fails the day orca renames one -- which is
# the point, since a rule quoting a flag that no longer exists reads as
# authoritative right up until it doesn't work.
check_documented_flags() {
  local doc line bin subs flags tok help
  while IFS= read -r doc; do
    while IFS= read -r line; do
      read -r bin _ <<<"$line"
      command -v "$bin" >/dev/null 2>&1 || continue

      subs=(); flags=()
      for tok in $line; do
        case "$tok" in
          "$bin") ;;
          --*) flags+=("${tok%%=*}") ;;
          *)
            # Subcommands are the plain lowercase words before the first flag
            # or argument. Everything else -- flag values, paths, quoted
            # prompts -- is skipped, but scanning continues, because the flag
            # worth catching is often the last thing on the line.
            if [ ${#flags[@]} -eq 0 ] && [[ "$tok" =~ ^[a-z][a-z0-9-]*$ ]]; then
              subs+=("$tok")
            fi
            ;;
        esac
      done
      [ ${#flags[@]} -gt 0 ] || continue

      help="$(timeout 20 "$bin" "${subs[@]}" --help 2>&1)" || continue
      for tok in "${flags[@]}"; do
        grep -q -- "$tok" <<<"$help" ||
          fail "$(basename "$doc"): '$bin ${subs[*]}' has no $tok"
      done
    done < <(grep -hoE '^[[:space:]]*(orca|graphify|codegraph|apm)[^|`]*' "$doc" |
      sed 's/^[[:space:]]*//')
  done < <(find "$pkg/.apm" -name '*.md' -type f)
}

# --- 4. Every source deploys, and every deployed file has a source -----------
# Catches the leftover: delete an instruction and its generated rule stays
# behind in .claude/, still loaded, with nothing in .apm/ explaining it.
check_deploy_parity() {
  [ -d "$repo/.claude" ] || { skip "nothing deployed yet"; return; }
  local src name
  for src in "$pkg"/.apm/instructions/*.instructions.md; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .instructions.md)"
    [ -f "$repo/.claude/rules/$name.md" ] || fail "$name is not deployed to .claude/rules/"
  done
  for src in "$pkg"/.apm/prompts/*.prompt.md; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .prompt.md)"
    [ -f "$repo/.claude/commands/$name.md" ] || fail "$name is not deployed to .claude/commands/"
  done
  for src in "$pkg"/.apm/agents/*.agent.md; do
    [ -e "$src" ] || continue
    name="$(basename "$src" .agent.md)"
    [ -f "$repo/.claude/agents/$name.md" ] || fail "$name is not deployed to .claude/agents/"
  done
  for src in "$pkg"/.apm/skills/*/SKILL.md; do
    [ -e "$src" ] || continue
    name="$(basename "$(dirname "$src")")"
    [ -f "$repo/.claude/skills/$name/SKILL.md" ] || fail "$name is not deployed to .claude/skills/"
  done

  # And the other direction, for the primitives this package owns.
  local out
  for out in "$repo"/.claude/rules/*.md; do
    [ -e "$out" ] || continue
    name="$(basename "$out" .md)"
    [ -f "$pkg/.apm/instructions/$name.instructions.md" ] ||
      [ -f "$repo/.apm/instructions/$name.instructions.md" ] ||
      fail ".claude/rules/$name.md has no source in any .apm/"
  done
}

# --- 5. No repo keeps its own fork of a skill it also receives ---------------
# A sibling repo having its own session-retro is fine while it is independent.
# It stops being fine the moment that repo also depends on makura-agents,
# because then two copies of the same skill name are in play and only one of
# them gets maintained.
check_skill_forks() {
  local workspace other name mine
  # Overridable so the check can be pointed at a fixture; otherwise the sibling
  # repos of whatever repo maintains this package.
  workspace="${MAKURA_WORKSPACE_ROOT:-$(cd "$repo/.." && pwd)}"
  for other in "$workspace"/*/; do
    other="${other%/}"
    [ "$other" = "$repo" ] && continue
    [ -f "$other/apm.yml" ] || continue
    grep -q 'makura-agents' "$other/apm.yml" 2>/dev/null || continue
    for mine in "$pkg"/.apm/skills/*/; do
      name="$(basename "${mine%/}")"
      [ -d "$other/.apm/skills/$name" ] &&
        fail "$(basename "$other") depends on makura-agents but keeps its own .apm/skills/$name"
    done
  done
}

check_agents_md
check_owned_paths
check_documented_flags
check_deploy_parity
check_skill_forks

if [ "$failures" != 0 ]; then
  printf '%s harness invariant(s) broken\n' "$failures" >&2
  exit 1
fi
echo "harness invariants ok"
