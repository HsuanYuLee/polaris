#!/usr/bin/env bash
# scripts/validate-spec-source-parity.sh — DP-228 T5
#
# Framework PR gate validator that enforces DP / company-Epic source parity:
#
#   1. Producer registry parity (AC2, AC-NF1):
#      For every path_glob entry in `scripts/lib/evidence-producers.json` that
#      targets the design-plans/DP-* spec namespace, there must be a matching
#      companies/*/*/{KEY} glob entry on the same producer, and vice versa.
#      Inherent asymmetry must be declared in
#      `scripts/lib/spec-source-parity-allowlist.txt` under [registry];
#      otherwise the gate exits 2.
#
#   2. Auto-pass DP-only routing prose scan (AC-NF4):
#      Scan auto-pass owning surface — the skill SKILL.md, helper scripts,
#      shared references, and the framework routing rule — for new DP-only
#      routing prose (patterns that gate execution on source type "DP-backed
#      source" while remaining surfaces have already been migrated to
#      source-neutral wording). Surfaces still mid-migration are baselined in
#      the allowlist under [auto-pass-prose]; new DP-only routing prose on
#      surfaces NOT in the allowlist is fail-stop.
#
# Exit codes:
#   0  PASS
#   2  Parity / DP-only drift detected
#   3  Usage / IO error
#
# Inputs (env, all optional):
#   POLARIS_PRODUCER_REGISTRY     default scripts/lib/evidence-producers.json
#   POLARIS_PARITY_ALLOWLIST      default scripts/lib/spec-source-parity-allowlist.txt
#   POLARIS_AUTO_PASS_SURFACES    newline-separated override for the auto-pass
#                                 surface file list (used by the selftest to
#                                 redirect the scan into a fixture).
#
# Usage:
#   bash scripts/validate-spec-source-parity.sh

set -euo pipefail

PREFIX="[spec-source-parity]"

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/validate-spec-source-parity.sh

Validates DP / company-Epic source parity in scripts/lib/evidence-producers.json
and scans the auto-pass surface for DP-only routing drift.

Exit:  0 = PASS, 2 = parity / drift detected, 3 = usage / IO error.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REGISTRY="${POLARIS_PRODUCER_REGISTRY:-scripts/lib/evidence-producers.json}"
ALLOWLIST="${POLARIS_PARITY_ALLOWLIST:-scripts/lib/spec-source-parity-allowlist.txt}"

[[ -f "$REGISTRY" ]] || { echo "$PREFIX registry not found: $REGISTRY" >&2; exit 3; }
[[ -f "$ALLOWLIST" ]] || { echo "$PREFIX allowlist not found: $ALLOWLIST" >&2; exit 3; }

# Default auto-pass surface list — overrideable via POLARIS_AUTO_PASS_SURFACES
# (newline-separated). Selftest fixtures point this at a temp directory.
if [[ -n "${POLARIS_AUTO_PASS_SURFACES:-}" ]]; then
  AUTO_PASS_SURFACES="$POLARIS_AUTO_PASS_SURFACES"
else
  AUTO_PASS_SURFACES="$(cat <<'EOF'
.claude/skills/auto-pass/SKILL.md
scripts/auto-pass-probe.sh
scripts/auto-pass-increment-counter.sh
.claude/skills/references/auto-pass-ledger.md
.claude/skills/references/auto-pass-execution-flow.md
.claude/rules/skill-routing.md
EOF
)"
fi

export POLARIS_REGISTRY_INPUT="$REGISTRY"
export POLARIS_ALLOWLIST_INPUT="$ALLOWLIST"
export POLARIS_AUTO_PASS_SURFACES_INPUT="$AUTO_PASS_SURFACES"
export POLARIS_PREFIX="$PREFIX"

python3 - <<'PY'
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

PREFIX = os.environ["POLARIS_PREFIX"]
registry_path = Path(os.environ["POLARIS_REGISTRY_INPUT"])
allowlist_path = Path(os.environ["POLARIS_ALLOWLIST_INPUT"])
surfaces_raw = os.environ.get("POLARIS_AUTO_PASS_SURFACES_INPUT", "")

