#!/usr/bin/env bash
# mark-spec-implemented-bare-key-selftest.sh
#
# AC35 + AC-NEG13: mark-spec-implemented.sh handles bare DP container keys
# (DP-NNN) by marking all active T*/V* tasks IMPLEMENTED, setting the parent
# index.md status to IMPLEMENTED, and archiving the container. ABANDONED active
# siblings are carved out: not migrated to IMPLEMENTED and not blocking parent
# closeout. The existing per-task mode (DP-NNN-T1) keeps backward-compat.
#
# Run:
#   bash scripts/selftests/mark-spec-implemented-bare-key-selftest.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d -t mark-spec-implemented-bare-selftest.XXXXXX)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Provide a fake `mise` + `node` shim that the close-parent-spec lifecycle
# reconciler uses (it spawns node reconcile-spec-lifecycle.mjs <parent>).
# The shim simply rewrites the parent file frontmatter status to IMPLEMENTED,
# matching the contract that the reconciler is supposed to enforce.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/mise" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "exec" ]]; then
  shift
  [[ "\${1:-}" == "--" ]] && shift
  if [[ "\${1:-}" == "bash" && "\${2:-}" == "-lc" ]]; then
    case "\${3:-}" in
      *"command -v node"*) echo "$TMP_ROOT/bin/node"; exit 0 ;;
      *) exit 0 ;;
    esac
  fi
  exec "\$@"
fi
exit 0
EOF
cat >"$TMP_ROOT/bin/node" <<'NODE_EOF'
#!/usr/bin/env bash
set -euo pipefail
script="${1:-}"
if [[ "$script" == *"reconcile-spec-lifecycle.mjs" ]]; then
  parent="${@: -1}"
  python3 - "$parent" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if text.startswith("---\n"):
    end = text.find("\n---\n", 4)
    if end != -1:
        fm = text[:end]
        body = text[end:]
        if re.search(r"^status:", fm, re.M):
            fm = re.sub(r"^status:.*$", "status: IMPLEMENTED", fm, flags=re.M)
        else:
            fm += "\nstatus: IMPLEMENTED"
        path.write_text(fm + body, encoding="utf-8")
        print("status: IMPLEMENTED")
        raise SystemExit(0)
path.write_text("---\nstatus: IMPLEMENTED\n---\n" + text, encoding="utf-8")
print("status: IMPLEMENTED")
PY
  exit 0
fi
echo "fake node"
NODE_EOF
chmod +x "$TMP_ROOT/bin/mise" "$TMP_ROOT/bin/node"
export PATH="$TMP_ROOT/bin:$PATH"

ARCHIVE_LOG="$TMP_ROOT/archive.log"
ARCHIVE_STUB="$TMP_ROOT/archive-spec-stub.sh"
cat >"$ARCHIVE_STUB" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${MARK_SPEC_ARCHIVE_LOG:?}"
# Simulate archive by moving the resolved container under design-plans/archive/.
WORKSPACE=""
SOURCE_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    *) SOURCE_PATH="$1"; shift ;;
  esac
done
[ -n "$SOURCE_PATH" ] || exit 0
container_dir="$(dirname "$SOURCE_PATH")"
[ -d "$container_dir" ] || exit 0
parent_dir="$(dirname "$container_dir")"
archive_dir="$parent_dir/archive"
mkdir -p "$archive_dir"
mv "$container_dir" "$archive_dir/"
SH
chmod +x "$ARCHIVE_STUB"

# -----------------------------------------------------------------------------
# Fixture 1 — Bare DP key (AC35): DP container with T1 + V1 + ABANDONED T2.
# Expected: T1/V1 → IMPLEMENTED (moved to pr-release/), T2 stays ABANDONED
# in place, parent index.md gets status=IMPLEMENTED, container is archived.
# -----------------------------------------------------------------------------
DP_DIR1="$TMP_ROOT/docs-manager/src/content/docs/specs/design-plans/DP-700-bare-key-implementation"
mkdir -p "$DP_DIR1/tasks/T1" "$DP_DIR1/tasks/T2" "$DP_DIR1/tasks/V1"
cat >"$DP_DIR1/index.md" <<'MD'
---
title: "DP-700 bare key implementation"
description: "Fixture for bare DP closeout selftest."
status: LOCKED
---

# DP-700

## Implementation Checklist
- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Abandoned task — `tasks/T2/index.md`
- [ ] V1: Verify — `tasks/V1/index.md`
MD
cat >"$DP_DIR1/tasks/T1/index.md" <<'MD'
---
title: "DP-700 T1"
status: IN_PROGRESS
verification:
  behavior_contract:
    applies: false
---

# T1

> Source: DP-700 | Task: DP-700-T1 | JIRA: N/A | Repo: polaris-framework
MD
cat >"$DP_DIR1/tasks/T2/index.md" <<'MD'
---
title: "DP-700 T2"
status: ABANDONED
---

