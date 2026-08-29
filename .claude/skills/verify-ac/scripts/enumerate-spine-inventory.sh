#!/usr/bin/env bash
# Purpose: Produce the inventory check-spine-legacy-layers.sh consumes, by looking at
#          what a delivery actually left behind rather than by asking someone to
#          list it.
# Inputs:  --issue <dir>, optional --repo <dir> (the tree the delivery landed in),
#          optional --base <ref> (default: that repo's own default branch).
# Outputs: the inventory JSON at {issue}/.spine/inventory.json; a one-line
#          summary on stderr.
#          Exit 2 on usage or a missing source.
#
# Why this exists
# ---------------
# The legacy-layer check was asserted and then never measured, because it needs an
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
REPO_ROOT=""
BASE_REF=""

die() {
  local marker="$1"; shift
  echo "$marker" >&2
  printf '%s\n' "$@" >&2
  exit 2
}

usage() {
  cat >&2 <<'EOF'
Usage:
  enumerate-spine-inventory.sh --issue <dir> [--repo <dir>] [--base <ref>]

  --repo  改動落在哪棵樹（預設：單自己住的那個 repo）
  --base  拿什麼當 diff 的起點（預設：那個 repo 自己的預設分支）
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUE_DIR="${2:-}"; shift 2 ;;
    --repo)   REPO_ROOT="${2:-}"; shift 2 ;;
    --base)   BASE_REF="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$ISSUE_DIR" ]] || usage
ISSUE_DIR="${ISSUE_DIR%/}"

# 一張單住在哪、它的改動落在哪，是兩棵樹。單住在 issues/（使用者自己的 repo），改動可能
# 落在任何一個產品 repo——那是常態，不是特例。所以這裡收兩個路徑，不從當下站的位置推。
#
# DP-482：這一行原本是 `git rev-parse --show-toplevel`，量的是呼叫者站的地方。對一張單
# 住在 A、改動落在 B 的單，它拿 A 的 diff 去回答「這次交付留下了什麼」，而舊層偵測就是
# 拿這份清單判的——B 裡真的還撐著一層舊的，這份清單永遠看不到它，而且看起來很完整。
ISSUE_ABS="$(cd "$ISSUE_DIR" 2>/dev/null && pwd || true)"
[[ -n "$ISSUE_ABS" ]] || die "POLARIS_SPINE_INVENTORY_SOURCE_MISSING" \
  "no source directory at $ISSUE_DIR"

if [[ -z "$REPO_ROOT" ]]; then
  # 呼叫者沒說改動落在哪的時候，退回單自己住的那個 repo，並且說出來。退回是猜的，一個
  # 安靜的猜測跟一個被告知的事實在輸出上長得一樣。
  REPO_ROOT="$(git -C "$ISSUE_ABS" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$REPO_ROOT" ]] || die "POLARIS_SPINE_INVENTORY_NO_REPO" \
    "$ISSUE_DIR is not inside a git repository, and --repo was not given"
  echo "NOTE: --repo 沒有給，改動落在哪退回用單自己住的 repo：$REPO_ROOT" >&2
fi

# 清單只有一個落點，因為只有一個讀者：check-spine-legacy-layers.sh --inventory 讀的就是
# 這裡。以前這是一個旗標，而它從來沒有被任何呼叫者給過值。
OUT="$ISSUE_ABS/.spine/inventory.json"

# 預設的 base 是那個 repo 自己說的預設分支，不是一個硬編的名字。硬編 `origin/main` 的
# 那一版對每一個預設分支叫別的名字的 repo 都是紅的——而那不是「這張單有問題」，是這支
# 腳本假設了全世界的 repo 都跟框架自己長得一樣（DP-482 撞上的是 master）。
if [[ -z "$BASE_REF" ]]; then
  BASE_REF="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -z "$BASE_REF" ]]; then
    for candidate in origin/main origin/master main master; do
      if git -C "$REPO_ROOT" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
        BASE_REF="$candidate"
        break
      fi
    done
  fi
  [[ -n "$BASE_REF" ]] || die "POLARIS_SPINE_INVENTORY_NO_BASE" \
    "$REPO_ROOT 說不出它的預設分支，也找不到 origin/main、origin/master、main、master 任何一個。" \
    "用 --base 指名一個，不指名就沒有東西可以拿來 diff——而一份空的 diff 會被讀成「這次交付什麼都沒留下」。"
  echo "NOTE: --base 沒有給，用 $REPO_ROOT 自己的預設分支：$BASE_REF" >&2
