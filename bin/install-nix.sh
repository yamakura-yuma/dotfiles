#!/usr/bin/env bash
# One-time, per-host bootstrap: installs Nix itself via the Determinate
# Systems installer (multi-user/system install, flakes enabled by default,
# ships a clean `/nix/nix-installer uninstall`).
#
# Deliberately NOT a `just` recipe: `just` itself comes from Nix (see
# flake.nix), so nothing Nix-dependent can exist yet when this script runs.
#
# Needs sudo (multi-user install runs a system daemon). After it finishes,
# open a new shell (or `source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`)
# for `nix` to be on PATH.
set -euo pipefail

if command -v nix >/dev/null 2>&1; then
  echo "nix is already installed: $(command -v nix)" >&2
  exit 0
fi

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
  | sh -s -- install --no-confirm
