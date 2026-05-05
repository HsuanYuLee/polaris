#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIGRATE="$ROOT/scripts/migrate-spec-container-layout.sh"
tmpdir="$(mktemp -d -t migrate-spec-layout.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

specs="$tmpdir/specs"
mkdir -p \
  "$specs/design-plans/DP-001-legacy" \
  "$specs/design-plans/archive/DP-002-archived" \
  "$specs/companies/acme/ACME-1/tasks/pr-release" \
  "$specs/companies/acme/ACME-1/assets" \
  "$specs/companies/acme/ACME-2/tasks/T1" \
  "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/assets/screenshots" \
  "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload"

cat >"$specs/design-plans/DP-001-legacy/plan.md" <<'MD'
---
title: "DP-001: Legacy"
description: "Legacy DP."
---

## Body
MD
cat >"$specs/design-plans/archive/DP-002-archived/plan.md" <<'MD'
---
title: "DP-002: Archived"
description: "Archived DP."
---
MD
cat >"$specs/companies/acme/ACME-1/refinement.md" <<'MD'
---
title: "ACME-1"
description: "Legacy company spec."
---
MD
cat >"$specs/companies/acme/ACME-1/tasks/T1.md" <<'MD'
---
title: "T1"
description: "Task."
---

![screen](./assets/screen.png)
MD
cat >"$specs/companies/acme/ACME-1/tasks/pr-release/T2.md" <<'MD'
---
title: "T2"
description: "Done task."
status: IMPLEMENTED
---
MD
cat >"$specs/companies/acme/ACME-2/tasks/T1.md" <<'MD'
---
title: "T1 legacy"
description: "Collision."
---
MD
cat >"$specs/companies/acme/ACME-2/tasks/T1/index.md" <<'MD'
---
title: "T1 folder"
description: "Collision."
---
MD

printf 'old\n' >"$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/legacy.png"
printf 'new\n' >"$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/assets/screenshots/new.png"
touch "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/links.json"
touch "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/publication-manifest.json"
touch "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/verify-report.md"
printf 'old\n' >"$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/legacy.png"

before_hash="$(find "$specs" -type f -print0 | sort -z | xargs -0 shasum | shasum)"
dry="$(bash "$MIGRATE" --specs-root "$specs" --dry-run)"
after_hash="$(find "$specs" -type f -print0 | sort -z | xargs -0 shasum | shasum)"
[[ "$before_hash" == "$after_hash" ]] || { echo "dry-run modified files" >&2; exit 1; }
grep -q '"action": "move"' <<<"$dry"
grep -q '"action": "blocked_collision"' <<<"$dry"
grep -q 'DP-002-archived' <<<"$dry" && { echo "archive should be skipped by default" >&2; exit 1; }

if bash "$MIGRATE" --specs-root "$specs" --apply --cleanup-legacy-bundles >/tmp/migrate-layout-blocked.json 2>/tmp/migrate-layout-blocked.err; then
  echo "apply should fail when collision or cleanup blockers exist" >&2
  exit 1
fi
grep -q '"action": "blocked_collision"' /tmp/migrate-layout-blocked.json
grep -q '"action": "blocked_cleanup"' /tmp/migrate-layout-blocked.json
grep -q 'no files were changed' /tmp/migrate-layout-blocked.err
[[ -f "$specs/design-plans/DP-001-legacy/plan.md" ]]
[[ -f "$specs/companies/acme/ACME-1/refinement.md" ]]
[[ -f "$specs/companies/acme/ACME-1/tasks/T1.md" ]]
[[ -f "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/legacy.png" ]]
[[ -f "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/legacy.png" ]]

rm "$specs/companies/acme/ACME-2/tasks/T1.md"
mkdir -p "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/assets"
touch "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/links.json"
touch "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/publication-manifest.json"
touch "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/verify-report.md"

bash "$MIGRATE" --specs-root "$specs" --apply --cleanup-legacy-bundles >/tmp/migrate-layout-apply.json
[[ -f "$specs/design-plans/DP-001-legacy/index.md" ]]
[[ ! -f "$specs/design-plans/DP-001-legacy/plan.md" ]]
[[ -f "$specs/design-plans/archive/DP-002-archived/plan.md" ]]
[[ -f "$specs/companies/acme/ACME-1/index.md" ]]
[[ -f "$specs/companies/acme/ACME-1/tasks/T1/index.md" ]]
grep -q '](../assets/screen.png)' "$specs/companies/acme/ACME-1/tasks/T1/index.md"
[[ -f "$specs/companies/acme/ACME-1/tasks/pr-release/T2/index.md" ]]
[[ -f "$specs/companies/acme/ACME-2/tasks/T1/index.md" ]]
[[ ! -f "$specs/companies/acme/ACME-3/artifacts/TASK-3-pr-upload/legacy.png" ]]
[[ ! -f "$specs/companies/acme/ACME-4/artifacts/TASK-4-pr-upload/legacy.png" ]]
! grep -q '"action": "blocked_' /tmp/migrate-layout-apply.json

bash "$MIGRATE" --specs-root "$specs" --apply --include-archive >/tmp/migrate-layout-archive.json
[[ -f "$specs/design-plans/archive/DP-002-archived/index.md" ]]
[[ ! -f "$specs/design-plans/archive/DP-002-archived/plan.md" ]]

echo "PASS: migrate spec container layout selftest"
