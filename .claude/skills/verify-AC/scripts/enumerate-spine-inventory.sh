#!/usr/bin/env bash
# Purpose: Produce the inventory check-spine-cost-floor.sh consumes, by looking at
#          what a delivery actually left behind rather than by asking someone to
#          list it.
# Inputs:  --issue <dir>, optional --base <ref> (default origin/main),
#          optional --out <path> (default {issue}/.spine/inventory.json).
# Outputs: the inventory JSON at --out; a one-line summary on stderr.
#          Exit 2 on usage or a missing source.
#
# Why this exists
# ---------------
# The cost floor was asserted and then never measured, because the check needs an
# inventory and nothing produced one. A hand-written inventory is worse than none:
# whoever writes it decides what to leave out, and the check goes green on the
# omission. This enumerates from two sources that cannot be talked out of it — the
# git diff of the delivery, and the .spine directory sitting on disk.
#
# What counts as forced
# ---------------------
# "Forced" means a stage of the flow refuses to finish without the file. That is a
# question about the flow, not about effort, so the rule is stated here rather than
# left to the caller:
#
#   {issue}/index.md               refinement seals it, verify-ac verifies it
#   .spine/loop-state.json          engineering cannot record a round without it
#   .spine/measurement-ledger.json  judge refuses a command it has not sanctioned
#   .spine/delivery.json            the release tail has nothing to read without it
#   .changeset/*.md                 a template-bound release does not bump without one
#
# Everything else the delivery touched is the work itself, not the toll, and is
# listed with forced=false so the inventory stays complete without inflating the
# count.
#
# Machine-written state is counted. It would be easy to argue .spine/*.json is not
# "a document someone was forced to write" and drop it, and the count would fit the
# floor immediately — which is exactly why that call is not made here. Whether the
# floor means authored files or all forced files is a question about the assertion,
# and assertions are changed at the first gate by a person, not by the tool that
# measures them.

set -euo pipefail

ISSUE_DIR=""
BASE_REF="origin/main"
OUT=""

die() {
  local marker="$1"; shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  enumerate-spine-inventory.sh --issue <dir> [--base <ref>] [--out <path>]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE_DIR="${2:-}"; shift 2 ;;
    --base)   BASE_REF="${2:-}"; shift 2 ;;
    --out)    OUT="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$ISSUE_DIR" ]] || usage
ISSUE_DIR="${ISSUE_DIR%/}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$REPO_ROOT" ]] || die "POLARIS_SPINE_INVENTORY_NO_REPO" "not inside a git repository"
[[ -d "$REPO_ROOT/$ISSUE_DIR" ]] || die "POLARIS_SPINE_INVENTORY_SOURCE_MISSING" \
  "no source directory at $ISSUE_DIR"

[[ -n "$OUT" ]] || OUT="$REPO_ROOT/$ISSUE_DIR/.spine/inventory.json"

# A base that does not resolve would silently produce an empty diff, and an empty
# diff reads as "this delivery forced nothing" — the most flattering possible lie.
git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1 \
  || die "POLARIS_SPINE_INVENTORY_BAD_BASE" \
    "cannot resolve --base '$BASE_REF'; an unresolvable base would report an empty delivery"

CHANGED="$(git -C "$REPO_ROOT" diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true)"

python3 - "$REPO_ROOT" "$ISSUE_DIR" "$OUT" "$CHANGED" <<'PY'
import json
import os
import sys
from pathlib import Path

root, source_dir, out, changed_blob = sys.argv[1:5]
root = Path(root)
changed = [line.strip() for line in changed_blob.splitlines() if line.strip()]

spine = root / source_dir / ".spine"
spine_state = {
    f"{source_dir}/.spine/loop-state.json": "work 沒有它就記不了輪次",
    f"{source_dir}/.spine/measurement-ledger.json": "judge 不承認沒登錄過的量測命令",
    f"{source_dir}/.spine/delivery.json": "釋出尾段沒有它就沒東西可讀",
}

artifacts = []
seen = set()


def add(path, forced, reason=None):
    if path in seen:
        return
    seen.add(path)
    entry = {"path": path, "forced": bool(forced)}
    if reason:
        entry["reason"] = reason
    artifacts.append(entry)


add(f"{source_dir}/index.md", True, "斷言與活文件的載體：assert 蓋封條、judge 驗它")

for path, reason in spine_state.items():
    if (root / path).exists():
        add(path, True, reason)

for path in changed:
    if path.startswith(".changeset/") and path.endswith(".md"):
        add(path, True, "出貨到 template 的交付沒有它就不壓版")
    else:
        add(path, False)

# Anything the flow wrote but nobody has to read is listed for completeness and
# not charged: judge's --evidence-out is optional, and an optional file is not a
# toll.
if spine.exists():
    for entry in sorted(spine.rglob("*")):
        if entry.is_file():
            add(entry.relative_to(root).as_posix(), False)

code_paths = [p for p in changed if not p.startswith(f"{source_dir}/") and not p.endswith(".md")]
kind = "code" if code_paths else "docs"

payload = {
    "schema_version": 1,
    "producer": "enumerate-spine-inventory.sh",
    "source": source_dir,
    "kind": kind,
    "artifacts": artifacts,
}

os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

forced = [a for a in artifacts if a["forced"]]
print(f"ENUMERATED: {out}", file=sys.stderr)
print(f"  kind={kind} forced={len(forced)} listed={len(artifacts)}", file=sys.stderr)
for a in forced:
    print(f"    forced  {a['path']}", file=sys.stderr)
PY
