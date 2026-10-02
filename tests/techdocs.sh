#!/usr/bin/env bash
# Tests for the Backstage TechDocs entry points: catalog-info.yaml and mkdocs.yml.
#
# Backstage builds docs/ from these two files inside its own Pod, so a typo here
# only shows up there. This checks what can be known offline: the techdocs-ref
# annotation, the plugin, and that every nav entry is a file under docs_dir.
# It does not run mkdocs -- that needs the network and a Python toolchain.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# No yq on host; this uses the same python3 + PyYAML that lint-yaml relies on.
if ! python3 - "$root" <<'PY'
import os, sys, yaml

root = sys.argv[1]
errors = []

def load(name):
    with open(os.path.join(root, name)) as f:
        return yaml.safe_load(f)

catalog = load("catalog-info.yaml")
if catalog.get("kind") != "Component":
    errors.append("catalog-info.yaml: kind is not Component")
if catalog.get("metadata", {}).get("name") != "dotfiles":
    errors.append("catalog-info.yaml: metadata.name is not dotfiles")
ann = catalog.get("metadata", {}).get("annotations", {})
if ann.get("backstage.io/techdocs-ref") != "dir:.":
    errors.append("catalog-info.yaml: backstage.io/techdocs-ref is not dir:.")
if not ann.get("github.com/project-slug"):
    errors.append("catalog-info.yaml: github.com/project-slug is missing")
if not catalog.get("spec", {}).get("owner"):
    errors.append("catalog-info.yaml: spec.owner is missing")

mk = load("mkdocs.yml")
if "techdocs-core" not in (mk.get("plugins") or []):
    errors.append("mkdocs.yml: plugins does not include techdocs-core")
docs_dir = mk.get("docs_dir", "docs")
if not os.path.isdir(os.path.join(root, docs_dir)):
    errors.append(f"mkdocs.yml: docs_dir {docs_dir} is not a directory")

def pages(nav):
    for item in nav:
        if isinstance(item, dict):
            for v in item.values():
                yield from pages(v) if isinstance(v, list) else [v]
        else:
            yield item

nav = {p for p in pages(mk.get("nav") or [])}
for page in sorted(nav):
    if not os.path.isfile(os.path.join(root, docs_dir, page)):
        errors.append(f"mkdocs.yml: nav entry {page} is not under {docs_dir}/")

# A page missing from nav still builds, but Backstage lists it nowhere.
for name in sorted(os.listdir(os.path.join(root, docs_dir))):
    if name.endswith(".md") and name not in nav:
        errors.append(f"mkdocs.yml: {docs_dir}/{name} is not in nav")

for e in errors:
    print(f"FAIL: {e}", file=sys.stderr)
sys.exit(1 if errors else 0)
PY
then
  exit 1
fi
echo "techdocs tests ok"
