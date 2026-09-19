#!/usr/bin/env bash
# Installs/upgrades `apm` (https://github.com/microsoft/apm) from its GitHub
# release binaries, replacing the mise github-release plugin that used to do
# this. apm ships as a PyInstaller "onedir" bundle (a binary plus an adjacent
# _internal/ directory it depends on at runtime), so it's unpacked into a
# versioned directory under ~/.local/share/apm and exposed via a symlink in
# ~/.local/bin — symlinking just the binary works fine since it resolves its
# own real path to find _internal/.
set -euo pipefail

REPO="microsoft/apm"
INSTALL_ROOT="$HOME/.local/share/apm"
BIN_DIR="$HOME/.local/bin"

os=$(uname -s)
arch=$(uname -m)

case "$os" in
  Linux) os_name="linux" ;;
  Darwin) os_name="darwin" ;;
  *) echo "install-apm.sh: unsupported OS: $os" >&2; exit 1 ;;
esac

case "$arch" in
  x86_64|amd64) arch_name="x86_64" ;;
  arm64|aarch64) arch_name="arm64" ;;
  *) echo "install-apm.sh: unsupported arch: $arch" >&2; exit 1 ;;
esac

asset="apm-${os_name}-${arch_name}.tar.gz"
url="https://github.com/${REPO}/releases/latest/download/${asset}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "install-apm.sh: fetching ${asset}..." >&2
curl --proto '=https' --tlsv1.2 -fsSL -o "$tmpdir/$asset" "$url"
curl --proto '=https' --tlsv1.2 -fsSL -o "$tmpdir/$asset.sha256" "$url.sha256"

( cd "$tmpdir" && sha256sum -c "$asset.sha256" )

extract_dir="$tmpdir/extracted"
mkdir -p "$extract_dir"
tar -xzf "$tmpdir/$asset" -C "$extract_dir"

# The tarball contains a single top-level dir, e.g. apm-linux-x86_64/.
bundle_dir=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d)
version=$("$bundle_dir/apm" --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

dest="$INSTALL_ROOT/$version"
rm -rf "$dest"
mkdir -p "$INSTALL_ROOT"
mv "$bundle_dir" "$dest"

mkdir -p "$BIN_DIR"
ln -sfn "$dest/apm" "$BIN_DIR/apm"

echo "install-apm.sh: installed apm $version -> $BIN_DIR/apm" >&2
