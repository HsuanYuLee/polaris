#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-verify-evidence-layout.sh"
TMP="$(mktemp -d -t dp207-verify-layout.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

make_valid() {
  local dir="$1"
  mkdir -p "$dir/assets/raw" "$dir/assets/images" "$dir/assets/screenshots" "$dir/assets/videos" "$dir/assets/files"
  cat >"$dir/verify-report.md" <<'MD'
---
title: "Verification report"
description: "Fixture verification report."
draft: true
sidebar:
  hidden: true
---

# Verification report
MD
  printf '%s\n' '[]' >"$dir/links.json"
  printf '%s\n' '{"schema_version":1,"artifacts":["verify-report.md"]}' >"$dir/publication-manifest.json"
}

valid="$TMP/valid"
make_valid "$valid"
bash "$VALIDATOR" "$valid" >/tmp/dp207-verify-layout-pass.out

missing_report="$TMP/missing-report"
make_valid "$missing_report"
rm "$missing_report/verify-report.md"
if bash "$VALIDATOR" "$missing_report" >/tmp/dp207-verify-layout-missing.out 2>&1; then
  echo "FAIL: missing verify-report.md should fail" >&2
  exit 1
fi
rg -n 'missing verify-report.md' /tmp/dp207-verify-layout-missing.out >/dev/null

loose_md="$TMP/loose-md"
make_valid "$loose_md"
touch "$loose_md/raw-output.md"
if bash "$VALIDATOR" "$loose_md" >/tmp/dp207-verify-layout-loose.out 2>&1; then
  echo "FAIL: loose markdown should fail" >&2
  exit 1
fi
rg -n 'unexpected markdown file' /tmp/dp207-verify-layout-loose.out >/dev/null

unknown_assets="$TMP/unknown-assets"
make_valid "$unknown_assets"
mkdir "$unknown_assets/assets/tmp"
if bash "$VALIDATOR" "$unknown_assets" >/tmp/dp207-verify-layout-assets.out 2>&1; then
  echo "FAIL: unknown assets subdir should fail" >&2
  exit 1
fi
rg -n 'unknown assets subdir' /tmp/dp207-verify-layout-assets.out >/dev/null

bad_manifest="$TMP/bad-manifest"
make_valid "$bad_manifest"
printf '%s\n' '{"schema_version":2}' >"$bad_manifest/publication-manifest.json"
if bash "$VALIDATOR" "$bad_manifest" >/tmp/dp207-verify-layout-manifest.out 2>&1; then
  echo "FAIL: bad manifest should fail" >&2
  exit 1
fi
rg -n 'schema_version must be 1|artifacts must be an array' /tmp/dp207-verify-layout-manifest.out >/dev/null

echo "PASS: validate verify evidence layout selftest"
