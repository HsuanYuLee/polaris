#!/usr/bin/env bash
# Purpose: DP-417 T11 — bidirectional spec↔check contract parity gate. Asserts that
#          every deterministic refinement.json producer check's hard requirement /
#          prohibition on an AUTHOR-controllable field is faithfully reflected in the
#          LLM-facing producer schema spec (refinement-artifact.md / pipeline-handoff.md).
#          Its thesis: "write the artifact per the spec" ⇒ "the deterministic checks pass
#          BY CONSTRUCTION". It fails-closed on drift in either direction:
#            - validator-hard-requires field X but the spec does not document X as
#              required          → POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED
#            - spec declares field X required but a validator FORBIDS X (or the spec
#              marks X as forbidden for a source type the validator now requires it on)
#                                → POLARIS_SPEC_CHECK_PARITY_CONTRADICTION
#          Each manifest entry is tied to a live validator via an anchor literal
#          (anchor-liveness); if the anchor is gone the manifest is stale and the check
#          is no longer trustworthy → POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE. This keeps
#          the manifest from silently diverging from the checks it mirrors.
# Inputs:  --repo-root <path>  (default: git toplevel of cwd, else this script's repo).
# Outputs: PASS line on stdout (exit 0); POLARIS_SPEC_CHECK_PARITY_* markers on stderr
#          (exit 2) on drift; exit 2 on missing inputs (fail-closed).
set -euo pipefail

