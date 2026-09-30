# shellcheck shell=bash
# Interactive prompt setup. Sourced from ~/.bashrc via the marked block that
# ./setup.sh reload appends there; edit this file rather than ~/.bashrc.
#
# Sourced into a live shell, so: no shebang, no `set -e` (it would make the
# user's shell exit on the next failed command), safe to source twice.

# Guard anyway: ~/.bashrc already returns early for non-interactive shells,
# but prompt escape sequences would corrupt the output of the non-interactive
# shells Claude Code and Orca spawn if this ever moves to ~/.profile.
case $- in
  *i*) ;;
  *) return 0 ;;
esac

# Tell the OTLP backend which Orca worktree (= worker) a Claude Code session
# belongs to. Orca exports ORCA_WORKTREE_ID as "<uuid>::<path>" into every
# terminal it opens; Claude Code reads OTEL_RESOURCE_ATTRIBUTES from its own
# environment, so this cannot live in settings.json `env` (static, and it would
# override this). Values must be percent-encoded, no spaces: the worktree name
# is a kebab-case dir name, the id a uuid. Skipped if already set or outside Orca.
if [ -n "${ORCA_WORKTREE_ID:-}" ] && [ -z "${OTEL_RESOURCE_ATTRIBUTES:-}" ]; then
  OTEL_RESOURCE_ATTRIBUTES="orca.worktree.id=${ORCA_WORKTREE_ID%%::*},orca.worktree.name=$(basename "${ORCA_WORKTREE_ID#*::}")"
  export OTEL_RESOURCE_ATTRIBUTES
fi

# Nix profile holds starship. A login shell gets this from /etc/profile.d,
# but a plain `bash -i` does not always.
case ":$PATH:" in
  *":$HOME/.nix-profile/bin:"*) ;;
  *) PATH="$HOME/.nix-profile/bin:$PATH" ;;
esac
export PATH

# Degrade to the stock PS1 on a host where `./setup.sh nix-tools` has not run
# yet, rather than erroring on every shell start.
command -v starship >/dev/null 2>&1 || return 0

# Config comes from ~/.config/starship.toml, symlinked by ./setup.sh reload;
# that is starship's own default, so STARSHIP_CONFIG stays unset.
# Keep this last so it wins over anything else that touched PS1.
eval "$(starship init bash)"
