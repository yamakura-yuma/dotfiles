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
