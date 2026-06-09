#!/usr/bin/env bash
# Purpose: DP-298 T1 regression lint — fail any business gate that reads the
#          DERIVED `refinement.md` body to drive a business decision. The
#          authoritative source is `refinement.json`; `refinement.md` is a
#          render-only derived view (see canonical-contract-governance.md
#          § Derived Artifact Read Boundary). The only allowed gate against
#          `refinement.md` is an idempotency / parity `--check`.
# Inputs:  [--scan-dir <dir>]  scan an arbitrary directory of scripts (default:
#                              <repo>/scripts), used by the selftest fixtures.
#          [--report]          print the reader disposition inventory as JSON
#                              and exit 0 (no blocking).
#          [<repo-root>]       repo root for the default scan (default: cwd's
#                              git toplevel, falling back to the script's repo).
# Outputs: stdout PASS line on clean scan; stderr POLARIS_DERIVED_MD_BUSINESS_READ
#          per violation. Exit 0 = clean, 1 = invalid input, 2 = violation found.
set -euo pipefail

REPORT=0
SCAN_DIR=""
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) REPORT=1; shift ;;
    --scan-dir) SCAN_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,15p' "$0" >&2
      exit 0
      ;;
    --*) echo "unknown argument: $1" >&2; exit 1 ;;
    *)
      if [[ -n "$REPO_ROOT" ]]; then
        echo "unexpected extra argument: $1" >&2
        exit 1
      fi
      REPO_ROOT="$1"
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$SCAN_DIR" ]]; then
  if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -z "$REPO_ROOT" ]] && REPO_ROOT="$(dirname "$SCRIPT_DIR")"
  fi
  SCAN_DIR="$REPO_ROOT/scripts"
fi

if [[ ! -d "$SCAN_DIR" ]]; then
  echo "scan directory not found: $SCAN_DIR" >&2
  exit 1
fi

python3 - "$SCAN_DIR" "$REPORT" <<'PY'
"""Classify every `refinement.md` reader as a business-read (violation) or a
legitimate idempotency / parity / shape / existence / status-frontmatter reader.

The authoritative source is `refinement.json`; `refinement.md` is a derived view.
A *business-read* extracts the rendered body and uses it to drive a lifecycle /
scope / correctness decision. Legitimate readers either compare the derived view
against the json (idempotency / parity `--check`), probe existence / shape, or
read only the status frontmatter (a different axis from the rendered body).
"""

import json
import re
import sys
from pathlib import Path

scan_dir = Path(sys.argv[1])
report = sys.argv[2] == "1"

# Transitional known-violation allowlist (canonical-contract-governance.md
# § Allowed Exceptions / migration shim). Each entry MUST carry an owning task
# that removes the body-read path; the allowlist entry is removed in the same
# task. Anything here is a documented exception, NOT a steady-state legitimate
# reader.
#   validate-refinement-locked-scope.sh: owner DP-298-T2 — T2 removes the
#     `refinement.md` `## Scope`/heading-diff body branch and keeps only the
#     JSON LOCKED_JSON_FIELDS comparison; this entry is deleted in T2.
TRANSITIONAL = {
    "validate-refinement-locked-scope.sh": "pending-t2-removal:DP-298-T2",
}

# Allowlist: scripts that legitimately touch `refinement.md`. Keyed by basename
# so fixture copies in a sandbox classify the same way as the live scripts.
# reason ∈ {idempotency, parity, shape, existence, status-frontmatter}.
ALLOWLIST = {
    "render-refinement-md.sh": "idempotency",
    "validate-refinement-artifact-parity.sh": "parity",
    "validate-spec-primary-doc-authoring.sh": "shape",
    "spec-source-resolver.sh": "status-frontmatter",
    "check-main-chain-compliance.sh": "existence",
    "auto-pass-probe.sh": "existence",
    "auto-pass-runner.sh": "existence",
    "refinement-handoff-gate.sh": "existence",
    "skill-workflow-boundary-gate.sh": "existence",
    "validate-auto-pass-ledger.sh": "existence",
    "validate-learning-seed-contract.sh": "existence",
    "validate-spec-source-parity.sh": "shape",
    "sync-spec-sidebar-metadata.sh": "status-frontmatter",
    "mark-spec-implemented.sh": "status-frontmatter",
    "close-parent-spec-if-complete.sh": "status-frontmatter",
    "check-release-completed.sh": "status-frontmatter",
    "framework-release-closeout.sh": "status-frontmatter",
    "archive-spec.sh": "existence",
    "write-producer-owned-artifact.sh": "existence",
    "migrate-epic-frontmatter.sh": "status-frontmatter",
    "migrate-epic-refinement-handoff.sh": "status-frontmatter",
    "migrate-pm-epic-mapping.sh": "status-frontmatter",
    "migrate-specs-artifact-frontmatter.sh": "status-frontmatter",
    "derive-task-md-from-refinement-json.sh": "existence",
    "refinement_common.py": "status-frontmatter",
    "memory-hygiene-tiering.py": "existence",
}

REF_MD = "refinement.md"