fi

# A base that does not resolve would silently produce an empty diff, and an empty
# diff reads as "this delivery forced nothing" — the most flattering possible lie.
git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE_REF" >/dev/null 2>&1 \
  || die "POLARIS_SPINE_INVENTORY_BAD_BASE" \
    "cannot resolve --base '$BASE_REF'; an unresolvable base would report an empty delivery"

# `--diff-filter=d` 排掉被刪除的檔案。清單問的是「這次交付留下了什麼」，而刪掉的東西不是
# 留下的東西。這一條不只是語意整齊：舊層偵測是拿這份清單判的，不排掉刪除的話，一張把舊層
# 拆掉的單會因為它的 diff 提到那些路徑而被自己擋下來。
CHANGED="$(git -C "$REPO_ROOT" diff --name-only --diff-filter=d "$BASE_REF"...HEAD 2>/dev/null || true)"

python3 - "$REPO_ROOT" "$ISSUE_DIR" "$OUT" "$CHANGED" "$ISSUE_ABS" <<'PY'
import json
import os
import sys
from pathlib import Path

root, source_dir, out, changed_blob, issue_abs = sys.argv[1:6]
root = Path(root)
# 單住的地方與改動落的地方是兩棵樹，所以掃 .spine 用單的絕對路徑。
issue_abs = Path(issue_abs)
# 清單記的是單的**身分**（名字），不是它被寫下那一刻的格位（DP-496 L-P2）。位置由
# `spine-loop-state.sh find` 當場問得到，而存下來的位置在下一次重算之後就是死指標——
# 實測 `.spine/` 底下存過的 19 條單路徑，19 條全部指向已經不存在的目錄。
issue_name = issue_abs.name
changed = [line.strip() for line in changed_blob.splitlines() if line.strip()]

spine = issue_abs / ".spine"
# 單自己的東西用**單內相對路徑**，同樣的理由。舊層偵測的 pattern 都以 `(^|/)` 開頭或不錨定，
# 所以短路徑照樣被它們認得——這一點是查過 check-spine-legacy-layers.sh 的 LEGACY_PATTERNS
# 才改的，不是猜的。
spine_state = {
    ".spine/loop-state.json": "work 沒有它就記不了輪次",
    ".spine/measurement-ledger.json": "judge 不承認沒登錄過的量測命令",
    ".spine/delivery.json": "釋出尾段沒有它就沒東西可讀",
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


add("index.md", True, "assertion 與可改內容的載體：assert 算校驗值、judge 驗它")

for path, reason in spine_state.items():
    if (spine / Path(path).name).exists():
        add(path, True, reason)

for path in changed:
    if path.startswith(".changeset/") and path.endswith(".md"):
        add(path, True, "出貨到 template 的交付沒有它就不壓版")
    elif path.startswith(f"{source_dir}/"):
        # 單住在同一棵樹的時候（`issues/` 沒被 gitignore 的專案），它自己的檔案會出現在
        # diff 裡。原樣收下就等於把格位寫進清單，而格位下一次重算就變了（DP-496 L-P2）。
        add(path[len(source_dir) + 1:], False)
    else:
        add(path, False)

# Anything the flow wrote but nobody has to read is listed for completeness and
# not charged: judge's --evidence-out is optional, and an optional file is not a
# toll.
if spine.exists():
    for entry in sorted(spine.rglob("*")):
        if entry.is_file():
            add(f".spine/{entry.relative_to(spine).as_posix()}", False)

code_paths = [p for p in changed if not p.startswith(f"{source_dir}/") and not p.endswith(".md")]
kind = "code" if code_paths else "docs"

payload = {
    "schema_version": 2,
    "producer": "enumerate-spine-inventory.sh",
    "issue": issue_name,
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