# T2

> Source: DP-700 | Task: DP-700-T2 | JIRA: N/A | Repo: polaris-framework
MD
cat >"$DP_DIR1/tasks/V1/index.md" <<'MD'
---
title: "DP-700 V1"
status: IN_PROGRESS
ac_verification:
  status: PASS
---

# V1

> Source: DP-700 | Task: DP-700-V1 | JIRA: N/A | Repo: polaris-framework
MD

env -u MARK_SPEC_IMPLEMENTED_SELFTEST \
    MARK_SPEC_ARCHIVE_SPEC_BIN="$ARCHIVE_STUB" \
    MARK_SPEC_ARCHIVE_LOG="$ARCHIVE_LOG" \
  bash "$ROOT/scripts/mark-spec-implemented.sh" DP-700 \
    --workspace "$TMP_ROOT" --auto-archive >/dev/null

# Container must have been archived
[ ! -d "$DP_DIR1" ] || {
  echo "[selftest] FAIL: AC35 — bare DP container was not archived after auto-archive" >&2
  exit 1
}
ARCHIVED_DIR="$TMP_ROOT/docs-manager/src/content/docs/specs/design-plans/archive/DP-700-bare-key-implementation"
[ -d "$ARCHIVED_DIR" ] || {
  echo "[selftest] FAIL: AC35 — archived container missing at expected path" >&2
  exit 1
}

# Parent index.md status = IMPLEMENTED
grep -q '^status: IMPLEMENTED$' "$ARCHIVED_DIR/index.md" || {
  echo "[selftest] FAIL: AC35 — parent index.md status not IMPLEMENTED" >&2
  exit 1
}

# T1 was moved to pr-release/ with status IMPLEMENTED
[ ! -d "$ARCHIVED_DIR/tasks/T1" ] || {
  echo "[selftest] FAIL: AC35 — T1 should have been moved to pr-release/" >&2
  exit 1
}
[ -f "$ARCHIVED_DIR/tasks/pr-release/T1/index.md" ] || {
  echo "[selftest] FAIL: AC35 — T1 pr-release artifact missing" >&2
  exit 1
}
grep -q '^status: IMPLEMENTED$' "$ARCHIVED_DIR/tasks/pr-release/T1/index.md" || {
  echo "[selftest] FAIL: AC35 — T1 pr-release status not IMPLEMENTED" >&2
  exit 1
}

# V1 was also moved to pr-release/ with status IMPLEMENTED
[ -f "$ARCHIVED_DIR/tasks/pr-release/V1/index.md" ] || {
  echo "[selftest] FAIL: AC35 — V1 pr-release artifact missing" >&2
  exit 1
}
grep -q '^status: IMPLEMENTED$' "$ARCHIVED_DIR/tasks/pr-release/V1/index.md" || {
  echo "[selftest] FAIL: AC35 — V1 pr-release status not IMPLEMENTED" >&2
  exit 1
}

