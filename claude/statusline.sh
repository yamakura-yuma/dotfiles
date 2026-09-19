#!/bin/bash
# Claude Code statusline, converted from the PS1 in ~/.bashrc:
#   PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
#
# Mapping: \u@\h -> user@host (bold green), \w -> current dir (bold blue),
# optional debian_chroot prefix preserved; trailing "\$ " prompt char dropped.
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir')
user=$(whoami)
host=$(hostname -s)

chroot=""
if [ -r /etc/debian_chroot ] && [ -s /etc/debian_chroot ]; then
  chroot="($(cat /etc/debian_chroot))"
fi

printf '%s\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m\n' "$chroot" "$user" "$host" "$cwd"
