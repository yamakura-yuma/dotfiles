#!/usr/bin/env bash
# WORK=<dir> run-one.sh <config A|B|C> <task> <rep>
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
E="${WORK:?set WORK to a scratch dir; run variants.sh "$WORK" first}"
cfg=$1 task=$2 rep=$3
case $cfg in A) pkg="$(cd "$here/../.." && pwd)" ;; *) pkg=$E/pkgs/$cfg ;; esac
d=$E/runs/$cfg-$task-$rep; rm -rf "$d"; mkdir -p "$d"
w=$d/repo; cc=$d/claude-config
mkdir -p "$w" "$cc"; cp ~/.claude/.credentials.json "$cc/"; chmod 600 "$cc/.credentials.json"
cp "$here/tasks/$task/"*.py "$w/"
cd "$w"
git init -q -b main .
printf '__pycache__/\napm_modules/\n' > .gitignore
cat > apm.yml <<YAML
name: exp-$cfg
version: 0.0.0
targets:
- claude
dependencies:
  apm:
  - path: $pkg
YAML
apm install --target claude >"$d/apm-install.log" 2>&1 || { echo "apm failed $d"; exit 1; }
git add -A && git -c user.name=exp -c user.email=exp@x commit -qm base
git checkout -qb feature
git rev-parse HEAD > "$d/base"
prompt="/poteto-mode 設計は architect スキルで行ってから実装すること。人間は不在なので質問せずに最後まで進め、feature ブランチにコミットしてよい。

$(cat "$here/tasks/$task/TASK.md")"
printf '%s' "$prompt" > "$d/prompt.txt"
start=$(date +%s)
# Each run gets its own /tmp: arena and friends write to fixed paths like
# /tmp/arena-<slug>, which concurrent runs of the same task would share.
mkdir -p "$d/tmp"
uid=$(id -u) gid=$(id -g)
export d prompt cc uid gid
unshare -r -m --propagation private bash -c '
  mount --bind "$0" /mnt && mount --bind "$d/tmp" /tmp && mkdir -p "$0" &&
  mount --bind /mnt "$0" && umount /mnt &&
  exec unshare --map-user="$uid" --map-group="$gid" bash -c "cd \"\$d/repo\" && exec env -i HOME=\"\$HOME\" PATH=\"\$PATH\" TERM=xterm LANG=C.UTF-8 CLAUDE_CONFIG_DIR=\"\$cc\" timeout 2700 claude -p --output-format stream-json --verbose --permission-mode bypassPermissions --max-budget-usd 20 \"\$prompt\""
' "$E" >"$d/out.jsonl" 2>"$d/err.txt"
echo "exit=$? wall=$(( $(date +%s) - start ))" > "$d/exit.txt"
cd "$w" && python3 "$here/hidden/$task.py" >"$d/hidden.txt" 2>&1; echo "hidden_exit=$?" >> "$d/exit.txt"
python3 -m unittest -q >"$d/visible.txt" 2>&1; echo "visible_exit=$?" >> "$d/exit.txt"
git add -A >/dev/null 2>&1
git diff --cached "$(cat "$d/base")" -- . ':(exclude).claude' ':(exclude)apm.yml' ':(exclude)apm.lock.yaml' > "$d/diff.patch"
echo "done $cfg-$task-$rep $(cat "$d/exit.txt" | tr '\n' ' ')"
