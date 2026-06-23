#!/usr/bin/env bash
# Purpose: Selftest for refinement_common.section() frontmatter-awareness (DP-345 AC3).
# Inputs:  none
# Outputs: TAP-ish lines to stdout; exit 0 on PASS, 1 on FAIL
# Side effects: none (in-memory python assertions via the lib import)
#
# Asserts refinement_common.section() strips the frontmatter block then
# line-anchors `^## `, so a frontmatter `description` literally containing
# `## Modules` / `## Risks` (DP-344-T1 collision shape) does NOT make section()
# return the frontmatter literal — the real body section is returned, so
# module / risk drift detection (refinement-intra-dp-consistency.py) stays correct.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB_DIR="$REPO_ROOT/scripts/lib"

PYTHONPATH="$LIB_DIR" python3 - <<'PY'
import sys
from refinement_common import section, md_table_rows, _strip_frontmatter

fail = 0
def check(label, got, want):
    global fail
    if got == want:
        print(f"ok {label}")
    else:
        print(f"not ok {label}: got {got!r} want {want!r}", file=sys.stderr)
        fail = 1

# DP-344-T1 collision shape: frontmatter description carries literal `## Modules`
# and `## Risks`; the body has the real sections. An indented `## Risks` inside a
# fenced code block proves line-anchoring (column-0 `## `) does not over-match.
text = (
    "---\n"
    "title: \"DP-999 refinement\"\n"
    "description: \"This DP edits the ## Modules table and the ## Risks list.\"\n"
    "---\n"
    "\n"
    "# DP-999\n"
    "\n"
    "## Modules\n"
    "\n"
    "| 檔案 | 動作 | 說明 |\n"
    "|------|------|------|\n"
    "| `scripts/real-one.py` | modify | real module one |\n"
    "| `scripts/real-two.py` | create | real module two |\n"
    "\n"
    "## Risks\n"
    "\n"
    "- **R1**: a genuine risk.\n"
    "- **R2**: another genuine risk.\n"
    "\n"
    "```text\n"
    "    ## Risks (this is inside a code block, indented — must not be a section)\n"
    "```\n"
)

# 1. _strip_frontmatter removes the leading block.
stripped = _strip_frontmatter(text)
check("strip_frontmatter_removes_description_literal",
      "description:" not in stripped, True)

# 2. section("Modules") returns the REAL body table (2 module rows), not the
#    frontmatter description literal.
modules_body = section(text, "Modules")
rows = [r for r in md_table_rows(modules_body)]
module_paths = {r[0].strip("`") for r in rows if len(r) >= 2}
check("modules_real_section_2_rows", len(rows), 2)
check("modules_paths_real", module_paths, {"scripts/real-one.py", "scripts/real-two.py"})
# The frontmatter literal text must NOT leak into the parsed section.
check("modules_no_frontmatter_leak", "This DP edits" in modules_body, False)

# 3. section("Risks") returns exactly the 2 real risk bullets; the indented
#    code-block `## Risks` must NOT start a new section (column-0 anchoring).
import re
risks_body = section(text, "Risks")
risk_count = len(re.findall(r"^\s*-\s*\*\*R", risks_body, re.M))
check("risks_real_section_2_bullets", risk_count, 2)
check("risks_no_frontmatter_leak", "This DP edits" in risks_body, False)

# 4. Absent heading → empty string.
check("absent_heading_empty", section(text, "Nonexistent"), "")

# 5. No-frontmatter text still parses normally (back-compat). Header row `檔案`
#    is stripped by md_table_rows, so a single data row yields 1 row.
plain = "# DP\n\n## Modules\n\n| 檔案 | 動作 |\n|---|---|\n| `x.py` | modify |\n"
plain_rows = md_table_rows(section(plain, "Modules"))
check("no_frontmatter_back_compat", len(plain_rows), 1)

sys.exit(1 if fail else 0)
PY
rc=$?
echo "---"
if [[ "$rc" == "0" ]]; then
  echo "[selftest] PASS"
else
  echo "[selftest] FAIL"
fi
exit "$rc"
