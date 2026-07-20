"""Structured validator authority extracted from scripts/validate-spec-source-parity.sh."""

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
render_pairs_raw = os.environ.get("POLARIS_RENDER_BODY_PAIRS_INPUT", "")

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
DP_GLOB_RE = re.compile(
    r"^docs-manager/src/content/docs/specs/design-plans/(?:archive/)?DP-"
)
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
        tail = glob[
            len("docs-manager/src/content/docs/specs/design-plans/archive/DP-") :
        ]
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
# Part 3 — Render-body parity proof (DP-302 AC5)
# ---------------------------------------------------------------------------
# Detect hardcoded DP-only body literals in derived task.md render output via a
# field-driven proof rather than an absolute string blacklist (EC3). Each pair
# is "dp_render_path::jira_render_path", produced from IDENTICAL refinement.json
# content under source.type dp vs jira. A `design-plans/` literal in the dp
# render is legitimate ONLY when it is container-derived — i.e. the jira render
# carries a `companies/` literal at the same structural position. A
# `design-plans/` literal that appears unchanged in the jira render is hardcoded
# (DP-only) and fails the gate.

DESIGN_PLANS_LITERAL = "docs-manager/src/content/docs/specs/design-plans/"
COMPANIES_LITERAL = "docs-manager/src/content/docs/specs/companies/"


def render_body_lines(path: Path) -> list[str]:
    """Read a render output and return its lines (best-effort, IO errors raise)."""
    return path.read_text(encoding="utf-8").splitlines()


def parse_render_pairs(raw: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for entry in raw.splitlines():
        entry = entry.strip()
        if not entry:
            continue
        if "::" not in entry:
            errors.append(
                f"render-body pair malformed (expected 'dp::jira'): {entry!r}"
            )
            continue
        dp_path, jira_path = entry.split("::", 1)
        pairs.append((dp_path.strip(), jira_path.strip()))
    return pairs


for dp_path_str, jira_path_str in parse_render_pairs(render_pairs_raw):
    dp_path = Path(dp_path_str)
    jira_path = Path(jira_path_str)
    if not dp_path.exists():
        errors.append(f"render-body dp render missing: {dp_path_str}")
        continue
    if not jira_path.exists():
        errors.append(f"render-body jira render missing: {jira_path_str}")
        continue
    try:
        dp_lines = render_body_lines(dp_path)
        jira_lines = render_body_lines(jira_path)
    except OSError as exc:
        errors.append(
            f"render-body read failed for {dp_path_str}/{jira_path_str}: {exc}"
        )
        continue

    # Field-driven proof: a `design-plans/` literal in the dp render is allowed
    # only if the jira render's same-position line replaces it with a
    # `companies/` literal (container-derived). If the dp `design-plans/` line is
    # reproduced unchanged in the jira render, the literal is hardcoded DP-only.
    for lineno, dp_line in enumerate(dp_lines, start=1):
        if DESIGN_PLANS_LITERAL not in dp_line:
            continue
        jira_line = jira_lines[lineno - 1] if lineno - 1 < len(jira_lines) else ""
        shifted = (
            COMPANIES_LITERAL in jira_line and DESIGN_PLANS_LITERAL not in jira_line
        )
        if not shifted:
            errors.append(
                f"DP-only body literal at {dp_path_str}:{lineno}: "
                f"{dp_line.strip()!r}; the jira render of identical content does "
                f"not shift it to a companies/ container path, so it is hardcoded "
                f"rather than container-derived (DP-302 AC5)"
            )


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

if errors:
    print(f"{PREFIX} FAIL: spec source parity", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(2)

producer_count = len(registry_data.get("producers", []))
render_pair_count = len(parse_render_pairs(render_pairs_raw))
print(
    f"{PREFIX} PASS: spec source parity ({producer_count} producers scanned, "
    f"{len(surfaces)} auto-pass surfaces inspected, "
    f"{render_pair_count} render-body pairs proven)"
)
