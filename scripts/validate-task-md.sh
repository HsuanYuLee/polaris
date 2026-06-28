#!/usr/bin/env bash
# validate-task-md.sh — full enforcer for task.md schema (T{n}.md + V{n}.md, dual-path).
#
# Usage:
#   validate-task-md.sh <path/to/task.md>
#   validate-task-md.sh --scan <workspace_root>
#
# Exit:  0 = schema pass (single) / scan complete (scan mode, always 0)
#        1 = schema violations (single mode; details printed to stderr)
#        2 = hard fail — completion invariant violated (status: IMPLEMENTED in tasks/)
#            OR usage error / file not found
#
# Schema source:  skills/references/task-md-schema.md (DP-033 Phase A + Phase B, single source of truth)
# Called by:      skills/breakdown/SKILL.md Step 14.5 (after Write)
#                 .claude/hooks/pipeline-artifact-gate.sh (PreToolUse hook)
#
# Mode dispatch (DP-033 Phase B):
#   filename T*.md → T mode (Implementation Schema, § 3)
#   filename V*.md → V mode (Verification Schema, § 4)
#   filename 由 entry 偵測；mode 為 唯一 type 訊號（DP-033 D2，frontmatter 無 type 欄位）
#   T/V 共用：Title regex / Header / status invariant / Test Environment / jira_transition_log /
#             pr-release-skip / move-first / depends_on schema (cross-file, validate-task-md-deps.sh)
#   T-only:   ## 改動範圍 / ## Allowed Files / ## Test Command / ## Verify Command /
#             Operational Context Test sub-tasks/AC 驗收單/Task branch cells /
#             DP-028 Depends on ⇒ task/ Base branch cross-field /
#             deliverable / extension_deliverable lifecycle
#   V-only:   ## 驗收項目 / ## 驗收步驟 / Operational Context Implementation tasks cell /
#             ac_verification + ac_verification_log lifecycle (§ 4.7 對稱 D7)
#
# DP history:
#   DP-023 — runtime contract fields (Level / Runtime verify target / Env bootstrap)
#   DP-025 — non-runtime required sections (Operational Context JIRA keys, 改動範圍 / 估點理由 non-empty)
#   DP-028 — cross-field rule: Depends on (non-empty) ⇒ Base branch must be task/...
#   DP-032 — lifecycle write-back: deliverable / jira_transition_log
#   DP-033 — Phase A enforcer (D5/D6/D7 T mode); Phase B V mode dual-path + ac_verification
#   DP-048 — local_extension release metadata lifecycle

set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $0 <path/to/task.md>
       $0 --snapshot <baseline-snapshot.json> <path/to/task.md>
       $0 --scan <workspace_root>
EOF
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