# AC-NEG13: ABANDONED T2 stays in tasks/ (not moved) and status preserved as ABANDONED.
[ -f "$ARCHIVED_DIR/tasks/T2/index.md" ] || {
  echo "[selftest] FAIL: AC-NEG13 — ABANDONED T2 was unexpectedly moved" >&2
  exit 1
}
grep -q '^status: ABANDONED$' "$ARCHIVED_DIR/tasks/T2/index.md" || {
  echo "[selftest] FAIL: AC-NEG13 — ABANDONED T2 status was silently migrated" >&2
  exit 1
}
[ ! -f "$ARCHIVED_DIR/tasks/pr-release/T2/index.md" ] || {
  echo "[selftest] FAIL: AC-NEG13 — ABANDONED T2 should not be moved to pr-release/" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Fixture 2 — Per-task backward compatibility: DP-NNN-Tn keeps existing behavior.
# -----------------------------------------------------------------------------
DP_DIR2="$TMP_ROOT/docs-manager/src/content/docs/specs/design-plans/DP-701-per-task-backcompat"
mkdir -p "$DP_DIR2/tasks/T1"
cat >"$DP_DIR2/index.md" <<'MD'
---
title: "DP-701 per-task backcompat"
status: LOCKED
---
# DP-701

## Implementation Checklist
- [ ] T1: First task — `tasks/T1/index.md`
MD
cat >"$DP_DIR2/tasks/T1/index.md" <<'MD'
---
title: "DP-701 T1"
status: IN_PROGRESS
---
# T1

> Source: DP-701 | Task: DP-701-T1 | JIRA: N/A | Repo: polaris-framework
MD

env -u MARK_SPEC_IMPLEMENTED_SELFTEST \
    MARK_SPEC_ARCHIVE_SPEC_BIN="$ARCHIVE_STUB" \
    MARK_SPEC_ARCHIVE_LOG="$ARCHIVE_LOG" \
  bash "$ROOT/scripts/mark-spec-implemented.sh" DP-701-T1 \
    --workspace "$TMP_ROOT" >/dev/null

[ ! -d "$DP_DIR2/tasks/T1" ] || {
  echo "[selftest] FAIL: backward-compat — per-task DP-701-T1 was not moved to pr-release/" >&2
  exit 1
}
[ -f "$DP_DIR2/tasks/pr-release/T1/index.md" ] || {
  echo "[selftest] FAIL: backward-compat — per-task pr-release artifact missing" >&2
  exit 1
}
grep -q '^status: IMPLEMENTED$' "$DP_DIR2/tasks/pr-release/T1/index.md" || {
  echo "[selftest] FAIL: backward-compat — per-task pr-release status not IMPLEMENTED" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Fixture 3 — close-parent-spec-if-complete: ABANDONED sibling does not block.
# -----------------------------------------------------------------------------
DP_DIR3="$TMP_ROOT/docs-manager/src/content/docs/specs/design-plans/DP-702-abandoned-sibling-carveout"
mkdir -p "$DP_DIR3/tasks/T2" "$DP_DIR3/tasks/pr-release/T1"
cat >"$DP_DIR3/index.md" <<'MD'
---
title: "DP-702 abandoned sibling carveout"
description: "AC-NEG13 fixture."
status: LOCKED
---

# DP-702

## Implementation Checklist
- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Abandoned task — `tasks/T2/index.md`
MD
cat >"$DP_DIR3/tasks/T2/index.md" <<'MD'
---
title: "DP-702 T2"
status: ABANDONED
---
# T2

> Source: DP-702 | Task: DP-702-T2 | JIRA: N/A | Repo: polaris-framework
MD
cat >"$DP_DIR3/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-702 T1"
status: IMPLEMENTED
---
# T1

> Source: DP-702 | Task: DP-702-T1 | JIRA: N/A | Repo: polaris-framework
MD

env -u CLOSE_PARENT_SPEC_SELFTEST \
  bash "$ROOT/scripts/close-parent-spec-if-complete.sh" \
    --task-md "$DP_DIR3/tasks/pr-release/T1/index.md" \
    --workspace "$TMP_ROOT" >/dev/null || {
      echo "[selftest] FAIL: AC-NEG13 — close-parent-spec-if-complete blocked despite only ABANDONED sibling remaining" >&2
      exit 1
    }
grep -q '^status: IMPLEMENTED$' "$DP_DIR3/index.md" || {
  echo "[selftest] FAIL: AC-NEG13 — parent was not closed when only ABANDONED sibling remained" >&2
  exit 1
}
grep -q '^status: ABANDONED$' "$DP_DIR3/tasks/T2/index.md" || {
  echo "[selftest] FAIL: AC-NEG13 — ABANDONED sibling status was silently migrated by close-parent-spec" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Fixture 4 — IN_PROGRESS sibling still blocks (AC35 adversarial pass)
# -----------------------------------------------------------------------------
DP_DIR4="$TMP_ROOT/docs-manager/src/content/docs/specs/design-plans/DP-703-in-progress-blocker"
mkdir -p "$DP_DIR4/tasks/T2" "$DP_DIR4/tasks/pr-release/T1"
cat >"$DP_DIR4/index.md" <<'MD'
---
title: "DP-703 in-progress blocker"
status: LOCKED
---
# DP-703

## Implementation Checklist
- [ ] T1: First task — `tasks/T1/index.md`
- [ ] T2: Active task — `tasks/T2/index.md`
MD
cat >"$DP_DIR4/tasks/T2/index.md" <<'MD'
---
title: "DP-703 T2"
status: IN_PROGRESS
---
# T2

> Source: DP-703 | Task: DP-703-T2 | JIRA: N/A | Repo: polaris-framework
MD
cat >"$DP_DIR4/tasks/pr-release/T1/index.md" <<'MD'
---
title: "DP-703 T1"
status: IMPLEMENTED
---
# T1

> Source: DP-703 | Task: DP-703-T1 | JIRA: N/A | Repo: polaris-framework
MD

env -u CLOSE_PARENT_SPEC_SELFTEST \
  bash "$ROOT/scripts/close-parent-spec-if-complete.sh" \
    --task-md "$DP_DIR4/tasks/pr-release/T1/index.md" \
    --workspace "$TMP_ROOT" >/dev/null 2>&1
# IN_PROGRESS T2 should be treated as a blocking active sibling — parent stays LOCKED.
if grep -q '^status: IMPLEMENTED$' "$DP_DIR4/index.md"; then
  echo "[selftest] FAIL: AC35 adversarial — parent closed despite IN_PROGRESS T2 sibling" >&2
  exit 1
fi

echo "[selftest] PASS: mark-spec-implemented bare-key + ABANDONED carve-out"
