#!/usr/bin/env bash
# Selftest for scripts/infer-starlight-descriptions.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFER="$SCRIPT_DIR/infer-starlight-descriptions.sh"

fail() {
  echo "[selftest] FAIL: $*" >&2
  exit 1
}

tmpdir="$(mktemp -d -t starlight-description-infer.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/specs/tasks" "$tmpdir/specs/artifacts" "$tmpdir/docs-manager/dist"

cat >"$tmpdir/specs/plan.md" <<'MD'
---
title: "Plan Title"
---

這是一段可作為摘要的第一段內容，描述文件的主要目的。

## Details
MD

cat >"$tmpdir/specs/tasks/T1.md" <<'MD'
---
title: "Work Order - T1: Demo Task (1 pt)"
---

# T1: Demo Task (1 pt)
MD

cat >"$tmpdir/specs/artifacts/evidence.md" <<'MD'
---
title: "Evidence Artifact"
---

```text
raw
```
MD

cat >"$tmpdir/specs/existing.md" <<'MD'
---
title: "Existing"
description: "Already done."
---
MD

cat >"$tmpdir/docs-manager/dist/generated.md" <<'MD'
---
title: "Generated"
---
MD

bash "$INFER" --dry-run --report "$tmpdir/report.md" "$tmpdir/specs" >"$tmpdir/dry-run.tsv"
grep -q $'inferred\tfirst-paragraph' "$tmpdir/dry-run.tsv" || fail "missing first paragraph inference"
grep -q $'inferred\ttask-title' "$tmpdir/dry-run.tsv" || fail "missing task inference"
grep -q $'inferred\tartifact-title' "$tmpdir/dry-run.tsv" || fail "missing artifact inference"
grep -q $'skipped\thas-description' "$tmpdir/dry-run.tsv" || fail "missing existing-description skip"
! grep -q '^description:' "$tmpdir/specs/plan.md" || fail "dry-run modified file"
grep -q 'DP-067 Legacy Description Inference Report' "$tmpdir/report.md" || fail "report missing title"

bash "$INFER" --apply --report "$tmpdir/report-apply.md" "$tmpdir/specs" >"$tmpdir/apply.tsv"
grep -q '^description: "這是一段可作為摘要的第一段內容，描述文件的主要目的。"$' "$tmpdir/specs/plan.md" || fail "apply missing paragraph description"
grep -q '^description: "此工單描述 T1: Demo Task (1 pt) 的實作或驗收範圍。"$' "$tmpdir/specs/tasks/T1.md" || fail "apply missing task description"
grep -q '^description: "此 artifact 記錄 Evidence Artifact 的執行脈絡與證據。"$' "$tmpdir/specs/artifacts/evidence.md" || fail "apply missing artifact description"

if bash "$INFER" --dry-run "$tmpdir/docs-manager/dist" >/tmp/starlight-description-infer-dist.out 2>&1; then
  fail "generated output path was accepted"
fi

echo "[selftest] PASS"
