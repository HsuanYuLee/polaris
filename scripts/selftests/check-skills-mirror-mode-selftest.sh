#!/usr/bin/env bash
# scripts/selftests/check-skills-mirror-mode-selftest.sh — DP-230 T6.
#
# Verifies scripts/check-skills-mirror-mode.sh on a synthetic fixture so the
# selftest is portable to fresh git clone / detached HEAD scenarios where
# `git rev-parse --show-toplevel` either fails or points at a non-framework
# root. The selftest resolves its own framework ROOT_DIR via the DP-230 T6
# BASH_SOURCE-derived bootstrap.
#
# Cases:
#   AC15-CASE1  fixture has .agents/skills → ../.claude/skills symlink + minimal
#               mise.toml/polaris-toolchain.yaml entries → check-skills-mirror-mode
#               exits 0.
#   AC15-CASE2  fixture has .agents/skills as a directory (not symlink) →
#               check-skills-mirror-mode exits non-zero (mirror drift signal).
#
# Both cases run inside a tmpdir, so this selftest neither depends on the live
# workspace .agents/skills state nor mutates it.

set -euo pipefail

# shellcheck source=../lib/selftest-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/selftest-bootstrap.sh"
init_ROOT_DIR "${BASH_SOURCE[0]}"

SCRIPT="$ROOT_DIR/scripts/check-skills-mirror-mode.sh"
if [[ ! -f "$SCRIPT" ]]; then
  echo "FAIL: missing $SCRIPT" >&2
  exit 1
fi

WORKDIR="$(mktemp -d -t dp230-t6.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

stage_fixture_root() {
  local root="$1"
  mkdir -p "$root/.claude/skills"
  mkdir -p "$root/.agents"
  mkdir -p "$root/scripts"

  cat >"$root/mise.toml" <<'EOF'
[tasks.bootstrap]
description = "fixture"
run = "echo bootstrap"

[tasks.doctor]
description = "fixture"
run = "echo doctor"

[tasks.doctor-mise]
description = "fixture"
run = "echo doctor-mise"

[tasks.onboard-doctor]
description = "fixture"
run = "echo onboard-doctor"

[tasks.release-preflight]
description = "fixture"
run = "echo release-preflight"

[tasks.pr-create]
description = "fixture"
run = "echo pr-create"

[tasks.spec-close-parent]
description = "fixture"
run = "echo spec-close-parent"

[tasks.script-audit]
description = "fixture"
run = "echo script-audit"

[tasks.docs-health]
description = "fixture"
run = "echo docs-health"

[tasks.verify]
description = "fixture"
run = "echo verify"

[tasks.cross-runtime-sync]
description = "fixture"
run = "echo cross-runtime-sync"
EOF

  cat >"$root/polaris-toolchain.yaml" <<'EOF'
tasks:
  bootstrap: fixture
  doctor: fixture
  doctor-mise: fixture
  onboard-doctor: fixture
  release-preflight: fixture
  pr-create: fixture
  spec-close-parent: fixture
  script-audit: fixture
  docs-health: fixture
  verify: fixture
  cross-runtime-sync: fixture
EOF

  # Mirror the check script under the fixture so the relative `$ROOT_DIR`
  # computation inside check-skills-mirror-mode.sh resolves to the fixture
  # root when we invoke the fixture copy.
  cp "$SCRIPT" "$root/scripts/check-skills-mirror-mode.sh"
}

# ---- CASE 1: happy path ----
case1="$WORKDIR/case1"
stage_fixture_root "$case1"
ln -s "../.claude/skills" "$case1/.agents/skills"

if ! bash "$case1/scripts/check-skills-mirror-mode.sh" >"$WORKDIR/case1.stdout" 2>"$WORKDIR/case1.stderr"; then
  echo "FAIL: AC15-CASE1 expected exit 0 from check-skills-mirror-mode on symlinked fixture" >&2
  echo "stdout:" >&2
  cat "$WORKDIR/case1.stdout" >&2
  echo "stderr:" >&2
  cat "$WORKDIR/case1.stderr" >&2
  exit 1
fi

# ---- CASE 2: drift fixture (directory, not symlink) ----
case2="$WORKDIR/case2"
stage_fixture_root "$case2"
mkdir -p "$case2/.agents/skills"

if bash "$case2/scripts/check-skills-mirror-mode.sh" >"$WORKDIR/case2.stdout" 2>"$WORKDIR/case2.stderr"; then
  echo "FAIL: AC15-CASE2 expected non-zero exit when .agents/skills is a directory" >&2
  echo "stdout:" >&2
  cat "$WORKDIR/case2.stdout" >&2
  echo "stderr:" >&2
  cat "$WORKDIR/case2.stderr" >&2
  exit 1
fi

echo "PASS: scripts/selftests/check-skills-mirror-mode-selftest.sh (DP-230 T6 AC15)"