errors: list[str] = []


# ---------------------------------------------------------------------------
# Allowlist parsing
# ---------------------------------------------------------------------------

def parse_allowlist(path: Path) -> tuple[set[str], set[str]]:
    """Return (registry_allowlist, auto_pass_prose_allowlist).

    registry_allowlist: set of path_glob strings declared as inherently asymmetric.
    auto_pass_prose_allowlist: set of file paths (relative to cwd) whose
        DP-only routing prose is baselined as transitional.
    """
    registry: set[str] = set()
    prose: set[str] = set()
    section: str | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        if section == "registry":
            registry.add(line)
        elif section == "auto-pass-prose":
            # entry: <relative-path>:<token>:<reason>
            head = line.split(":", 1)[0].strip()
            if head:
                prose.add(head)
    return registry, prose


registry_allowlist, prose_allowlist = parse_allowlist(allowlist_path)


# ---------------------------------------------------------------------------
# Part 1 — Producer registry parity
# ---------------------------------------------------------------------------

try:
    registry_data = json.loads(registry_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as exc:
    print(f"{PREFIX} registry parse failed: {exc}", file=sys.stderr)
    sys.exit(3)

DP_PREFIX = "docs-manager/src/content/docs/specs/design-plans/DP-"
DP_ARCHIVE_PREFIX = "docs-manager/src/content/docs/specs/design-plans/archive/DP-"
COMPANIES_PREFIX = "docs-manager/src/content/docs/specs/companies/"

# Patterns that identify a glob as a DP-spec-namespace or company-spec-namespace
# entry. Globs that don't touch either namespace (e.g. .polaris/evidence/**)
# are out of scope for source parity.
DP_GLOB_RE = re.compile(r"^docs-manager/src/content/docs/specs/design-plans/(?:archive/)?DP-")
COMPANY_GLOB_RE = re.compile(
    r"^docs-manager/src/content/docs/specs/companies/[^/]+/(?:archive/)?[^/]+/"
)


def dp_to_company_template(glob: str) -> str:
    """Project a DP-* path glob onto its expected companies/* counterpart shape.

    e.g. design-plans/DP-*/refinement.md
         -> companies/*/*/refinement.md
    e.g. design-plans/archive/DP-*/tasks/**/T*.md
         -> companies/*/archive/*/tasks/**/T*.md
    """
    if glob.startswith(DP_ARCHIVE_PREFIX[:-3]):
        tail = glob[len("docs-manager/src/content/docs/specs/design-plans/archive/DP-") :]
        # tail still starts with the wildcard portion (e.g. */tasks/**)
        tail = tail.split("/", 1)
        # drop the DP folder fragment ("*" after DP-) and keep remaining path
        remainder = tail[1] if len(tail) > 1 else ""
        return f"docs-manager/src/content/docs/specs/companies/*/archive/*/{remainder}"
    if glob.startswith("docs-manager/src/content/docs/specs/design-plans/DP-"):
        tail = glob[len("docs-manager/src/content/docs/specs/design-plans/DP-") :]
        # tail is e.g. "*/refinement.md" or "*/tasks/T*/index.md"
        tail_parts = tail.split("/", 1)
        remainder = tail_parts[1] if len(tail_parts) > 1 else ""
        return f"docs-manager/src/content/docs/specs/companies/*/*/{remainder}"
    return glob


def company_to_dp_template(glob: str) -> str:
    """Inverse projection: companies/*/*/x -> design-plans/DP-*/x (and archive)."""
    archive_marker = "docs-manager/src/content/docs/specs/companies/"
    if glob.startswith(archive_marker):
        tail = glob[len(archive_marker) :]
        parts = tail.split("/")
        # forms:
        #   {company}/archive/{key}/...  -> design-plans/archive/DP-*/...
        #   {company}/{key}/...          -> design-plans/DP-*/...
        if len(parts) >= 3 and parts[1] == "archive":
            remainder = "/".join(parts[3:])
            return f"docs-manager/src/content/docs/specs/design-plans/archive/DP-*/{remainder}"
        if len(parts) >= 2:
            remainder = "/".join(parts[2:])
            return f"docs-manager/src/content/docs/specs/design-plans/DP-*/{remainder}"
    return glob


for producer in registry_data.get("producers", []):
    owning = producer.get("owning_skill", "<unknown>")
    writer = producer.get("writer", "<unknown>")
    label = f"producer[owning_skill={owning}, writer={writer}]"
    globs = list(producer.get("path_globs") or [])
    dp_globs = [g for g in globs if DP_GLOB_RE.match(g)]
    company_globs = [g for g in globs if COMPANY_GLOB_RE.match(g)]

    # Skip producers that don't participate in the DP / companies namespace.
    if not dp_globs and not company_globs:
        continue

    expected_company_for_dp = {dp_to_company_template(g) for g in dp_globs}
    expected_dp_for_company = {company_to_dp_template(g) for g in company_globs}

    company_set = set(company_globs)
    dp_set = set(dp_globs)

    missing_company = sorted(expected_company_for_dp - company_set)
    missing_dp = sorted(expected_dp_for_company - dp_set)

    for miss in missing_company:
        if miss in registry_allowlist:
            continue
        # locate the DP glob that produced this expectation, for a helpful message
        sources = [g for g in dp_globs if dp_to_company_template(g) == miss]
        errors.append(
            f"{label}: DP glob {sources[0] if sources else '?'} lacks companies/ counterpart "
            f"(expected {miss}); add the missing glob or list it in [registry] allowlist"
        )
    for miss in missing_dp:
        if miss in registry_allowlist:
            continue
        sources = [g for g in company_globs if company_to_dp_template(g) == miss]
        errors.append(
            f"{label}: companies/ glob {sources[0] if sources else '?'} lacks DP-* counterpart "
            f"(expected {miss}); add the missing glob or list it in [registry] allowlist"
        )


# ---------------------------------------------------------------------------
# Part 2 — Auto-pass DP-only routing prose scan
# ---------------------------------------------------------------------------

# Patterns that flag DP-only routing intent (i.e. statements that gate
# execution on a source being DP-backed while parity should already accept
# Epic / company sources). Hits must appear on surfaces that are NOT in the
# transitional allowlist.
DP_ONLY_PATTERNS = [
    re.compile(r"只接受\s*DP-?backed\s*source"),
    re.compile(r"DP-?only\s+(?:route|routing|source)"),
    re.compile(r"only\s+DP-?backed\s+source", re.IGNORECASE),
    re.compile(r"only\s+accepts?\s+DP-?backed", re.IGNORECASE),
]

surfaces = [line.strip() for line in surfaces_raw.splitlines() if line.strip()]

for surface in surfaces:
    surface_path = Path(surface)
    if not surface_path.exists():
        # Missing surface is a fail-stop: the gate must not silently skip the scan.
        errors.append(f"auto-pass surface missing: {surface}")
        continue
    if surface in prose_allowlist:
        # The surface is documented as transitional; we still confirm the file
        # exists (above), but defer the prose-cleanup expectation to the owning
        # migration task. No further action.
        continue
    try:
        text = surface_path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"auto-pass surface read failed: {surface}: {exc}")
        continue
    for lineno, line in enumerate(text.splitlines(), start=1):
        for pat in DP_ONLY_PATTERNS:
            if pat.search(line):
                errors.append(
                    f"auto-pass DP-only routing prose at {surface}:{lineno}: "
                    f"{line.strip()!r}; surface must be source-neutral or "
                    f"listed under [auto-pass-prose] allowlist with migration task"
                )
                break


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if errors:
    print(f"{PREFIX} FAIL: spec source parity", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(2)

producer_count = len(registry_data.get("producers", []))
print(f"{PREFIX} PASS: spec source parity ({producer_count} producers scanned, "
      f"{len(surfaces)} auto-pass surfaces inspected)")
PY