# Signatures that indicate the script consumes the rendered BODY of refinement.md
# (as opposed to merely naming the path or probing existence). Evaluated against
# comment-stripped executable lines.
BODY_READ_TOKENS = (
    re.compile(r"\bshow\b"),                 # git show <ref>:.../refinement.md
    re.compile(r"\bcat\b"),                  # cat .../refinement.md
    re.compile(r"\bgrep\b"),                 # grep over refinement.md body
    re.compile(r"\bsed\b"),
    re.compile(r"\bawk\b"),
    re.compile(r"\bhead\b|\btail\b"),
    re.compile(r"read_text\(|\.read\(\)|open\("),
    re.compile(r"split_sections|## (Goal|Background|Decisions|Scope|Acceptance)"),
)
# Existence / shape probes never count as a body read on their own.
EXISTENCE_ONLY = re.compile(r"\[\[\s*-[fed]\s|\bis_file\(\)|\bexists\(\)|\.resolve\(\)")


def strip_comment(line: str) -> str:
    # Drop trailing/full-line shell or python comments (best-effort: we only need
    # to avoid classifying path mentions buried in comments as executable reads).
    in_single = in_double = False
    out = []
    for ch in line:
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            break
        out.append(ch)
    return "".join(out)


def references_refinement_md_path(line: str) -> bool:
    # The line refers to refinement.md either by literal name or via a path var
    # that resolves to it (REFINEMENT_MD / ref_md / refinement.md).
    return (
        REF_MD in line
        or "REFINEMENT_MD" in line
        or re.search(r"\bref_md\b", line) is not None
    )


def classify(path: Path):
    """Return (is_body_reader, references_md)."""
    references_md = False
    body_reader = False
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False, False

    # Track a window: a body-read token on the same line as (or close to) a
    # refinement.md path reference. We also catch the heredoc case where the
    # path is bound to a variable (rel_path / REFINEMENT_MD) and `git show` runs
    # against that variable elsewhere in the file.
    binds_md_var = False
    for raw in text.splitlines():
        line = strip_comment(raw)
        if not line.strip():
            continue
        names_md = references_refinement_md_path(line)
        if names_md:
            references_md = True
            # A var bound to the refinement.md rel path (heredoc-resolved show).
            if re.search(r"(rel_path|REFINEMENT_MD\w*|ref_md)\s*=", line) or (
                REF_MD in line and re.search(r"\w+\s*=", line)
            ):
                binds_md_var = True

        has_body_token = any(p.search(line) for p in BODY_READ_TOKENS)
        if not has_body_token:
            continue
        # An existence/shape-only line is not a body read.
        if EXISTENCE_ONLY.search(line) and not (
            re.search(r"\bshow\b|\bcat\b|\bgrep\b|split_sections", line)
        ):
            continue
        # Body-read token on a line that names refinement.md => direct body read.
        if names_md:
            body_reader = True
        # Heredoc/indirect: `git show` (or section split) against the bound md var.
        elif binds_md_var and re.search(r"\bshow\b|split_sections|rel_path", line):
            body_reader = True

    return body_reader, references_md


SELF_NAME = "lint-no-business-gate-reads-derived-md.sh"

candidates = []
for path in sorted(scan_dir.rglob("*")):
    if not path.is_file():
        continue
    if path.suffix not in {".sh", ".py"}:
        continue
    # Selftests build refinement.md fixtures and run `git show` against them as
    # test scaffolding — they are not live business gates. The lint itself names
    # the tokens it scans for. Both are excluded from the live gate scan; the
    # selftest exercises the detector against a controlled sandbox instead.
    if "/selftests/" in str(path).replace("\\", "/"):
        continue
    name = path.name
    if name == SELF_NAME:
        continue
    body_reader, references_md = classify(path)
    if not references_md:
        continue
    if name in TRANSITIONAL:
        candidates.append(
            {
                "path": str(path),
                "name": name,
                "reads_body": body_reader,
                "disposition": f"transitional:{TRANSITIONAL[name]}",
            }
        )
        continue
    reason = ALLOWLIST.get(name)
    if body_reader and reason is None:
        disposition = "business-read"
    elif reason is not None:
        disposition = reason
    else:
        # References the path but does not read the body and is not allowlisted —
        # e.g. a pure path/usage mention. Treat as legitimate (non-body) mention.
        disposition = "path-mention"
    candidates.append(
        {
            "path": str(path),
            "name": name,
            "reads_body": body_reader,
            "disposition": disposition,
        }
    )

if report:
    print(json.dumps(candidates, ensure_ascii=False, indent=2))
    sys.exit(0)

violations = [c for c in candidates if c["disposition"] == "business-read"]
if violations:
    for c in violations:
        print(
            f"POLARIS_DERIVED_MD_BUSINESS_READ:{c['path']} "
            "reads refinement.md body for a business decision; the authoritative "
            "source is refinement.json. Read refinement.json, or restrict this "
            "gate to an idempotency/parity --check.",
            file=sys.stderr,
        )
    print(
        f"lint-no-business-gate-reads-derived-md FAIL ({len(violations)} violation(s))",
        file=sys.stderr,
    )
    sys.exit(2)

legit = len(candidates)
print(
    f"lint-no-business-gate-reads-derived-md PASS "
    f"({legit} refinement.md reader(s); 0 business-read of derived body)"
)
PY