compare_planner_snapshot() {
  local snapshot="$1"
  local file="$2"

  if [[ ! -f "$snapshot" ]]; then
    echo "planner-owned baseline snapshot not found: $snapshot" >&2
    return 1
  fi
  if [[ ! -f "$file" ]]; then
    echo "task.md not found: $file" >&2
    return 2
  fi

  python3 - "$snapshot" "$file" <<'PY'
import hashlib
import json
import re
import sys
from pathlib import Path

snapshot_path = Path(sys.argv[1])
task_path = Path(sys.argv[2])

def digest(value):
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()

def _strip_frontmatter(text):
    # DP-345 D1: drop the leading `---`...`---` YAML frontmatter block before
    # section parsing so a frontmatter `description` containing a literal
    # `## heading` (DP-344-T1 shape) cannot be mistaken for a real body section.
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "".join(lines[i + 1:])
    return text

def section(text, heading):
    # Frontmatter-aware, line-anchored: strip frontmatter, then match a `## `
    # heading only at the start of a line (same idiom as parse-task-md.sh).
    body = _strip_frontmatter(text)
    marker = f"## {heading}"
    lines = body.splitlines()
    start = None
    for idx, ln in enumerate(lines):
        if ln.rstrip() == marker or ln.startswith(marker + " "):
            start = idx + 1
            break
    if start is None:
        return ""
    end = len(lines)
    for idx in range(start, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return "\n".join(lines[start:end])

def first_fence(block):
    match = re.search(r"```[^\n]*\n(.*?)\n```", block, re.S)
    return match.group(1).strip() if match else ""

def table_value(text, field):
    for raw in text.splitlines():
        if not raw.lstrip().startswith("|"):
            continue
        cells = [c.strip() for c in raw.split("|")]
        if len(cells) >= 4 and cells[1] == field:
            return cells[2]
    return ""

def frontmatter_depends_on(text):
    if not text.startswith("---\n"):
        return []
    end = text.find("\n---\n", 4)
    if end == -1:
        return []
    fm = text[4:end]
    for raw in fm.splitlines():
        if raw.startswith("depends_on:"):
            value = raw.split(":", 1)[1].strip()
            if value in ("", "[]"):
                return []
            if value.startswith("[") and value.endswith("]"):
                return [item.strip().strip("'\"") for item in value[1:-1].split(",") if item.strip()]
            return [value.strip("'\"")]
    return []

def allowed_files(text):
    values = []
    for raw in section(text, "Allowed Files").splitlines():
        stripped = raw.strip()
        if stripped.startswith("- "):
            values.append(stripped[2:].strip())
    return values

try:
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid baseline snapshot JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

text = task_path.read_text(encoding="utf-8")
current = {
    "verify_command": first_fence(section(text, "Verify Command")),
    "depends_on": frontmatter_depends_on(text),
    "base_branch": table_value(text, "Base branch"),
    "allowed_files": allowed_files(text),
}
current_hashes = {
    "verify_command_sha256": digest(current["verify_command"]),
    "depends_on_sha256": digest(current["depends_on"]),
    "base_branch_sha256": digest(current["base_branch"]),
    "allowed_files_sha256": digest(current["allowed_files"]),
}
expected = snapshot.get("hashes") or {}
labels = {
    "verify_command_sha256": "Verify Command",
    "depends_on_sha256": "depends_on",
    "base_branch_sha256": "Base branch",
    "allowed_files_sha256": "Allowed Files",
}
errors = []
for key, label in labels.items():
    if expected.get(key) != current_hashes.get(key):
        errors.append(f"{label} changed from planner-owned baseline")

if errors:
    print("planner-owned baseline mismatch:", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    print(f"snapshot: {snapshot_path}", file=sys.stderr)
    print(f"task.md: {task_path}", file=sys.stderr)
    raise SystemExit(1)

print(f"validate-task-md snapshot PASS: {task_path}")
PY
}

if [[ "${1:-}" == "--snapshot" ]]; then
  [[ $# -eq 3 ]] || usage
  compare_planner_snapshot "$2" "$3"
  exit $?
fi

# ---------------------------------------------------------------------------
# Helper: extract all content lines under a markdown section heading.
# Stops at the next ## heading.
# ---------------------------------------------------------------------------
extract_markdown_section() {
  local file="$1"
  local heading="$2"
  awk -v heading="$heading" '
    $0 == heading { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract the first fenced code block from stdin.
# ---------------------------------------------------------------------------
extract_first_fenced_code_block() {
  awk '
    /^```/ {
      if (in_block == 0) { in_block=1; next }
      exit
    }
    in_block { print }
  '
}

# ---------------------------------------------------------------------------
# Helper: decide whether a task is a genuine docs-manager *content-page*
# deliverable, for which the Runtime verify target / Verify Command URL must use
# a /docs-manager/ path (DP-023 Target-first rule for docs viewer pages).
#
# This is a precise classifier — NOT a file-wide `grep docs-manager`. A docs-manager
# specs-container path that merely appears in "References to load"
# (e.g. docs-manager/src/content/docs/specs/.../refinement.md) is a
# References-only artifact and does NOT make the task a page deliverable.
#
# A task counts as a docs-manager page deliverable when EITHER signal holds:
#   (a) Runtime verify target host = local docs viewer (127.0.0.1:8080 /
#       localhost:8080); or
#   (b) the ## Allowed Files section lists a docs-manager content page —
#       a path under docs-manager/src/content/docs/** that is NOT a specs
#       container artifact (docs-manager/src/content/docs/specs/** is excluded).
#
# Args: $1 = task.md file path, $2 = normalized Runtime verify target URL.
# Returns: 0 (true) if it is a docs-manager page deliverable, 1 (false) otherwise.
# ---------------------------------------------------------------------------
is_docs_manager_page_deliverable() {
  local file="$1"
  local normalized_target="$2"

  # Signal (a): Runtime verify target host = local docs viewer (port 8080).
  local target_host_port
  target_host_port=$(python3 -c "
from urllib.parse import urlparse
import sys
u = urlparse(sys.argv[1])
host = (u.hostname or '').lower()
port = u.port
print(f'{host}:{port}')
" "$normalized_target" 2>/dev/null || true)
  if [[ "$target_host_port" == "127.0.0.1:8080" || "$target_host_port" == "localhost:8080" ]]; then
    return 0
  fi

  # Signal (b): ## Allowed Files lists a docs-manager content page that is NOT a
  # specs container artifact.
  local allowed_files_body
  allowed_files_body=$(extract_markdown_section "$file" "## Allowed Files")
  if printf '%s\n' "$allowed_files_body" \
    | grep -oE 'docs-manager/src/content/docs/[^[:space:]`<>)]+' \
    | grep -qvE '^docs-manager/src/content/docs/specs/'; then
    return 0
  fi

  return 1
}

verify_command_static_smoke() {
  local file="$1"
  local command="$2"
  # DP-369 GapA: optional kind selector. Default "verify_command" preserves the
  # existing Verify Command smoke behavior unchanged; "env_bootstrap" additionally
  # runs a first-token command-shape executability check on the Env bootstrap
  # command so prose env_bootstrap fails LOCK/breakdown (run-verify-command.sh
  # later runs `bash -c` on it at engineering RUN). Single classifier — same
  # primitive, reusing this function's command_lines/shlex tokenizer (AC-NEG3).
  local kind="${3:-verify_command}"

  python3 - "$file" "$command" "$kind" <<'PY'
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlparse

task_path = Path(sys.argv[1])
command = sys.argv[2]
kind = sys.argv[3] if len(sys.argv) > 3 else "verify_command"
repo_root = Path.cwd()
errors = []

# DP-226 T3: build create_set = intersection of (## 改動範圍 action=create paths,
# ## Allowed Files bullet paths). Scripts referenced in the create_set are
# allowed to be missing at validation time (forward reference, since the
# script will be created by the same task that references it). Outside the
# create_set, missing-script remains a fail-loud error.
def _read_task_text() -> str:
    try:
        return task_path.read_text(encoding="utf-8")
    except Exception:
        return ""

def _strip_frontmatter(text: str) -> str:
    # DP-345 D1: drop the leading `---`...`---` YAML frontmatter block before
    # section parsing so a frontmatter `description` containing a literal
    # `## heading` (DP-344-T1 shape) cannot be mistaken for a real body section.
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "".join(lines[i + 1:])
    return text

def _section_text(text: str, heading: str) -> str:
    # Frontmatter-aware, line-anchored (same idiom as parse-task-md.sh).
    body = _strip_frontmatter(text)
    marker = f"## {heading}"
    lines = body.splitlines()
    start = None
    for idx, ln in enumerate(lines):
        if ln.rstrip() == marker or ln.startswith(marker + " "):
            start = idx + 1
            break
    if start is None:
        return ""
    end = len(lines)
    for idx in range(start, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return "\n".join(lines[start:end])

def _parse_change_scope_create_paths(text: str) -> set[str]:
    """Parse `## 改動範圍` markdown table rows whose action column equals
    'create'. Returns the path tokens (col 1) for those rows. Heuristic:
    the action column is identified by header name (`動作` or `action`,
    case/whitespace tolerant); fall back to column index 2 (zero-based 1)
    when the header parse fails."""
    body = _section_text(text, "改動範圍")
    if not body:
        return set()
    lines = [ln for ln in body.splitlines() if ln.strip().startswith("|")]
    if not lines:
        return set()
    # First row is header; second row is `|---|---|...` separator.
    header_cells = [c.strip() for c in lines[0].strip().strip("|").split("|")]
    action_idx = None
    for idx, name in enumerate(header_cells):
        n = name.lower()
        if n in {"action", "動作"}:
            action_idx = idx
            break
    if action_idx is None:
        # Conventional schema (refinement-artifact.md): | 檔案 | 動作 | 說明 |
        if len(header_cells) >= 2:
            action_idx = 1
    create_paths: set[str] = set()
    for row in lines[2:]:  # skip header + separator
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        if len(cells) <= action_idx:
            continue
        action = cells[action_idx].strip().lower()
        if action != "create":
            continue
        path_cell = cells[0]
        # Path cell often wraps the path in backticks; strip them.
        m = re.search(r"`([^`]+)`", path_cell)
        if m:
            create_paths.add(m.group(1).strip())
        else:
            create_paths.add(path_cell.strip())
    return create_paths

def _parse_allowed_files(text: str) -> set[str]:
    body = _section_text(text, "Allowed Files")
    if not body:
        return set()
    paths: set[str] = set()
    for raw in body.splitlines():
        stripped = raw.strip()
        if not stripped.startswith("- "):
            continue
        item = stripped[2:].strip()
        # Strip wrapping backticks if present.
        m = re.match(r"^`([^`]+)`", item)
        if m:
            paths.add(m.group(1).strip())
        else:
            # Drop trailing inline annotations after a space.
            paths.add(item.split()[0].strip())
    return paths

_task_text = _read_task_text()
_create_paths = _parse_change_scope_create_paths(_task_text)
_allowed_paths = _parse_allowed_files(_task_text)
CREATE_SET: set[str] = _create_paths & _allowed_paths

def script_supported_flags(script: Path):
    if not script.is_file():
        return None
    try:
        proc = subprocess.run(
            ["bash", str(script), "--help"],
            cwd=repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
    except Exception:
        return None
    if proc.returncode not in (0, 2):
        return None
    help_text = f"{proc.stdout}\n{proc.stderr}"
    flags = set(re.findall(r"(?<!\w)--[A-Za-z][A-Za-z0-9_-]*", help_text))
    return flags or None

def smoke_script_flags(line: str, tokens: list[str]):
    script_idx = None
    for idx, token in enumerate(tokens):
        if token.startswith("scripts/") and token.endswith(".sh"):
            script_idx = idx
            break
    if script_idx is None:
        return
    script = repo_root / tokens[script_idx]
    if not script.is_file():
        # DP-226 T3: skip missing-script error when the referenced script is
        # listed in the create_set (intersection of ## 改動範圍 action=create
        # AND ## Allowed Files). Outside create_set, fail loud.
        if tokens[script_idx] in CREATE_SET:
            return
        errors.append(f"Verify Command references missing repo-local script: {tokens[script_idx]} (line: {line})")
        return
    supported = script_supported_flags(script)
    if supported is None:
        return
    used = []
    for token in tokens[script_idx + 1:]:
        if token == "--":
            break
        if token.startswith("--"):
            used.append(token.split("=", 1)[0])
    for flag in used:
        if flag not in supported:
            errors.append(
                f"Verify Command uses unsupported flag {flag} for {tokens[script_idx]} (line: {line})"
            )

def smoke_rg_pattern(line: str, tokens: list[str]):
    if not tokens or tokens[0] != "rg":
        return
    pattern = None
    skip_next = False
    option_args = {
        "-e", "--regexp", "-g", "--glob", "-t", "--type", "-T", "--type-not",
        "-A", "--after-context", "-B", "--before-context", "-C", "--context",
        "-m", "--max-count", "--max-depth", "--max-filesize",
    }
    for idx, token in enumerate(tokens[1:], start=1):
        if skip_next:
            skip_next = False
            continue
        if token == "--":
            if idx + 1 < len(tokens):
                pattern = tokens[idx + 1]
            break
        if token in option_args:
            if token in {"-e", "--regexp"} and idx + 1 < len(tokens):
                pattern = tokens[idx + 1]
                break
            skip_next = True
            continue
        if token.startswith("-"):
            continue
        pattern = token
        break
    if not pattern:
        return
    with tempfile.NamedTemporaryFile("w", delete=False) as handle:
        tmp = handle.name
    try:
        proc = subprocess.run(
            ["rg", "-q", "--regexp", pattern, tmp],
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5,
        )
    except FileNotFoundError:
        return
    except Exception as exc:
        errors.append(f"Verify Command rg smoke failed unexpectedly (line: {line}): {exc}")
        return
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    if proc.returncode == 2:
        detail = proc.stderr.strip().splitlines()[0] if proc.stderr.strip() else "regex parse error"
        errors.append(f"Verify Command rg pattern parse failed: {pattern!r} (line: {line}) — {detail}")

def command_lines(script: str):
    for raw in script.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith(("if ", "for ", "while ", "then", "fi", "do", "done", "else", "elif ")):
            continue
        yield line

for line in command_lines(command):
    try:
        tokens = shlex.split(line, comments=False, posix=True)
    except ValueError:
        continue
    if not tokens:
        continue
    if tokens[0] in {"env", "timeout", "command"} and len(tokens) > 1:
        tokens = tokens[1:]
    if tokens and tokens[0] == "bash" and len(tokens) > 1:
        smoke_script_flags(line, tokens)
    elif tokens and tokens[0].startswith("scripts/") and tokens[0].endswith(".sh"):
        smoke_script_flags(line, tokens)
    smoke_rg_pattern(line, tokens)

# DP-369 GapA: env_bootstrap executability — first-token command-shape check.
# Reuses this primitive's command_lines/shlex tokenizer (no second parser).
# Goal: prose env_bootstrap (e.g. "啟動 dev.kkday.com 三層 stack ...") fails LOCK,
# while a legitimate pipe-free shell chain that merely references host binaries
# absent from the gate host (colima / docker-compose / pnpm) still passes — the
# check validates command-name SHAPE, never binary existence.

# A shell statement separator splits a chain into individual commands; the first
# word of each is the command name and must be command-shaped.
_STATEMENT_SEPARATORS = (";", "&&", "||", "|", "&")
# A command word is a binary name or path: ASCII alnum plus ._-/:+@ punctuation.
# CJK / prose words do not match, so a prose env_bootstrap value is rejected.
_COMMAND_NAME_RE = re.compile(r"^[A-Za-z0-9_./:+@-]+$")
# A leading `VAR=value` env-assignment prefix is not the command word; skip it.
_ENV_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def _split_statements(line: str):
    """Split one bootstrap line into statements on top-level shell separators.

    Args:
        line: a single non-comment command line.

    Returns:
        List of non-empty statement strings (each the text between separators).
    """
    statements = []
    buf = []
    i = 0
    n = len(line)
    while i < n:
        matched = None
        for sep in _STATEMENT_SEPARATORS:
            if line.startswith(sep, i):
                matched = sep
                break
        if matched:
            statements.append("".join(buf))
            buf = []
            i += len(matched)
            continue
        buf.append(line[i])
        i += 1
    statements.append("".join(buf))
    return [s for s in (st.strip() for st in statements) if s]


def _first_command_word(statement: str):
    """Return the first command word of a statement.

    Skips leading subshell/grouping/negation punctuation and `VAR=value`
    env-assignment prefixes so the actual command name is returned.

    Args:
        statement: a single shell statement (no top-level separators).

    Returns:
        The command-name token, or "" when none can be extracted.
    """
    try:
        toks = shlex.split(statement, comments=False, posix=True)
    except ValueError:
        return ""
    for tok in toks:
        if tok in {"(", ")", "{", "}", "!"}:
            continue
        if _ENV_ASSIGN_RE.match(tok) and "/" not in tok.split("=", 1)[0]:
            continue
        return tok
    return ""


def env_bootstrap_shape_smoke():
    """Append an error for any bootstrap statement whose first token is not a
    runnable command name. Catches prose env_bootstrap while tolerating absent
    host binaries, since only command-name shape (not existence) is checked."""
    for line in command_lines(command):
        for statement in _split_statements(line):
            word = _first_command_word(statement)
            if not word:
                errors.append(
                    "Env bootstrap command executability: cannot resolve a "
                    f"command from statement (statement: {statement!r})"
                )
                continue
            if not _COMMAND_NAME_RE.match(word):
                errors.append(
                    "Env bootstrap command executability: first token "
                    f"{word!r} is not a runnable command (prose, not a shell "
                    f"command; statement: {statement!r})"
                )


if kind == "env_bootstrap":
    env_bootstrap_shape_smoke()

for error in errors:
    print(error)

raise SystemExit(1 if errors else 0)
PY
}

validate_required_tools_section() {
  local file="$1"
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

def _strip_frontmatter(text):
    # DP-345 D1: drop the leading `---`...`---` YAML frontmatter block before
    # section parsing so a frontmatter `description` containing a literal
    # `## heading` (DP-344-T1 shape) cannot be mistaken for a real body section.
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "".join(lines[i + 1:])
    return text

def section(text, heading):
    # Frontmatter-aware, line-anchored (same idiom as parse-task-md.sh).
    body = _strip_frontmatter(text)
    marker = f"## {heading}"
    lines = body.splitlines()
    start = None
    for idx, ln in enumerate(lines):
        if ln.rstrip() == marker or ln.startswith(marker + " "):
            start = idx + 1
            break
    if start is None:
        return ""
    end = len(lines)
    for idx in range(start, len(lines)):
        if lines[idx].startswith("## "):
            end = idx
            break
    return "\n".join(lines[start:end])

def split_row(line):
    raw = line.strip()
    if not raw.startswith("|") or not raw.endswith("|"):
        return []
    return [cell.strip().strip("`") for cell in raw.strip("|").split("|")]

def norm(value):
    return re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")

body = section(text, "Required Tools")
if not body:
    raise SystemExit(0)

rows = [split_row(line) for line in body.splitlines() if split_row(line)]
data_rows = []
headers = []
for row in rows:
    if not headers:
        headers = [norm(cell) for cell in row]
        continue
    if all(re.fullmatch(r":?-{3,}:?", cell.strip()) for cell in row):
        continue
    data_rows.append(row)

errors = []
required = [
    "name",
    "owner",
    "install_authority",
    "check_command",
    "runtime_profile",
    "goes_to_mise",
    "handoff_hint",
]
optional = ["install_command"]
valid_columns = set(required + optional)
aliases = {
    "tool": "name",
    "tool_name": "name",
    "profile": "runtime_profile",
}
headers = [aliases.get(header, header) for header in headers]
missing_headers = [field for field in required if field not in headers]
if missing_headers:
    errors.append(
        "Required Tools table missing columns: " + ", ".join(missing_headers)
    )

if not data_rows:
    errors.append("Required Tools section must contain at least one tool row")

valid_owners = {"framework", "delivery", "project", "ticket", "user"}
valid_authorities = {
    "root_mise",
    "system",
    "project_package_manager",
    "workspace_dependency_consent",
    "manual_user_action",
}
valid_profiles = {"core", "runtime", "delivery", "ticket"}

for ridx, row in enumerate(data_rows, start=1):
    values = {headers[idx]: row[idx].strip() if idx < len(row) else "" for idx in range(len(headers))}
    if not set(values).intersection(valid_columns):
        continue
    for field in required:
        if not values.get(field):
            errors.append(f"Required Tools row {ridx}: missing '{field}'")
    owner = values.get("owner")
    authority = values.get("install_authority")
    profile = values.get("runtime_profile")
    goes_to_mise = values.get("goes_to_mise", "").lower()
    if owner and owner not in valid_owners:
        errors.append(f"Required Tools row {ridx}: invalid owner '{owner}'")
    if authority and authority not in valid_authorities:
        errors.append(f"Required Tools row {ridx}: invalid install_authority '{authority}'")
    if profile and profile not in valid_profiles:
        errors.append(f"Required Tools row {ridx}: invalid runtime_profile '{profile}'")
    if goes_to_mise and goes_to_mise not in {"true", "false"}:
        errors.append(f"Required Tools row {ridx}: goes_to_mise must be true or false")
    if goes_to_mise == "true" and (owner == "ticket" or profile == "ticket"):
        errors.append("Required Tools row %d: ticket-scoped tools must set goes_to_mise=false" % ridx)

for error in errors:
    print(error)
raise SystemExit(0)
PY
}

# ---------------------------------------------------------------------------
# Helper: extract the value cell of an Operational Context table row.
# task.md convention: `| {field} | {value} |`
# Returns the trimmed value; empty string if field is not present.
# ---------------------------------------------------------------------------
extract_op_ctx_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^\|/ {
      n = split($0, fields, "|")
      if (n < 4) next
      name = fields[2]; val = fields[3]
      sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
      sub(/^[[:space:]]+/, "", val);  sub(/[[:space:]]+$/, "", val)
      if (name == field) { print val; exit }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract a YAML scalar from the frontmatter block (first --- block).
# Returns the trimmed value for a top-level key: "key: value".
# Outputs nothing if key is absent or has a complex (block/list) value.
# ---------------------------------------------------------------------------
extract_frontmatter_scalar() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next   # skip indented (nested) lines
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) {
          val = $0
          sub(/^[^:]*:[[:space:]]*/, "", val)
          sub(/[[:space:]]+$/, "", val)
          print val
          exit
        }
      }
    }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: check if a top-level YAML key exists in the frontmatter block.
# Returns 0 if found, 1 if not.
# ---------------------------------------------------------------------------
frontmatter_key_exists() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 {
      if (/^[[:space:]]/) next
      n = split($0, parts, ":")
      if (n >= 2) {
        k = parts[1]
        sub(/^[[:space:]]+/, "", k); sub(/[[:space:]]+$/, "", k)
        if (k == key) { found=1; exit }
      }
    }
    END { exit (found ? 0 : 1) }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract raw frontmatter block (between first --- delimiters).
# ---------------------------------------------------------------------------
extract_frontmatter_block() {
  local file="$1"
  awk '
    /^---$/ { if (fm==0) { fm=1; next } else { exit } }
    fm==1 { print }
  ' "$file"
}

# ---------------------------------------------------------------------------
# Helper: extract frontmatter verification.visual_regression state as JSON.
# This mirrors the YAML subset supported by parse-task-md.sh without adding a
# PyYAML dependency to the validator.
# ---------------------------------------------------------------------------
extract_vr_frontmatter_state() {
  local file="$1"
  python3 - "$file" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    lines = open(path, "r", encoding="utf-8").read().splitlines()
except OSError:
    print(json.dumps({"present": False}))
    raise SystemExit(0)

def parse_scalar(value):
    value = value.strip()
    if value == "":
        return None
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part.strip()) for part in body.split(",")]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def parse_frontmatter_lines(fm_lines):
    out = {}
    i = 0
    while i < len(fm_lines):
        raw = fm_lines[i]
        if not raw.strip() or raw.lstrip().startswith("#") or raw[0].isspace() or ":" not in raw:
            i += 1
            continue
        key, _, value = raw.partition(":")
        key = key.strip()
        value = value.strip()
        if value:
            out[key] = parse_scalar(value)
            i += 1
            continue

        mapping = {}
        i += 1
        while i < len(fm_lines):
            child_raw = fm_lines[i]
            if not child_raw.strip():
                i += 1
                continue
            child_indent = len(child_raw) - len(child_raw.lstrip(" "))
            if child_indent == 0:
                break
            child_stripped = child_raw.strip()
            if child_indent != 2 or ":" not in child_stripped:
                i += 1
                continue
            child_key, _, child_value = child_stripped.partition(":")
            child_key = child_key.strip()
            child_value = child_value.strip()
            if child_value:
                mapping[child_key] = parse_scalar(child_value)
                i += 1
                continue

            nested = {}
            i += 1
            while i < len(fm_lines):
                nested_raw = fm_lines[i]
                if not nested_raw.strip():
                    i += 1
                    continue
                nested_indent = len(nested_raw) - len(nested_raw.lstrip(" "))
                if nested_indent <= 2:
                    break
                nested_stripped = nested_raw.strip()
                if nested_indent == 4 and ":" in nested_stripped:
                    nested_key, _, nested_value = nested_stripped.partition(":")
                    nested[nested_key.strip()] = parse_scalar(nested_value.strip())
                i += 1
            mapping[child_key] = nested
        out[key] = mapping
    return out

frontmatter = {}
if lines and lines[0].strip() == "---":
    end = None
    for idx in range(1, len(lines)):
        if lines[idx].strip() == "---":
            end = idx
            break
    if end is not None:
        frontmatter = parse_frontmatter_lines(lines[1:end])

verification = frontmatter.get("verification")
vr = verification.get("visual_regression") if isinstance(verification, dict) else None
result = {
    "present": vr is not None,
    "is_map": isinstance(vr, dict),
    "expected": None,
    "expected_is_string": False,
    "pages_present": False,
    "pages_is_list": False,
}
if isinstance(vr, dict):
    expected = vr.get("expected")
    pages = vr.get("pages")
    result["expected"] = expected
    result["expected_is_string"] = isinstance(expected, str)
    result["pages_present"] = "pages" in vr
    result["pages_is_list"] = isinstance(pages, list)
print(json.dumps(result, ensure_ascii=False))
PY
}

# ---------------------------------------------------------------------------
# Helper: validate frontmatter verification.behavior_contract.
# The validator intentionally uses a small YAML subset parser to avoid adding a
# PyYAML dependency. Missing behavior_contract is allowed here; producer
# readiness / migration gates decide when the field is mandatory.
# ---------------------------------------------------------------------------
validate_behavior_contract_frontmatter() {
  local file="$1"
  python3 - "$file" <<'PY'
import csv
import re
import sys
from urllib.parse import urlparse

path = sys.argv[1]
try:
    lines = open(path, "r", encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

def parse_scalar(value):
    value = value.strip()
    if value == "":
        return None
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        body = value[1:-1].strip()
        if not body:
            return []
        return [parse_scalar(part.strip()) for part in next(csv.reader([body], skipinitialspace=True))]
    if value == "true":
        return True
    if value == "false":
        return False
    return value

def extract_frontmatter(all_lines):
    if not all_lines or all_lines[0].strip() != "---":
        return []
    for idx in range(1, len(all_lines)):
        if all_lines[idx].strip() == "---":
            return all_lines[1:idx]
    return []

def extract_behavior_contract(fm_lines):
    in_verification = False
    in_behavior = False
    behavior = None
    current_list_key = None

    for raw in fm_lines:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()

        if indent == 0:
            in_behavior = False
            current_list_key = None
            if ":" not in stripped:
                in_verification = False
                continue
            key, _, value = stripped.partition(":")
            in_verification = key.strip() == "verification" and value.strip() == ""
            continue

        if not in_verification:
            continue

        if indent == 2 and ":" in stripped:
            current_list_key = None
            key, _, value = stripped.partition(":")
            if key.strip() == "behavior_contract":
                parsed = parse_scalar(value.strip())
                behavior = {} if parsed is None else parsed
                in_behavior = isinstance(behavior, dict)
            else:
                in_behavior = False
            continue

        if behavior is None or not isinstance(behavior, dict) or not in_behavior:
            continue

        if indent == 4 and ":" in stripped:
            key, _, value = stripped.partition(":")
            key = key.strip()
            value = value.strip()
            if value == "":
                behavior[key] = []
                current_list_key = key
            else:
                behavior[key] = parse_scalar(value)
                current_list_key = None
            continue

        if current_list_key and indent >= 6 and stripped.startswith("- "):
            behavior[current_list_key].append(parse_scalar(stripped[2:].strip()))

    return behavior

def is_nonempty_string(value):
    return isinstance(value, str) and value.strip() != ""

def first_runtime_verify_target(all_lines):
    for raw in all_lines:
        stripped = raw.strip()
        match = re.match(r"^(?:-\s*)?\*\*Runtime verify target\*\*:\s*(.+?)\s*$", stripped)
        if match:
            value = match.group(1).strip().strip("`").strip()
            return value
    return ""

def is_remote_live_url(value):
    if not is_nonempty_string(value):
        return False
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"}:
        return False
    host = (parsed.hostname or "").lower()
    if not host:
        return False
    if host in {"localhost", "0.0.0.0", "::1"}:
        return False
    if host.startswith("127."):
        return False
    if host.endswith(".localhost"):
        return False
    # Single-label hosts are commonly docker-compose service names for local
    # replay targets (for example "mockoon"). Dotted public hosts are remote.
    if "." not in host:
        return False
    return True

full_text = "\n".join(lines)
lower_text = full_text.lower()
lower_path = path.lower()
runtime_verify_target = first_runtime_verify_target(lines)

def is_framework_static_context():
    if "/design-plans/" in lower_path:
        return True
    return (
        "repo: polaris-framework" in lower_text
        or "framework/static work order" in lower_text
        or "polaris-framework" in lower_text
    )

def is_behavior_sensitive_migration():
    return bool(
        re.search(
            r"\b(replacement|replace|migration|migrate|refactor|remove legacy|dependency removal)\b",
            lower_text,
        )
        or re.search(r"(替換|重構|移除\s*legacy|移除.*依賴|遷移|相容性)", full_text)
    )

bc = extract_behavior_contract(extract_frontmatter(lines))
if bc is None:
    raise SystemExit(0)

errors = []
if not isinstance(bc, dict):
    errors.append("frontmatter verification.behavior_contract must be a map")
else:
    applies = bc.get("applies")
    if not isinstance(applies, bool):
        errors.append("frontmatter verification.behavior_contract.applies is required and must be true or false")
    elif not applies:
        reason = bc.get("reason")
        if not is_nonempty_string(reason):
            errors.append("frontmatter verification.behavior_contract.reason is required when applies=false")
        elif (
            is_behavior_sensitive_migration()
            and not is_framework_static_context()
            and "planner override" not in str(reason).lower()
        ):
            errors.append(
                "frontmatter verification.behavior_contract.applies=false is not allowed for product migration/replacement/removal tasks without an explicit planner override in reason"
            )
    else:
        mode = bc.get("mode")
        if mode not in {"parity", "visual_target", "pm_flow", "hybrid"}:
            errors.append("frontmatter verification.behavior_contract.mode must be parity, visual_target, pm_flow, or hybrid")

        source = bc.get("source_of_truth")
        if source not in {"existing_behavior", "figma", "pm_flow", "spec"}:
            errors.append("frontmatter verification.behavior_contract.source_of_truth must be existing_behavior, figma, pm_flow, or spec")

        fixture_policy = bc.get("fixture_policy")
        if fixture_policy not in {"mockoon_required", "live_allowed", "static_only"}:
            errors.append("frontmatter verification.behavior_contract.fixture_policy must be mockoon_required, live_allowed, or static_only")
        elif fixture_policy == "mockoon_required":
            flow_script = bc.get("flow_script") or bc.get("script_path") or bc.get("playwright_script")
            if not is_nonempty_string(flow_script):
                errors.append("frontmatter verification.behavior_contract.flow_script is required when fixture_policy=mockoon_required")
            if is_remote_live_url(runtime_verify_target):
                errors.append("frontmatter verification.behavior_contract.fixture_policy=mockoon_required cannot use a remote live Runtime verify target")

        if "baseline_ref" in bc and not is_nonempty_string(bc.get("baseline_ref")):
            errors.append("frontmatter verification.behavior_contract.baseline_ref must be a non-empty string when present")

        if "target_url" in bc and not is_nonempty_string(bc.get("target_url")):
            errors.append("frontmatter verification.behavior_contract.target_url must be a non-empty string when present")
        elif fixture_policy == "mockoon_required" and is_remote_live_url(bc.get("target_url")):
            errors.append("frontmatter verification.behavior_contract.fixture_policy=mockoon_required cannot use a remote live target_url")

        viewport = bc.get("viewport")
        if viewport is not None and viewport not in {"mobile", "desktop", "responsive"}:
            errors.append("frontmatter verification.behavior_contract.viewport must be mobile, desktop, or responsive when present")

        if not is_nonempty_string(bc.get("flow")):
            errors.append("frontmatter verification.behavior_contract.flow is required when applies=true")

        assertions = bc.get("assertions")
        if not isinstance(assertions, list) or not assertions:
            errors.append("frontmatter verification.behavior_contract.assertions must be a non-empty YAML list when applies=true")
        elif any(not is_nonempty_string(item) for item in assertions):
            errors.append("frontmatter verification.behavior_contract.assertions entries must be non-empty strings")

        allowed_differences = bc.get("allowed_differences")
        if allowed_differences is not None and not isinstance(allowed_differences, list):
            errors.append("frontmatter verification.behavior_contract.allowed_differences must be a YAML list when present")
        elif mode == "hybrid" and not allowed_differences:
            errors.append("frontmatter verification.behavior_contract.allowed_differences must be non-empty when mode=hybrid")

for error in errors:
    print(error)
PY
}

# ---------------------------------------------------------------------------
# Helper: task identity grammar.
# Product tasks use JIRA keys (PROJ-123). Framework DP-backed work orders use
# pseudo IDs (DP-047-T1 / DP-047-V1) but otherwise follow the same task.md schema.
# ---------------------------------------------------------------------------
is_valid_task_identity() {
  local value="$1"
  [[ "$value" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ || "$value" =~ ^DP-[0-9]{3}-[TV][0-9]+[a-z]*$ ]]
}

is_valid_jira_key() {
  local value="$1"
  [[ "$value" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]
}

is_na_value() {
  local value
  value=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
  [[ -z "$value" || "$value" == "n/a" || "$value" == "-" || "$value" == "none" || "$value" == "無" ]]
}

extract_header_token() {
  local file="$1"
  local label="$2"
  awk -v label="$label" '
    /^> / {
      line = $0
      n = split(line, parts, "|")
      for (i = 1; i <= n; i++) {
        part = parts[i]
        sub(/^>[[:space:]]*/, "", part)
        sub(/^[[:space:]]+/, "", part)
        sub(/[[:space:]]+$/, "", part)
        prefix = label ":[[:space:]]*"
        if (part ~ "^" prefix) {
          sub("^" prefix, "", part)
          sub(/[[:space:]]+$/, "", part)
          print part
          exit
        }
      }
    }
  ' "$file"
}

validate_task_summary_language() {
  local file="$1"
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()

def read_language_from_config(config: Path) -> str:
    if not config.is_file():
        return ""
    for line in config.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"\s*language\s*:\s*([^#]+)", line)
        if match:
            return match.group(1).strip().strip("\"'")
    return ""

language = ""
for parent in [path.parent, *path.parents]:
    language = read_language_from_config(parent / "workspace-config.yaml")
    if language:
        break

if language not in {"zh-TW", "zh-Hant", "zh"}:
    raise SystemExit(0)

summary = ""
for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
    match = re.match(r"^#\s+[TV][0-9]+[a-z]*:\s+(.+?)\s+\([0-9.]+\s*pt\)\s*$", line)
    if match:
        summary = match.group(1).strip()
        break

if not summary or re.search(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", summary):
    raise SystemExit(0)

cleaned = re.sub(r"`[^`]*`", " ", summary)
cleaned = re.sub(r"\b[A-Z][A-Z0-9]+-\d+(?:-[TV]\d+[a-z]*)?\b", " ", cleaned)
cleaned = re.sub(r"\b[A-Za-z0-9_.-]+\.(?:sh|py|js|ts|tsx|vue|json|ya?ml|md|txt)\b", " ", cleaned)
cleaned = re.sub(r"(?<!\w)--?[A-Za-z][A-Za-z0-9_-]*(?:[= ][A-Za-z0-9._/:@-]+)?", " ", cleaned)
words = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", cleaned)
alpha = sum(ch.isalpha() and ch.isascii() for ch in cleaned)

if alpha >= 12 and len(words) >= 2:
    print("task summary appears to be English prose under zh-TW policy; use zh-TW summary so downstream PR title gates fail early", file=sys.stderr)
    raise SystemExit(1)
PY
}

# ---------------------------------------------------------------------------
# Main single-file validator.
# Returns 0 (pass) / 1 (violations) / 2 (hard fail — completion invariant).
# Writes all output to stderr.
# ---------------------------------------------------------------------------
validate_file() {
  local FILE="$1"

  if [[ ! -f "$FILE" ]]; then
    echo "error: file not found: $FILE" >&2
    return 2
  fi

  # --- G: Skip rule — files under tasks/pr-release/ are never validated (DP-033 D6) ---
  case "$FILE" in
    */tasks/pr-release/*)
      return 0
      ;;
  esac

  # --- Mode detection (DP-033 Phase B): filename pattern → schema mode ---
  local _basename mode verify_section_name
  _basename=$(basename "$FILE")
  if [[ "$_basename" == "index.md" ]]; then
    _basename="$(basename "$(dirname "$FILE")").md"
  fi
  case "$_basename" in
    T[0-9]*.md)  mode="T" ;;
    V[0-9]*.md)  mode="V" ;;
    *)
      # Fallback: file is not a T*.md or V*.md → apply T mode (backward compat)
      # for legacy/unknown filenames; the dispatch hook should have routed
      # canonical V*.md / T*.md before this point.
      mode="T"
      ;;
  esac
  # Driver section that holds the executable / step block:
  #   T mode: ## Verify Command  (deterministic shell, fenced code block)
  #   V mode: ## 驗收步驟        (verify-AC LLM driver entry + per-AC step list)
  if [[ "$mode" == "V" ]]; then
    verify_section_name="## 驗收步驟"
  else
    verify_section_name="## Verify Command"
  fi

  local errors=()
  local warnings=()

  # ---------------------------------------------------------------------------
  # § 5.5 Hard invariant — completion location (exit 2, DP-033 D6)
  # If frontmatter status: IMPLEMENTED AND file is NOT in tasks/pr-release/ → HARD FAIL.
  # move-first contract: mark-spec-implemented.sh always mv before updating frontmatter,
  # so the only way to hit this is a manual edit that bypassed the helper.
  # ---------------------------------------------------------------------------
  local fm_status
  fm_status=$(extract_frontmatter_scalar "$FILE" "status" 2>/dev/null || true)
  fm_status="${fm_status%\"}"
  fm_status="${fm_status#\"}"
  fm_status="${fm_status%\'}"
  fm_status="${fm_status#\'}"
  if [[ -z "$fm_status" ]]; then
    errors+=("frontmatter status is required; use PLANNED, IN_PROGRESS, BLOCKED, IMPLEMENTED, or ABANDONED")
  else
    case "$fm_status" in
      PLANNED|IN_PROGRESS|BLOCKED|IMPLEMENTED|ABANDONED) ;;
      *) errors+=("frontmatter status must be PLANNED|IN_PROGRESS|BLOCKED|IMPLEMENTED|ABANDONED (got: '$fm_status')") ;;
    esac
  fi
  if [[ "$fm_status" == "IMPLEMENTED" ]]; then
    echo "✗✗ HARD FAIL (exit 2) — task.md completion invariant violated in $FILE:" >&2
    echo "   frontmatter 'status: IMPLEMENTED' but file is NOT in tasks/pr-release/." >&2
    echo "   Fix: run 'scripts/mark-spec-implemented.sh' (move-first: mv tasks/T.md tasks/pr-release/T.md → update frontmatter)." >&2
    echo "   Reference: skills/references/task-md-schema.md § 5.5 + DP-033 D6" >&2
    return 2
  fi

  # ---------------------------------------------------------------------------
  # OPTIONAL: frontmatter task_shape — delivery-shape enum (DP-262 T1).
  # enum: implementation | audit | confirmation; default implementation (absent).
  # Orthogonal to task_kind (T/V completion-gate dispatcher) — do not conflate.
  # If present, the value must be one of the enum members.
  # ---------------------------------------------------------------------------
  if frontmatter_key_exists "$FILE" "task_shape"; then
    local fm_task_shape
    fm_task_shape=$(extract_frontmatter_scalar "$FILE" "task_shape" 2>/dev/null || true)
    fm_task_shape="${fm_task_shape%\"}"
    fm_task_shape="${fm_task_shape#\"}"
    fm_task_shape="${fm_task_shape%\'}"
    fm_task_shape="${fm_task_shape#\'}"
    case "$fm_task_shape" in
      implementation|audit|confirmation) ;;
      *) errors+=("frontmatter task_shape must be implementation|audit|confirmation (got: '$fm_task_shape')") ;;
    esac
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Title line regex (§ 2.2)
  # ^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)
  # ---------------------------------------------------------------------------
  if ! grep -qE '^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)' "$FILE"; then
    errors+=("missing or malformed title: expected '# T{n}[suffix]: {summary} ({SP} pt)' — regex: ^# (T|V)[0-9]+[a-z]*: .+\\([0-9.]+ ?pt\\)")
  elif ! summary_language_error="$(validate_task_summary_language "$FILE" 2>&1)"; then
    errors+=("$summary_language_error")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Header metadata line — task identity + Repo (§ 2.3 / DP-050)
  # SOFT: Epic (warn only — Bug tasks may omit Epic)
  # ---------------------------------------------------------------------------
  local header_jira_token header_task_token
  header_jira_token="$(extract_header_token "$FILE" "JIRA")"
  header_task_token="$(extract_header_token "$FILE" "Task")"
  if [[ -n "$header_task_token" ]]; then
    if ! is_valid_task_identity "$header_task_token"; then
      errors+=("invalid Task identity in metadata line: got '$header_task_token' (expected JIRA key like PROJ-123 or DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi
    if [[ -n "$header_jira_token" ]] && ! is_na_value "$header_jira_token" && ! is_valid_jira_key "$header_jira_token"; then
      errors+=("invalid JIRA key in metadata line: got '$header_jira_token' (expected real JIRA key like PROJ-123 or N/A for DP-backed task)")
    fi
  else
    if [[ -z "$header_jira_token" ]]; then
      errors+=("missing task identity in metadata line: expected legacy 'JIRA: {KEY}' or canonical 'Task: {ID}'")
    elif ! is_valid_task_identity "$header_jira_token"; then
      errors+=("invalid task identity in metadata line: got '$header_jira_token' (expected JIRA key like PROJ-123 or legacy DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi
  fi
  if ! grep -qE '^> .*Repo: \S+' "$FILE"; then
    errors+=("missing Repo in metadata line: expected '> ... | Repo: {repo_name}'")
  fi
  # Soft: Epic: — warn only (Bug tasks are a real no-Epic case, per DP-033 D5)
  if ! grep -qE '^> .*Epic: \S+' "$FILE" && ! grep -qE '^> .*Source: \S+' "$FILE"; then
    warnings+=("metadata line missing 'Epic:' cell — Soft required (Bug tasks may omit; warn only)")
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Section existence (§ 3.1 / § 4.1, mode-aware)
  # ---------------------------------------------------------------------------
  local hard_sections=()
  local soft_sections=()
  if [[ "$mode" == "T" ]]; then
    hard_sections=(
      "## Operational Context"
      "## 改動範圍"
      "## Allowed Files"
      "## 估點理由"
      "## Test Command"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 測試計畫（code-level）"
    )
  else
    # V mode (DP-033 Phase B § 4.1) — symmetric to T but driver section names differ:
    #   T 改動範圍       → V 驗收項目      (語意對稱：T 列檔案改動，V 列 AC 覆蓋)
    #   T 測試計畫 code-level → V 驗收計畫（AC level）
    # T-only sections (Allowed Files / Test Command) are omitted — V doesn't write code.
    # Verify Command analog `## 驗收步驟` is checked separately below (level-conditional).
    hard_sections=(
      "## Operational Context"
      "## 驗收項目"
      "## 估點理由"
      "## Test Environment"
    )
    soft_sections=(
      "## 目標"
      "## 驗收計畫（AC level）"
    )
  fi
  local section
  for section in "${hard_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      errors+=("missing Hard required section: $section")
    fi
  done
  for section in "${soft_sections[@]}"; do
    if ! grep -qF "$section" "$FILE"; then
      warnings+=("missing Soft required section: $section (warn only — presence expected but not enforced)")
    fi
  done

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Non-empty body checks (§ 3.1)
  # 改動範圍, 估點理由 — must have at least 1 non-blank, non-comment line.
  # ---------------------------------------------------------------------------
  check_section_non_empty() {
    local heading="$1"
    local label="$2"
    if ! grep -qF "$heading" "$FILE"; then
      return  # missing section already reported above
    fi
    local body
    body=$(extract_markdown_section "$FILE" "$heading")
    local content_lines
    content_lines=$(printf '%s\n' "$body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      { count++ }
      END { print count+0 }
    ')
    if [[ "$content_lines" -eq 0 ]]; then
      errors+=("section '$heading' body is empty ($label — must have at least 1 non-comment line)")
    fi
  }

  if [[ "$mode" == "T" ]]; then
    check_section_non_empty "## 改動範圍" "Hard required"
  else
    # V mode (§ 4.3): 驗收項目 must be non-empty (≥ 1 markdown row OR bullet)
    if grep -qF "## 驗收項目" "$FILE"; then
      local v_body
      v_body=$(extract_markdown_section "$FILE" "## 驗收項目")
      local v_lines
      v_lines=$(printf '%s\n' "$v_body" | awk '
        /^[[:space:]]*$/ { next }
        /^[[:space:]]*>/ { next }
        /^[[:space:]]*\|/ { count++ }
        /^[[:space:]]*-/ { count++ }
        END { print count+0 }
      ')
      if [[ "$v_lines" -eq 0 ]]; then
        errors+=("section '## 驗收項目' has no AC entries (Hard required — must have at least one markdown row '|' or bullet '- ')")
      fi
    fi
  fi
  check_section_non_empty "## 估點理由" "Hard required"

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Allowed Files — non-empty bullet list (DP-033 D5, no grace)
  # V mode 不寫 code → 不需 Allowed Files。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Allowed Files" "$FILE"; then
    local allowed_files_body
    allowed_files_body=$(extract_markdown_section "$FILE" "## Allowed Files")
    local bullet_lines
    bullet_lines=$(printf '%s\n' "$allowed_files_body" | awk '
      /^[[:space:]]*$/ { next }
      /^[[:space:]]*>/ { next }
      /^[[:space:]]*-/ { count++ }
      END { print count+0 }
    ')
    if [[ "$bullet_lines" -eq 0 ]]; then
      errors+=("section '## Allowed Files' has no bullet list entries (Hard required — must have at least one '- ' bullet; A7 migration script can backfill)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # OPTIONAL (T mode): ## Required Tools — ticket-scoped tool handoff contract.
  # When present, validate the table shape and ensure ticket-scoped tools do
  # not get promoted into root mise.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Required Tools" "$FILE"; then
    local required_tools_errors required_tools_error
    required_tools_errors="$(validate_required_tools_section "$FILE")"
    if [[ -n "$required_tools_errors" ]]; then
      while IFS= read -r required_tools_error; do
        [[ -n "$required_tools_error" ]] && errors+=("$required_tools_error")
      done <<< "$required_tools_errors"
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Operational Context (§ 3.2)
  # Must contain ≥ 1 JIRA key pattern AND all required cells.
  # ---------------------------------------------------------------------------
  if grep -qF "## Operational Context" "$FILE"; then
    local op_ctx
    op_ctx=$(extract_markdown_section "$FILE" "## Operational Context")

    local task_identity
    task_identity="$(extract_op_ctx_field "$FILE" "Task ID")"
    if [[ -z "$task_identity" ]]; then
      task_identity="$(extract_op_ctx_field "$FILE" "Task JIRA key")"
    fi
    if [[ -z "$task_identity" ]]; then
      errors+=("Operational Context section missing task identity value (expected canonical 'Task ID' or legacy 'Task JIRA key')")
    elif ! is_valid_task_identity "$task_identity"; then
      errors+=("Operational Context task identity has invalid value '$task_identity' (expected JIRA key like PROJ-123 or DP pseudo identity like DP-047-T1 / DP-047-V1)")
    fi

    local canonical_identity=0
    if [[ -n "$(extract_op_ctx_field "$FILE" "Task ID")" \
          || -n "$(extract_op_ctx_field "$FILE" "Source type")" \
          || -n "$(extract_op_ctx_field "$FILE" "Source ID")" \
          || -n "$(extract_op_ctx_field "$FILE" "JIRA key")" ]]; then
      canonical_identity=1
    fi

    if [[ "$canonical_identity" -eq 1 ]]; then
      local source_type source_id jira_key_cell
      source_type="$(extract_op_ctx_field "$FILE" "Source type")"
      source_id="$(extract_op_ctx_field "$FILE" "Source ID")"
      jira_key_cell="$(extract_op_ctx_field "$FILE" "JIRA key")"
      case "$source_type" in
        dp|jira) ;;
        *) errors+=("Operational Context canonical identity requires Source type = dp|jira (got: '${source_type:-<empty>}')") ;;
      esac
      if [[ -z "$source_id" ]]; then
        errors+=("Operational Context canonical identity missing Source ID")
      fi
      if [[ -z "$(extract_op_ctx_field "$FILE" "Task ID")" ]]; then
        errors+=("Operational Context canonical identity missing Task ID")
      fi
      if [[ -z "$jira_key_cell" ]]; then
        errors+=("Operational Context canonical identity missing JIRA key cell (use N/A when absent)")
      elif ! is_na_value "$jira_key_cell" && ! is_valid_jira_key "$jira_key_cell"; then
        errors+=("Operational Context JIRA key must be a real JIRA key or N/A (got: '$jira_key_cell')")
      elif [[ "$source_type" == "jira" ]] && is_na_value "$jira_key_cell"; then
        errors+=("Operational Context source_type=jira requires a real JIRA key (got: '$jira_key_cell')")
      fi
    else
      if [[ -z "$(extract_op_ctx_field "$FILE" "Task JIRA key")" ]]; then
        errors+=("Operational Context legacy identity missing Task JIRA key")
      fi
      if [[ -z "$(extract_op_ctx_field "$FILE" "Parent Epic")" ]]; then
        errors+=("Operational Context legacy identity missing Parent Epic")
      fi
    fi

    # Hard required cells — mode-aware (§ 3.2 for T, § 4.2 for V)
    local required_cells=()
    if [[ "$mode" == "T" ]]; then
      required_cells=(
        "Test sub-tasks"
        "AC 驗收單"
        "Base branch"
        "Task branch"
        "References to load"
      )
    else
      # V mode (§ 4.2): drops T-only cells (Test sub-tasks / AC 驗收單 / Task branch)
      # and adds Implementation tasks (the T list this V verifies).
      required_cells=(
        "Implementation tasks"
        "Base branch"
        "References to load"
      )
    fi
    local cell
    for cell in "${required_cells[@]}"; do
      if ! grep -qF "$cell" "$FILE"; then
        errors+=("missing Hard required Operational Context cell: '$cell'")
      fi
    done

    # Soft: 'Depends on' — warn only (absent = no deps, which is valid; T/V common)
    if ! grep -qF "Depends on" "$FILE"; then
      warnings+=("Operational Context missing 'Depends on' cell (Soft — N/A is valid; warn only)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: Test Environment — Level enum + Level-specific field rules
  # § 3.3 + § 5.1
  # ---------------------------------------------------------------------------
  local level=""
  if grep -qF "## Test Environment" "$FILE"; then

    # Extract Level value
    local level_line
    level_line=$(grep -E '^\*\*Level\*\*: |^- \*\*Level\*\*: ' "$FILE" | head -n1 || true)
    if [[ -z "$level_line" ]]; then
      errors+=("Test Environment section missing 'Level' field (expected '- **Level**: {static|build|runtime}')")
    else
      level=$(printf '%s' "$level_line" \
        | sed -E 's/.*\*\*Level\*\*:[[:space:]]*//' \
        | sed -E 's/[[:space:]].*//' \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d '\r')
      case "$level" in
        static|build|runtime) ;;
        *) errors+=("Test Environment 'Level' must be one of {static, build, runtime} (got: '$level')") ; level="" ;;
      esac
    fi

    # Extract Runtime verify target + Env bootstrap command
    local target_line bootstrap_line target="" bootstrap=""
    target_line=$(grep -E '^\*\*Runtime verify target\*\*: |^- \*\*Runtime verify target\*\*: ' "$FILE" | head -n1 || true)
    bootstrap_line=$(grep -E '^\*\*Env bootstrap command\*\*: |^- \*\*Env bootstrap command\*\*: ' "$FILE" | head -n1 || true)

    if [[ -z "$target_line" ]]; then
      errors+=("Test Environment missing 'Runtime verify target' field (expected '- **Runtime verify target**: {url|N/A}')")
    else
      target=$(printf '%s' "$target_line" | sed -E 's/.*\*\*Runtime verify target\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    if [[ -z "$bootstrap_line" ]]; then
      errors+=("Test Environment missing 'Env bootstrap command' field (expected '- **Env bootstrap command**: {command|N/A}')")
    else
      bootstrap=$(printf '%s' "$bootstrap_line" | sed -E 's/.*\*\*Env bootstrap command\*\*:[[:space:]]*//' | tr -d '\r')
    fi

    # Apply Level-specific cross-field rules (§ 5.1 + § 3.3)
    if [[ -n "$level" ]]; then
      if [[ "$level" == "runtime" ]]; then
        # --- Level=runtime rules ---
        local normalized_target
        normalized_target=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)

        if [[ -z "$normalized_target" || "$normalized_target" == "N/A" || "$normalized_target" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Runtime verify target (got: '${normalized_target:-<empty>}')")
        elif ! printf '%s' "$normalized_target" | grep -Eq '^https?://'; then
          errors+=("Level=runtime requires Runtime verify target to be an http/https URL (got: '$normalized_target')")
        fi

        local normalized_bootstrap
        normalized_bootstrap=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -z "$normalized_bootstrap" || "$normalized_bootstrap" == "N/A" || "$normalized_bootstrap" == "n/a" ]]; then
          errors+=("Level=runtime requires non-N/A Env bootstrap command")
        fi

        # Verify Command / 驗收步驟 host must equal Runtime verify target host (§ 5.1 rule 4)
        if grep -qF "$verify_section_name" "$FILE"; then
          local verify_section verify_cmd verify_cmd_compact
          verify_section=$(extract_markdown_section "$FILE" "$verify_section_name")
          verify_cmd=$(printf '%s\n' "$verify_section" | extract_first_fenced_code_block)
          verify_cmd_compact=$(printf '%s' "$verify_cmd" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | xargs 2>/dev/null || true)

          if [[ -z "$verify_cmd_compact" ]]; then
            errors+=("$verify_section_name fenced code block is empty (Level=runtime requires a live endpoint URL inside)")
          else
            local verify_url target_host verify_host
            verify_url=$(python3 -c "
import re, sys
s = sys.stdin.read()
m = re.search(r'https?://[^\s\"\'\\)]+', s)
print(m.group(0) if m else '')
" <<< "$verify_cmd_compact" 2>/dev/null || true)

            if [[ -z "$verify_url" ]]; then
              errors+=("Level=runtime requires Verify Command fenced block to contain a live http/https endpoint URL")
            else
              target_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$normalized_target" 2>/dev/null || true)
              verify_host=$(python3 -c "
from urllib.parse import urlparse
import sys
u = sys.argv[1]
print((urlparse(u).hostname or '').lower())
" "$verify_url" 2>/dev/null || true)

              if [[ -z "$target_host" || -z "$verify_host" ]]; then
                errors+=("unable to parse host from Runtime verify target ('$normalized_target') or Verify Command URL ('$verify_url')")
              elif [[ "$target_host" != "$verify_host" ]]; then
                errors+=("Level=runtime: Verify Command URL host ($verify_host) must match Runtime verify target host ($target_host) — DP-023 Target-first rule")
              fi

              if is_docs_manager_page_deliverable "$FILE" "$normalized_target"; then
                local target_path verify_path
                target_path=$(python3 -c "
from urllib.parse import urlparse
import sys
print(urlparse(sys.argv[1]).path or '/')
" "$normalized_target" 2>/dev/null || true)
                verify_path=$(python3 -c "
from urllib.parse import urlparse
import sys
print(urlparse(sys.argv[1]).path or '/')
" "$verify_url" 2>/dev/null || true)
                if [[ "$target_path" != /docs-manager/* && "$target_path" != "/docs-manager/" ]]; then
                  errors+=("docs-manager runtime target must include /docs-manager/ path (got: '$normalized_target')")
                fi
                if [[ "$verify_path" != /docs-manager/* && "$verify_path" != "/docs-manager/" ]]; then
                  errors+=("docs-manager Verify Command URL must include /docs-manager/ path (got: '$verify_url')")
                fi
              fi
            fi
          fi
        fi

      elif [[ "$level" == "static" ]]; then
        # --- Level=static: Runtime verify target + Env bootstrap must be N/A ---
        local t_val b_val
        t_val=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)
        b_val=$(printf '%s' "${bootstrap:-}" | xargs 2>/dev/null || true)
        if [[ -n "$t_val" && "$t_val" != "N/A" && "$t_val" != "n/a" ]]; then
          errors+=("Level=$level expects Runtime verify target = N/A (got: '$t_val') — avoid false declarations")
        fi
        if [[ -n "$b_val" && "$b_val" != "N/A" && "$b_val" != "n/a" ]]; then
          errors+=("Level=$level expects Env bootstrap command = N/A (got: '$b_val') — avoid false declarations")
        fi
      elif [[ "$level" == "build" ]]; then
        # --- Level=build: Runtime verify target must be N/A; Env bootstrap may be N/A or an install/build setup command. ---
        local t_val
        t_val=$(printf '%s' "${target:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)
        if [[ -n "$t_val" && "$t_val" != "N/A" && "$t_val" != "n/a" ]]; then
          errors+=("Level=$level expects Runtime verify target = N/A (got: '$t_val') — build gates should not declare live endpoints")
        fi
      fi

      # --- DP-369 GapA: Env bootstrap command executability smoke ---
      # run-verify-command.sh runs `bash -c` on the Env bootstrap command at
      # engineering RUN; a prose / non-executable value must fail LOCK/breakdown
      # here instead of exploding at RUN. Applies to runtime and build levels
      # (both can carry a non-N/A bootstrap); static requires N/A (enforced
      # above) so no smoke is needed. N/A / empty stays valid (no-op). Reuses the
      # verify_command_static_smoke primitive with kind=env_bootstrap — single
      # classifier, no second parser (AC-NEG3).
      if [[ "$level" == "runtime" || "$level" == "build" ]]; then
        local env_bootstrap_norm
        env_bootstrap_norm=$(printf '%s' "${bootstrap:-}" | sed -E 's/^`|`$//g' | xargs 2>/dev/null || true)
        if [[ -n "$env_bootstrap_norm" && "$env_bootstrap_norm" != "N/A" && "$env_bootstrap_norm" != "n/a" ]]; then
          local eb_output eb_rc
          set +e
          eb_output=$(verify_command_static_smoke "$FILE" "$env_bootstrap_norm" env_bootstrap 2>/dev/null)
          eb_rc=$?
          set -e
          if [[ "$eb_rc" -ne 0 ]]; then
            while IFS= read -r eb_line; do
              [[ -n "$eb_line" ]] && errors+=("$eb_line")
            done <<< "$eb_output"
          fi
        fi
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # Optional VR metadata: frontmatter verification.visual_regression.
  # When declared, it must be schema-valid and tied to runtime verification.
  # ---------------------------------------------------------------------------
  local vr_state vr_present vr_is_map vr_expected vr_expected_is_string vr_pages_present vr_pages_is_list
  vr_state="$(extract_vr_frontmatter_state "$FILE")"
  vr_present="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("present") else "0")' "$vr_state")"
  if [[ "$vr_present" == "1" ]]; then
    vr_is_map="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("is_map") else "0")' "$vr_state")"
    vr_expected="$(python3 -c 'import json,sys; v=json.loads(sys.argv[1]).get("expected"); print("" if v is None else v)' "$vr_state")"
    vr_expected_is_string="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("expected_is_string") else "0")' "$vr_state")"
    vr_pages_present="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("pages_present") else "0")' "$vr_state")"
    vr_pages_is_list="$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1]).get("pages_is_list") else "0")' "$vr_state")"

    if [[ "$vr_is_map" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression must be a map with expected and pages")
    fi
    if [[ "$vr_expected_is_string" != "1" || -z "$vr_expected" ]]; then
      errors+=("frontmatter verification.visual_regression.expected is required")
    else
      case "$vr_expected" in
        none_allowed|baseline_required|update_baseline) ;;
        *) errors+=("frontmatter verification.visual_regression.expected must be none_allowed, baseline_required, or update_baseline (got: '$vr_expected')") ;;
      esac
    fi
    if [[ "$vr_pages_present" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression.pages is required; use [] to select workspace-config pages")
    elif [[ "$vr_pages_is_list" != "1" ]]; then
      errors+=("frontmatter verification.visual_regression.pages must be a YAML list")
    fi
    if [[ "$level" != "runtime" ]]; then
      errors+=("frontmatter verification.visual_regression requires Test Environment Level=runtime (got: '${level:-<empty>}')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # Optional behavior contract metadata: frontmatter verification.behavior_contract.
  # When declared, it must explicitly say whether runtime/user-visible behavior
  # verification applies; applies=true has no unknown/default mode.
  # ---------------------------------------------------------------------------
  local behavior_contract_errors behavior_contract_error
  behavior_contract_errors="$(validate_behavior_contract_frontmatter "$FILE")"
  if [[ -n "$behavior_contract_errors" ]]; then
    while IFS= read -r behavior_contract_error; do
      [[ -n "$behavior_contract_error" ]] && errors+=("$behavior_contract_error")
    done <<< "$behavior_contract_errors"
  fi

  if [[ "$mode" == "T" ]] && grep -qF "## Verify Command" "$FILE"; then
    local smoke_section smoke_cmd smoke_output smoke_rc
    smoke_section=$(extract_markdown_section "$FILE" "## Verify Command")
    smoke_cmd=$(printf '%s\n' "$smoke_section" | extract_first_fenced_code_block)
    if [[ -n "$smoke_cmd" ]]; then
      set +e
      smoke_output=$(verify_command_static_smoke "$FILE" "$smoke_cmd" 2>/dev/null)
      smoke_rc=$?
      set -e
      if [[ "$smoke_rc" -ne 0 ]]; then
        while IFS= read -r line; do
          [[ -n "$line" ]] && errors+=("$line")
        done <<< "$smoke_output"
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED: ## Verify Command (T) / ## 驗收步驟 (V) — only Hard when Level ≠ static
  # § 3.1 / § 4.1 / § 4.5
  # For Level=static: section is Optional (no check).
  # For Level=build|runtime: section must exist with fenced code block.
  # (runtime host-alignment check already done above inside Test Environment block.)
  # T/V 共用，使用 verify_section_name 動態指向。
  # ---------------------------------------------------------------------------
  if [[ -n "$level" && "$level" != "static" ]]; then
    if ! grep -qF "$verify_section_name" "$FILE"; then
      errors+=("missing Hard required section: $verify_section_name (required when Level=$level)")
    else
      local vc_code
      vc_code=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block (required when Level=$level)")
      fi
    fi
  elif [[ -z "$level" ]]; then
    # Level unknown (Test Environment missing or malformed) — check section integrity
    # if the section exists, it must have a code block (preserve prior behavior).
    if grep -qF "$verify_section_name" "$FILE"; then
      local vc_code2
      vc_code2=$(extract_markdown_section "$FILE" "$verify_section_name" | extract_first_fenced_code_block | tr -d '[:space:]')
      if [[ -z "$vc_code2" ]]; then
        errors+=("$verify_section_name section missing executable fenced code block")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # HARD REQUIRED (T mode only): ## Test Command must contain a fenced code block (§ 3.5)
  # V mode 不跑 unit test → 不需 Test Command（§ 4.1 「合理省略」）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && grep -qF "## Test Command" "$FILE"; then
    local tc_code
    tc_code=$(extract_markdown_section "$FILE" "## Test Command" | extract_first_fenced_code_block | tr -d '[:space:]')
    if [[ -z "$tc_code" ]]; then
      errors+=("## Test Command section missing executable fenced code block")
    fi
  fi

  # ---------------------------------------------------------------------------
  # DP-028 Cross-field (T mode only): Depends on (non-empty) ⇒ Base branch must start with task/
  # § 5.2 — V mode 通常從 feat/... 或 develop 跑驗收，不適用此 cross-field（§ 5.2 表格）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]]; then
    local depends_on_val base_branch_val
    depends_on_val=$(extract_op_ctx_field "$FILE" "Depends on")
    base_branch_val=$(extract_op_ctx_field "$FILE" "Base branch")
    local deps_normalized
    deps_normalized=$(printf '%s' "$depends_on_val" | tr '[:upper:]' '[:lower:]' | xargs 2>/dev/null || true)
    if [[ -n "$deps_normalized" \
          && "$deps_normalized" != "n/a" \
          && "$deps_normalized" != "-" \
          && "$deps_normalized" != "無" \
          && "$deps_normalized" != "none" ]]; then
      if [[ -z "$base_branch_val" ]]; then
        errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: <empty>)")
      elif [[ "$base_branch_val" != task/* ]]; then
        errors+=("DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: '$base_branch_val')")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (T mode only): deliverable schema (§ 2.1 + § 3.6 + DP-033 D7)
  # Not required to exist; validator only checks schema WHEN the block is present.
  # V mode 對稱 lifecycle 是 ac_verification（見下方 V-only block）。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && frontmatter_key_exists "$FILE" "deliverable" 2>/dev/null; then
    local fm_block
    fm_block=$(extract_frontmatter_block "$FILE")

    # Extract indented scalar fields under deliverable:
    # pr_url, pr_state, head_sha
    local pr_url pr_state head_sha
    pr_url=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_url:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    pr_state=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+pr_state:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')
    head_sha=$(printf '%s\n' "$fm_block" | awk '
      /^[[:space:]]+head_sha:[[:space:]]/ {
        val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
        print val; exit
      }
    ')

    # Validate pr_url
    if [[ -z "$pr_url" ]]; then
      errors+=("deliverable.pr_url is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$pr_url" | grep -qE '^https://github\.com/.+/pull/[0-9]+$'; then
      errors+=("deliverable.pr_url must match '^https://github\\.com/.+/pull/[0-9]+\$' (got: '$pr_url')")
    fi

    # Validate pr_state
    if [[ -z "$pr_state" ]]; then
      errors+=("deliverable.pr_state is missing or empty (required when deliverable block is present)")
    else
      case "$pr_state" in
        OPEN|MERGED|CLOSED) ;;
        *) errors+=("deliverable.pr_state must be OPEN, MERGED, or CLOSED (got: '$pr_state')") ;;
      esac
    fi

    # Validate head_sha (7+ hex chars)
    if [[ -z "$head_sha" ]]; then
      errors+=("deliverable.head_sha is missing or empty (required when deliverable block is present)")
    elif ! printf '%s' "$head_sha" | grep -qE '^[0-9a-fA-F]{7,}$'; then
      errors+=("deliverable.head_sha must be a hex string of ≥ 7 characters (got: '$head_sha')")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (T mode only): extension_deliverable schema (DP-048)
  # Used by local_extension delivery endpoints. It may supplement a real
  # workspace PR deliverable for post-PR release tails, or stand alone for
  # explicitly PR-bypass endpoints; validator only checks structure WHEN the
  # block is present.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "T" ]] && frontmatter_key_exists "$FILE" "extension_deliverable" 2>/dev/null; then
    local fm_block_ext
    fm_block_ext=$(extract_frontmatter_block "$FILE")

    extract_ext_field() {
      printf '%s\n' "$fm_block_ext" | awk -v key="$1" '
        /^extension_deliverable:/ { in_block=1; in_evidence=0; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && /^[[:space:]]+evidence:/ { in_evidence=1; next }
        in_block && /^[[:space:]]+[A-Za-z0-9_.-]+:/ { in_evidence=0 }
        in_block && !in_evidence && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      '
    }

    extract_ext_evidence_field() {
      printf '%s\n' "$fm_block_ext" | awk -v key="$1" '
        /^extension_deliverable:/ { in_block=1; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && /^[[:space:]]+evidence:/ { in_evidence=1; next }
        in_evidence && /^[[:space:]]{4}/ && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
        in_evidence && /^[[:space:]]{2}[A-Za-z0-9_.-]+:/ { exit }
      '
    }

    local ext_endpoint ext_extension_id ext_task_head ext_workspace_commit ext_template_commit ext_version_tag ext_release_url ext_completed_at
    local ext_ci_evidence ext_verify_evidence ext_vr_evidence
    ext_endpoint=$(extract_ext_field "endpoint")
    ext_extension_id=$(extract_ext_field "extension_id")
    ext_task_head=$(extract_ext_field "task_head_sha")
    ext_workspace_commit=$(extract_ext_field "workspace_commit")
    ext_template_commit=$(extract_ext_field "template_commit")
    ext_version_tag=$(extract_ext_field "version_tag")
    ext_release_url=$(extract_ext_field "release_url")
    ext_completed_at=$(extract_ext_field "completed_at")
    ext_ci_evidence=$(extract_ext_evidence_field "ci_local")
    ext_verify_evidence=$(extract_ext_evidence_field "verify")
    ext_vr_evidence=$(extract_ext_evidence_field "vr")

    if [[ "$ext_endpoint" != "local_extension" ]]; then
      errors+=("extension_deliverable.endpoint must be local_extension (got: '${ext_endpoint:-<empty>}')")
    fi
    if [[ -z "$ext_extension_id" ]]; then
      errors+=("extension_deliverable.extension_id is missing or empty")
    elif ! printf '%s' "$ext_extension_id" | grep -qE '^[A-Za-z0-9._-]+$'; then
      errors+=("extension_deliverable.extension_id contains unsupported characters (got: '$ext_extension_id')")
    fi
    for field in task_head_sha workspace_commit template_commit; do
      local field_value
      case "$field" in
        task_head_sha) field_value="$ext_task_head" ;;
        workspace_commit) field_value="$ext_workspace_commit" ;;
        template_commit) field_value="$ext_template_commit" ;;
      esac
      if [[ -z "$field_value" ]]; then
        errors+=("extension_deliverable.$field is missing or empty")
      elif ! printf '%s' "$field_value" | grep -qE '^[0-9a-fA-F]{7,40}$'; then
        errors+=("extension_deliverable.$field must be a 7-40 char hex SHA (got: '$field_value')")
      fi
    done
    if [[ -z "$ext_version_tag" ]]; then
      errors+=("extension_deliverable.version_tag is missing or empty")
    elif [[ "$ext_version_tag" != "N/A" ]] && ! printf '%s' "$ext_version_tag" | grep -qE '^v[0-9][A-Za-z0-9._-]*$'; then
      errors+=("extension_deliverable.version_tag must look like v1.2.3 or be N/A (got: '$ext_version_tag')")
    fi
    if [[ -n "$ext_release_url" && "$ext_release_url" != "N/A" ]] && ! printf '%s' "$ext_release_url" | grep -qE '^https://github\.com/.+/releases/tag/.+$'; then
      errors+=("extension_deliverable.release_url must be a GitHub release URL or N/A (got: '$ext_release_url')")
    fi
    if [[ -z "$ext_completed_at" ]]; then
      errors+=("extension_deliverable.completed_at is missing or empty")
    elif ! printf '%s' "$ext_completed_at" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$'; then
      errors+=("extension_deliverable.completed_at must be ISO 8601 timestamp (got: '$ext_completed_at')")
    fi
    if [[ -z "$ext_ci_evidence" ]]; then
      errors+=("extension_deliverable.evidence.ci_local is missing (use N/A when no ci-local is declared)")
    fi
    if [[ -z "$ext_verify_evidence" || "$ext_verify_evidence" == "N/A" ]]; then
      errors+=("extension_deliverable.evidence.verify is missing or N/A")
    fi
    if [[ -z "$ext_vr_evidence" ]]; then
      errors+=("extension_deliverable.evidence.vr is missing (use N/A when VR did not run)")
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification schema (§ 4.6 + § 4.7,
  # symmetric to deliverable D7). verify-AC writes summary on every run.
  # Not required to exist (breakdown stage absent is legal); only check WHEN present.
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification" 2>/dev/null; then
    local fm_block_v
    fm_block_v=$(extract_frontmatter_block "$FILE")

    # Helper: extract scalar field under `ac_verification:` block (state machine).
    # Stops at the next top-level (unindented) YAML key.
    extract_av_field() {
      printf '%s\n' "$fm_block_v" | awk -v key="$1" '
        /^ac_verification:/ { in_block=1; next }
        in_block && /^[^[:space:]#]/ { exit }
        in_block && match($0, "^[[:space:]]+" key ":[[:space:]]") {
          val = $0; sub(/^[^:]*:[[:space:]]*/, "", val); sub(/[[:space:]]+$/, "", val)
          print val; exit
        }
      '
    }

    local av_status av_last_run av_total av_pass av_fail av_manual av_uncertain av_disposition av_pending_disp
    av_status=$(extract_av_field "status")
    av_last_run=$(extract_av_field "last_run_at")
    av_total=$(extract_av_field "ac_total")
    av_pass=$(extract_av_field "ac_pass")
    av_fail=$(extract_av_field "ac_fail")
    av_manual=$(extract_av_field "ac_manual_required")
    av_uncertain=$(extract_av_field "ac_uncertain")
    av_disposition=$(extract_av_field "human_disposition")
    # DP-230 T2: pending-stage `disposition:` field — schema doc fixture form,
    # written by breakdown before verify-AC has run. Distinct from post-run
    # `status:` field. Either `status:` (post-run form) or `disposition:`
    # (pending form) must be present.
    av_pending_disp=$(extract_av_field "disposition")

    if [[ -z "$av_status" && -n "$av_pending_disp" ]]; then
      # ---------------------------------------------------------------------
      # Pending form (pre verify-AC run, schema doc fixture).
      # disposition enum only; runtime counters not required yet.
      # ---------------------------------------------------------------------
      case "$av_pending_disp" in
        pending|pass|fail|drift_retry) ;;
        *) errors+=("ac_verification.disposition must be pending|pass|fail|drift_retry (got: '$av_pending_disp')") ;;
      esac
    elif [[ -z "$av_status" ]]; then
      errors+=("ac_verification.status is missing or empty (required when ac_verification block is present; pending form must declare disposition: pending|pass|fail|drift_retry)")
    else
      # ---------------------------------------------------------------------
      # Post-run form (verify-AC already executed). Existing strict schema.
      # ---------------------------------------------------------------------
      case "$av_status" in
        PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS) ;;
        *) errors+=("ac_verification.status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS (got: '$av_status')") ;;
      esac
    fi

    # Post-run schema checks only apply when the runtime `status:` field is set.
    # DP-230 T2: pending form (`disposition:` only) skips the counter / last_run_at
    # / human_disposition requirements — verify-AC populates those on first run.
    if [[ -n "$av_status" ]]; then
      # last_run_at ISO 8601 (loose: must look like YYYY-MM-DDThh:mm:ss with optional Z/±offset)
      if [[ -z "$av_last_run" ]]; then
        errors+=("ac_verification.last_run_at is missing or empty (required when ac_verification block is present)")
      elif ! printf '%s' "$av_last_run" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:?[0-9]{2})?$'; then
        errors+=("ac_verification.last_run_at must be ISO 8601 timestamp (got: '$av_last_run')")
      fi

      # ac_total / ac_pass / ac_fail / ac_manual_required / ac_uncertain — int ≥ 0; sum == total
      local _is_int='^-?[0-9]+$'
      local sum=0 has_count_error=0
      local field val
      for field in ac_total ac_pass ac_fail ac_manual_required ac_uncertain; do
        val=$(extract_av_field "$field")
        if [[ -z "$val" ]]; then
          errors+=("ac_verification.$field is missing or empty (required when ac_verification block is present)")
          has_count_error=1
          continue
        fi
        if ! [[ "$val" =~ ^[0-9]+$ ]]; then
          errors+=("ac_verification.$field must be a non-negative integer (got: '$val')")
          has_count_error=1
          continue
        fi
        if [[ "$field" != "ac_total" ]]; then
          sum=$((sum + val))
        fi
      done
      if [[ "$has_count_error" -eq 0 && -n "$av_total" ]]; then
        if [[ "$sum" -ne "$av_total" ]]; then
          errors+=("ac_verification: ac_pass + ac_fail + ac_manual_required + ac_uncertain ($sum) must equal ac_total ($av_total)")
        fi
      fi

      # human_disposition: required when status != PASS
      if [[ "$av_status" != "PASS" && "$av_status" != "IN_PROGRESS" ]]; then
        if [[ -z "$av_disposition" ]]; then
          errors+=("ac_verification.human_disposition is required when status='$av_status' (FAIL/MANUAL_REQUIRED/UNCERTAIN/BLOCKED_ENV need human triage)")
        else
          case "$av_disposition" in
            passed|rejected|deferred) ;;
            *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
          esac
        fi
      elif [[ -n "$av_disposition" ]]; then
        # status=PASS or IN_PROGRESS but human_disposition is set — must still be valid enum
        case "$av_disposition" in
          passed|rejected|deferred) ;;
          *) errors+=("ac_verification.human_disposition must be passed|rejected|deferred (got: '$av_disposition')") ;;
        esac
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL (V mode only): ac_verification_log schema (§ 4.6 + § 4.7, loose)
  # Same精神 as jira_transition_log — list-of-maps，time 建議不強制；其他欄位 freeform。
  # ---------------------------------------------------------------------------
  if [[ "$mode" == "V" ]] && frontmatter_key_exists "$FILE" "ac_verification_log" 2>/dev/null; then
    local fm_block_avl
    fm_block_avl=$(extract_frontmatter_block "$FILE")

    # Reject inline scalar (e.g., `ac_verification_log: some_string`).
    local avl_inline
    avl_inline=$(printf '%s\n' "$fm_block_avl" | awk '
      /^ac_verification_log:/ {
        val = $0
        sub(/^ac_verification_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$avl_inline" ]]; then
      errors+=("ac_verification_log must be a YAML list (array), not a scalar (got inline value: '$avl_inline')")
    else
      # Each entry must be a map (key: value), not a bare scalar.
      local avl_bad
      avl_bad=$(printf '%s\n' "$fm_block_avl" | awk '
        /^ac_verification_log:/ { in_blk=1; next }
        in_blk && /^[^[:space:]]/ { exit }
        in_blk && /^[[:space:]]+-[[:space:]]+[^{]/ {
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$avl_bad" ]]; then
        errors+=("ac_verification_log entries must be YAML maps (key: value), not bare scalars ($avl_bad)")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # LIFECYCLE-CONDITIONAL: jira_transition_log schema (§ 2.1 + DP-033 D7, loose)
  # Not required to exist; WHEN present: must be a YAML list (not scalar).
  # Each entry should be a map; time is recommended but not enforced.
  # ---------------------------------------------------------------------------
  if frontmatter_key_exists "$FILE" "jira_transition_log" 2>/dev/null; then
    local fm_block2
    fm_block2=$(extract_frontmatter_block "$FILE")

    # Check that jira_transition_log is NOT a scalar (inline value on the key line).
    # Valid forms: empty value (list follows on next lines) or "[]"
    # Invalid: jira_transition_log: some_string
    local jtl_inline
    jtl_inline=$(printf '%s\n' "$fm_block2" | awk '
      /^jira_transition_log:/ {
        val = $0
        sub(/^jira_transition_log:[[:space:]]*/, "", val)
        sub(/[[:space:]]+$/, "", val)
        if (val != "" && val != "[]" && val != "~" && val != "null") {
          print val
        }
        exit
      }
    ')
    if [[ -n "$jtl_inline" ]]; then
      errors+=("jira_transition_log must be a YAML list (array), not a scalar (got inline value: '$jtl_inline')")
    else
      # Verify each list entry (lines starting with "  - ") is a map (has at least one sub-key: value pair).
      # Loose check: each "  - " line must be followed by at least one "    key: value" line.
      # We just verify that if there are entries, they don't look like raw scalars on the same line.
      local jtl_bad_entries
      jtl_bad_entries=$(printf '%s\n' "$fm_block2" | awk '
        /^jira_transition_log:/ { in_jtl=1; next }
        in_jtl && /^[^[:space:]]/ { exit }
        in_jtl && /^[[:space:]]+-[[:space:]]+[^{]/ {
          # "  - value" (bare scalar entry) — not a map
          sub(/^[[:space:]]+-[[:space:]]*/, "", $0)
          # If remainder looks like a plain scalar (no colon), it might be a scalar entry.
          # But since YAML allows "- key: val" on one line too, only flag obvious non-map.
          if ($0 !~ /:/) { print "bare scalar entry: " $0 }
        }
      ')
      if [[ -n "$jtl_bad_entries" ]]; then
        errors+=("jira_transition_log entries must be YAML maps (key: value), not bare scalars ($jtl_bad_entries)")
      fi
    fi
  fi

  # ---------------------------------------------------------------------------
  # Output: warnings (non-blocking) + errors (violations → exit 1)
  # ---------------------------------------------------------------------------
  if [[ ${#warnings[@]} -gt 0 ]]; then
    echo "⚠ task.md soft warnings in $FILE:" >&2
    local w
    for w in "${warnings[@]}"; do
      echo "  ~ $w" >&2
    done
    echo "" >&2
  fi

  if [[ ${#errors[@]} -eq 0 ]]; then
    return 0
  fi

  echo "✗ task.md schema violations in $FILE:" >&2
  local err
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  echo "" >&2
  echo "Contract: skills/references/task-md-schema.md (DP-033 A2 full enforcer)" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Scan mode: recursively validate all T*.md and V*.md in specs/*/tasks/ (skip pr-release/)
# Always exits 0; produces PASS/FAIL/HARD summary lines.
# DP-033 Phase B: filename pattern擴展到 V*.md (filename dispatch 對 T/V 共用).
# ---------------------------------------------------------------------------
if [[ "$1" == "--scan" ]]; then
  if [[ $# -ne 2 ]]; then
    usage
  fi
  root="$2"
  if [[ ! -d "$root" ]]; then
    echo "error: scan root not found: $root" >&2
    exit 2
  fi

  pass=0
  fail=0
  hard=0
  while IFS= read -r f; do
    case "$f" in
      */.worktrees/*|*/node_modules/*) continue ;;
      */tasks/pr-release/*) continue ;;
    esac
    case "$f" in
      */specs/*/tasks/T*.md|*/specs/*/tasks/T*/index.md) ;;
      */specs/*/tasks/V*.md|*/specs/*/tasks/V*/index.md) ;;
      *) continue ;;
    esac

    rc=0
    validate_file "$f" >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0)
        printf "PASS  %s\n" "$f"
        pass=$((pass+1))
        ;;
      2)
        printf "HARD  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        hard=$((hard+1))
        fail=$((fail+1))
        ;;
      *)
        printf "FAIL  %s\n" "$f"
        validate_file "$f" 2>&1 | sed 's/^/      /' >&2 || true
        fail=$((fail+1))
        ;;
    esac
  done < <(find "$root" -type f \( -name 'T*.md' -o -name 'V*.md' -o -name 'index.md' \) 2>/dev/null | sort)

  echo ""
  echo "task.md scan: $pass pass, $fail fail ($hard hard-fail) — total $((pass+fail))"
  exit 0
fi

# ---------------------------------------------------------------------------
# Single-file mode
# ---------------------------------------------------------------------------
validate_file "$1"
exit $?