REPO_ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0" >&2; exit 0 ;;
    *) echo "POLARIS_SPEC_CHECK_PARITY_USAGE: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  # git toplevel if inside a repo, else fall back to this script's parent dir.
  # NB: keep the git branch and the fallback as separate statements — a single
  # `git ... || cd ... && pwd` chain mis-parses (|| and && are left-associative
  # with equal precedence), appending pwd to a successful git result.
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || REPO_ROOT=""
  if [[ -z "$REPO_ROOT" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"

python3 - "$REPO_ROOT" <<'PY'
"""Purpose: bidirectional spec↔check contract parity checker for DP-417 T11.
Reads a fixed manifest of (author field, direction, validator+anchor, spec check_kind)
and asserts the LLM-facing producer schema stays in lockstep with the deterministic
refinement.json validators. Fail-closed on either drift direction and on stale anchors.
"""
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()

REF_ARTIFACT = repo / ".claude/skills/references/refinement-artifact.md"
PIPELINE = repo / ".claude/skills/references/pipeline-handoff.md"
V_JSON = repo / "scripts/validate-refinement-json.sh"
V_PARITY = repo / "scripts/validate-refinement-artifact-parity.sh"
V_BREAKDOWN = repo / "scripts/validate-breakdown-ready.sh"

SPEC_FILES = {"refinement-artifact": REF_ARTIFACT, "pipeline-handoff": PIPELINE}

errors = []

def read(path):
    if not path.is_file():
        errors.append(f"POLARIS_SPEC_CHECK_PARITY_USAGE: missing input file: {path}")
        return None
    return path.read_text(encoding="utf-8")

texts = {name: read(p) for name, p in SPEC_FILES.items()}
validators = {
    str(V_JSON): read(V_JSON),
    str(V_PARITY): read(V_PARITY),
    str(V_BREAKDOWN): read(V_BREAKDOWN),
}
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(2)

ref_text = texts["refinement-artifact"]

def tasks_required_region(text):
    """The `tasks[]`：每筆必填 ... 。 enumeration in refinement-artifact.md.

    Returns the substring from the 必填 bullet to the terminating '。' — the region
    that lists which tasks[] fields the producer must supply.
    """
    marker = "每筆必填"
    idx = text.find(marker)
    if idx == -1:
        return ""
    end = text.find("。", idx)
    return text[idx : (end if end != -1 else len(text))]

def jira_only_region(text):
    """The jira-only field enumeration ('下列欄位只允許 `source.type=jira`' … block).

    Returns the substring from that marker to the derived-view sentinel that follows
    the list, i.e. the region that declares which fields are jira-only (dp-forbidden).
    """
    marker = "只允許 `source.type=jira`"
    idx = text.find(marker)
    if idx == -1:
        return ""
    sentinel = "是 derived view"
    end = text.find(sentinel, idx)
    return text[idx : (end if end != -1 else len(text))]

REQ_REGION = tasks_required_region(ref_text)
JIRA_REGION = jira_only_region(ref_text)

# Manifest: each entry ties an author-controllable refinement.json field to the live
# validator that requires/forbids it (anchor-liveness) and to the spec obligation that
# must mirror it. check_kind decides the parity assertion + failure marker:
#   documented         (requires)  → token appears in >=1 candidate spec doc
#   in_required_enum   (requires)  → token appears in refinement-artifact tasks[] 必填 region
#   not_in_required_enum (forbids) → token absent from that 必填 region
#   not_in_jira_only_enum (reverse)→ token absent from the jira-only region
MANIFEST = [
    # --- validator-hard-requires → spec must document (top-level artifact fields) ---
    {"field": "changed_files", "token": "`changed_files`", "check_kind": "documented",
     "specs": ["refinement-artifact", "pipeline-handoff"],
     "validator": str(V_PARITY), "anchor": "changed_files != module_paths"},
    {"field": "predecessor_audit", "token": "`predecessor_audit`", "check_kind": "documented",
     "specs": ["refinement-artifact", "pipeline-handoff"],
     "validator": str(V_JSON), "anchor": "missing required field 'predecessor_audit'"},
    {"field": "schema_version", "token": "`schema_version`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": 'strong_error("schema_version")'},
    {"field": "version", "token": "`version`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": 'require_nonempty_string("version")'},
    {"field": "created_at", "token": "`created_at`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": 'require_nonempty_string("created_at")'},
    {"field": "acceptance_criteria", "token": "`acceptance_criteria`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": "missing required field 'acceptance_criteria'"},
    {"field": "edge_cases", "token": "`edge_cases`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": "missing required field 'edge_cases'"},
    {"field": "modules", "token": "`modules`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": "'modules' array must contain"},
    {"field": "adversarial_pass", "token": "`adversarial_pass[]`", "check_kind": "documented",
     "specs": ["refinement-artifact"],
     "validator": str(V_JSON), "anchor": 'adversarial_pass = data.get("adversarial_pass")'},
    # --- validator-hard-requires tasks[] fields → must be in the 必填 enumeration ---
    {"field": "tasks[].id", "token": "`id`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].kind", "token": "`kind`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].title", "token": "`title`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].scope", "token": "`scope`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].ac_ids", "token": "`ac_ids`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].dependencies", "token": "`dependencies`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    {"field": "tasks[].verification", "token": "`verification`", "check_kind": "in_required_enum",
     "validator": str(V_JSON), "anchor": "task_required = {"},
    # --- validator FORBIDS on tasks[] → must NOT be listed as required (DP-341) ---
    {"field": "tasks[].allowed_files", "token": "`allowed_files`", "check_kind": "not_in_required_enum",
     "validator": str(V_JSON), "anchor": "POLARIS_REFINEMENT_PACKAGING_FIELD_FORBIDDEN"},
    {"field": "tasks[].estimate_points", "token": "`estimate_points`", "check_kind": "not_in_required_enum",
     "validator": str(V_JSON), "anchor": "POLARIS_REFINEMENT_PACKAGING_FIELD_FORBIDDEN"},
    # --- reverse: validator REQUIRES for dp → spec must NOT mark it jira-only (DP-337) ---
    {"field": "source.base_branch", "token": "`source.base_branch`", "check_kind": "not_in_jira_only_enum",
     "validator": str(V_BREAKDOWN),
     "anchor": "DP-337 graduated source.base_branch to a universal field"},
]

for entry in MANIFEST:
    field = entry["field"]
    token = entry["token"]
    kind = entry["check_kind"]
    vpath = entry["validator"]
    anchor = entry["anchor"]

    # Anchor-liveness: the mirrored check must still exist in its validator.
    vtext = validators.get(vpath)
    if vtext is None or anchor not in vtext:
        errors.append(
            f"POLARIS_SPEC_CHECK_PARITY_ANCHOR_STALE: manifest entry for '{field}' "
            f"references anchor '{anchor}' no longer present in {Path(vpath).name}; "
            "the parity manifest has drifted from the live check"
        )
        continue

    if kind == "documented":
        if not any(token in (texts[s] or "") for s in entry["specs"]):
            specs = " / ".join(entry["specs"])
            errors.append(
                f"POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED: validator {Path(vpath).name} "
                f"hard-requires '{field}' but no producer spec ({specs}) documents {token}"
            )
    elif kind == "in_required_enum":
        if token not in REQ_REGION:
            errors.append(
                f"POLARIS_SPEC_CHECK_PARITY_UNDOCUMENTED: validator {Path(vpath).name} "
                f"hard-requires tasks[] field '{field}' but {token} is missing from the "
                "refinement-artifact.md tasks[] 必填 enumeration"
            )
    elif kind == "not_in_required_enum":
        if token in REQ_REGION:
            errors.append(
                f"POLARIS_SPEC_CHECK_PARITY_CONTRADICTION: validator {Path(vpath).name} "
                f"FORBIDS tasks[] field '{field}' (packaging field) but the "
                f"refinement-artifact.md tasks[] 必填 enumeration declares {token} required"
            )
    elif kind == "not_in_jira_only_enum":
        # A jira-only DECLARATION is a leading field bullet ("- `source.base_branch`：…"),
        # not an inline fallback reference elsewhere in the block. Match the defining
        # bullet only so a legitimate "fallback `source.base_branch`" mention on another
        # field's bullet does not trigger a false contradiction.
        bullet_re = re.compile(r"(?m)^\s*-\s*" + re.escape(token) + r"\s*[：:]")
        if bullet_re.search(JIRA_REGION):
            errors.append(
                f"POLARIS_SPEC_CHECK_PARITY_CONTRADICTION: validator {Path(vpath).name} "
                f"requires '{field}' for dp sources (feat/<id>) but refinement-artifact.md "
                f"still declares {token} as a jira-only (dp-forbidden) field bullet"
            )
    else:  # pragma: no cover - guarded by manifest authoring
        errors.append(f"POLARIS_SPEC_CHECK_PARITY_USAGE: unknown check_kind '{kind}' for '{field}'")

if errors:
    print("FAIL: spec↔check contract parity", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(2)

print(f"PASS: spec↔check contract parity ({len(MANIFEST)} manifest entries)")
PY
