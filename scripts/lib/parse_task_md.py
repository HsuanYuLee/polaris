"""Canonical task.md parser and field selector."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


def die(message: str, code: int = 2) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(code)


if os.environ.get("PARSE_TASK_MD_SELFTEST") == "1":
    root = Path(__file__).resolve().parents[2]
    selftest_env = os.environ.copy()
    selftest_env.pop("PARSE_TASK_MD_SELFTEST", None)
    raise SystemExit(subprocess.run([
        "mise", "exec", "--", "pytest", "tests/test_parse_task_md.py", "-q",
        "-k", "not embedded_parse_task_md_selftest_remains_green",
    ], cwd=root, env=selftest_env).returncode)

parser = argparse.ArgumentParser(
    add_help=False,
    allow_abbrev=False,
    usage="parse-task-md.sh <task.md> [--field key] [--no-resolve]",
)
parser.add_argument("path", nargs="?")
parser.add_argument("--field", default="")
parser.add_argument("--key", default="")
parser.add_argument("--tasks-dir", default="")
parser.add_argument("--no-resolve", action="store_true")
parser.add_argument("-h", "--help", action="store_true")
parsed = parser.parse_args()
if parsed.help:
    parser.print_usage(sys.stderr)
    raise SystemExit(2)

field = parsed.field
no_resolve = parsed.no_resolve
task_key = parsed.key
tasks_dir = parsed.tasks_dir
path = parsed.path or ""

if task_key:
    base = Path(tasks_dir).resolve() if tasks_dir else None
    if base is None or not base.is_dir():
        die("--key requires an existing --tasks-dir")
    candidates = [base / f"{task_key}.md", base / task_key / "index.md",
                  base / "pr-release" / f"{task_key}.md", base / "pr-release" / task_key / "index.md"]
    found = next((candidate for candidate in candidates if candidate.is_file()), None)
    if found is None:
        die(f"broken ref — task key '{task_key}' not found under {base}/ (flat or folder-native, active or pr-release)")
    path = str(found)
if not path:
    die("usage: parse-task-md.sh <task.md> [--field key] [--no-resolve]")
task_file = Path(path).resolve()
if not task_file.is_file():
    die(f"file not found: {path}")
path = str(task_file)
resolved_base = None
if not no_resolve:
    resolver = Path(__file__).resolve().parents[1] / "resolve-task-base.sh"
    proc = subprocess.run([str(resolver), path], text=True, capture_output=True, check=False)
    if proc.returncode == 0 and proc.stdout.strip():
        resolved_base = proc.stdout.strip()
    else:
        print(f"warn: resolve-task-base.sh failed for {path} (resolved_base=null)", file=sys.stderr)

try:
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
except OSError as e:
    sys.stderr.write(f"error: cannot read {path}: {e}\n")
    sys.exit(1)

lines = text.splitlines()

# ---- frontmatter -----------------------------------------------------------
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
    """Parse the YAML subset used by task.md lifecycle metadata.

    This intentionally avoids a PyYAML dependency. It supports top-level
    scalars, bracket lists, 2-space nested maps, one 4-space nested map level
    (for extension_deliverable.evidence), and one 6-space nested map level
    under a 4-space key (for deliverable.verification.ac_counts, DP-360 T6/T7).
    """
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
                    nested_key = nested_key.strip()
                    nested_value = nested_value.strip()
                    if nested_value:
                        nested[nested_key] = parse_scalar(nested_value)
                        i += 1
                        continue
                    # 4-space key with no inline value → one deeper (6-space) map
                    # level, e.g. deliverable.verification.ac_counts (DP-360).
                    deep = {}
                    i += 1
                    while i < len(fm_lines):
                        deep_raw = fm_lines[i]
                        if not deep_raw.strip():
                            i += 1
                            continue
                        deep_indent = len(deep_raw) - len(deep_raw.lstrip(" "))
                        if deep_indent <= 4:
                            break
                        deep_stripped = deep_raw.strip()
                        if deep_indent == 6 and ":" in deep_stripped:
                            deep_key, _, deep_value = deep_stripped.partition(":")
                            deep[deep_key.strip()] = parse_scalar(deep_value.strip())
                        i += 1
                    nested[nested_key] = deep
                    continue
                i += 1
            mapping[child_key] = nested
        out[key] = mapping
    return out

frontmatter = {}
body_start = 0
if lines and lines[0].strip() == "---":
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is not None:
        frontmatter = parse_frontmatter_lines(lines[1:end])
        body_start = end + 1

body_lines = lines[body_start:]


# ---- header: # T{n}[suffix]: {summary} ({SP} pt) --------------------------
header = {"task_id": None, "summary": None, "story_points": None}
header_re = re.compile(r"^#\s+(T\d+[a-z]*)\s*:\s*(.+?)\s*\(([0-9.]+)\s*pt\)\s*$")
for ln in body_lines:
    m = header_re.match(ln)
    if m:
        header["task_id"] = m.group(1)
        header["summary"] = m.group(2).strip()
        sp_str = m.group(3)
        try:
            sp = float(sp_str)
            header["story_points"] = int(sp) if sp.is_integer() else sp
        except ValueError:
            header["story_points"] = sp_str
        break


# ---- metadata quote line --------------------------------------------------
# Legacy:
#   > Epic: ... | JIRA: KEY | Repo: ...
# Canonical candidate (DP-050):
#   > Source: DP-050 | Task: DP-050-T1 | JIRA: N/A | Repo: ...
metadata = {"epic": None, "source": None, "task": None, "jira": None, "repo": None}
for ln in body_lines:
    mm = re.match(r"^>\s*(.+)$", ln)
    if not mm or ("JIRA:" not in mm.group(1) and "Task:" not in mm.group(1)):
        continue
    for p in [s.strip() for s in mm.group(1).split("|")]:
        if p.startswith("Epic:"):
            metadata["epic"] = p[len("Epic:"):].strip() or None
        elif p.startswith("Source:"):
            metadata["source"] = p[len("Source:"):].strip() or None
        elif p.startswith("Task:"):
            metadata["task"] = p[len("Task:"):].strip() or None
        elif p.startswith("JIRA:"):
            metadata["jira"] = p[len("JIRA:"):].strip() or None
        elif p.startswith("Repo:"):
            metadata["repo"] = p[len("Repo:"):].strip() or None
    break


# ---- section indexing -----------------------------------------------------
def iter_sections(lns):
    i = 0
    while i < len(lns):
        if lns[i].startswith("## "):
            heading = lns[i].rstrip()
            start = i + 1
            j = start
            while j < len(lns) and not lns[j].startswith("## "):
                j += 1
            yield heading, lns[start:j]
            i = j
        else:
            i += 1

sections = {h.strip(): body for h, body in iter_sections(body_lines)}

def section_lines(heading):
    return sections.get(heading, [])


# ---- Operational Context table -------------------------------------------
op_ctx_raw = {}
for ln in section_lines("## Operational Context"):
    if not ln.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in ln.strip().strip("|").split("|")]
    if len(cells) < 2:
        continue
    name, val = cells[0], cells[1]
    if not name or name in ("欄位",) or set(name) <= {"-", " "}:
        continue
    if val == "值":
        continue
    op_ctx_raw[name] = val

NA_SENTINELS = {"-", "N/A", "n/a", "無", "None", "none", ""}

def opf(label, allow_sentinel=False):
    v = op_ctx_raw.get(label)
    if v is None:
        return None
    if not allow_sentinel and v.strip() in NA_SENTINELS:
        return None
    return v

operational_context = {
    "task_jira_key": opf("Task JIRA key"),
    "source_type": opf("Source type"),
    "source_id": opf("Source ID"),
    # DP-338 D1: the dedicated work_item_id cell (canonical {source}-T{n},
    # source-type-agnostic). De-conflated from the "Task ID" cell, which now
    # carries the branch-identity atom. Absent on legacy task.md that predate
    # the split — the identity resolution below falls back to "Task ID" then.
    "work_item_id_cell": opf("Work item ID"),
    "task_id": opf("Task ID"),
    "jira_key": opf("JIRA key"),
    "parent_epic": opf("Parent Epic"),
    "test_sub_tasks": opf("Test sub-tasks"),
    "ac_verification_ticket": opf("AC 驗收單"),
    "base_branch": opf("Base branch"),
    "branch_chain": opf("Branch chain"),
    "task_branch": opf("Task branch"),
    "depends_on": opf("Depends on"),
    "references_to_load": opf("References to load"),
}


# ---- Canonical identity (DP-050) -----------------------------------------
def normalize_jira(value):
    if value is None:
        return None
    v = value.strip()
    if v in NA_SENTINELS or v.upper() == "N/A":
        return None
    return v

def infer_source_type(source_id, work_item_id, jira_key):
    explicit = operational_context.get("source_type")
    if explicit:
        return explicit.lower()
    if (source_id or "").startswith("DP-") or re.match(r"^DP-\d{3}-[TV]\d+[a-z]*$", work_item_id or ""):
        return "dp"
    if jira_key:
        return "jira"
    return None

source_id = (
    operational_context.get("source_id")
    or metadata.get("source")
    or operational_context.get("parent_epic")
    or metadata.get("epic")
)
# DP-338 D1: work_item_id resolution prefers the dedicated "Work item ID" cell
# (canonical {source}-T{n}); the legacy "Task ID" cell / `Task:` quote / jira
# aliases are read-side fallbacks only for task.md that predate the de-conflation
# (EC1). On a current task.md the "Task ID" cell carries the branch-identity atom
# (= jira_key for JIRA-Epic sources), so reading it as work_item_id would re-
# conflate the two; the new cell must therefore win.
work_item_id = (
    operational_context.get("work_item_id_cell")
    or operational_context.get("task_id")
    or metadata.get("task")
    or operational_context.get("task_jira_key")
    or metadata.get("jira")
)
jira_key = normalize_jira(operational_context.get("jira_key") or metadata.get("jira"))
source_type = infer_source_type(source_id, work_item_id, jira_key)
if source_type == "dp":
    jira_key = normalize_jira(operational_context.get("jira_key"))
elif source_type == "jira" and jira_key is None:
    jira_key = work_item_id

# delivery_ticket_key (DP-238 atom matrix): the canonical product-PR-identity
# atom consumed by resolve-task-branch.sh / gate-pr-title.sh / polaris-pr-create.sh.
#   - Bug / JIRA source → jira_key (the real delivery ticket, e.g. PROJ-4190),
#     never the internal task marker work_item_id (e.g. PROJ-4190-T1).
#   - DP-backed source → work_item_id (e.g. DP-238-T4), keeping framework
#     pseudo-task identity backward compatible.
if source_type == "jira":
    delivery_ticket_key = jira_key or work_item_id
else:
    delivery_ticket_key = work_item_id

identity = {
    "source_type": source_type,
    "source_id": source_id,
    "work_item_id": work_item_id,
    "jira_key": jira_key,
    "delivery_ticket_key": delivery_ticket_key,
}

# Migration aliases. Product aliases equal the real JIRA key; DP aliases return
# work_item_id so old consumers keep resolving framework pseudo-tasks.
if operational_context["task_jira_key"] is None and work_item_id:
    operational_context["task_jira_key"] = work_item_id
if metadata["jira"] is not None and normalize_jira(metadata["jira"]) is None:
    metadata["jira"] = None


# ---- Test Environment ----------------------------------------------------
test_env = {
    "level": None,
    "dev_env_config": None,
    "fixtures": None,
    "runtime_verify_target": None,
    "env_bootstrap_command": None,
}
te_re = re.compile(r"^[\-*]?\s*\*\*([^*]+?)\*\*\s*:\s*(.+?)\s*$")
te_map = {
    "Level": "level",
    "Dev env config": "dev_env_config",
    "Fixtures": "fixtures",
    "Runtime verify target": "runtime_verify_target",
    "Env bootstrap command": "env_bootstrap_command",
}
for ln in section_lines("## Test Environment"):
    m = te_re.match(ln)
    if not m:
        continue
    label = m.group(1).strip()
    val = m.group(2).strip()
    key = te_map.get(label)
    if not key:
        continue
    if val.startswith("`") and val.endswith("`") and len(val) > 1:
        val = val[1:-1].strip()
    test_env[key] = val
if test_env["level"] is not None:
    test_env["level"] = test_env["level"].lower()
# Normalize sentinel "N/A" / "-" / empty → null on string fields. Level is an
# enum and stays as-is; consumer branches on level before reading other fields.
for k in ("dev_env_config", "fixtures", "runtime_verify_target", "env_bootstrap_command"):
    v = test_env.get(k)
    if v is not None and v.strip() in NA_SENTINELS:
        test_env[k] = None


# ---- Verification metadata ------------------------------------------------
verification_block = frontmatter.get("verification")
if not isinstance(verification_block, dict):
    verification_block = {}
visual_regression_block = verification_block.get("visual_regression")
if not isinstance(visual_regression_block, dict):
    visual_regression_block = {}
behavior_contract_block = verification_block.get("behavior_contract")
if not isinstance(behavior_contract_block, dict):
    behavior_contract_block = {}

vr_expected = visual_regression_block.get("expected")
if not isinstance(vr_expected, str) or vr_expected.strip() in NA_SENTINELS:
    vr_expected = None
else:
    vr_expected = vr_expected.strip()

vr_pages = visual_regression_block.get("pages")
if isinstance(vr_pages, list):
    vr_pages = [str(page) for page in vr_pages]
else:
    vr_pages = None

verification = {
    "visual_regression": {
        "expected": vr_expected,
        "pages": vr_pages,
    },
    "behavior_contract": behavior_contract_block,
}


# ---- first fenced code block helper --------------------------------------
def first_code_block(lns):
    in_block = False
    out = []
    for ln in lns:
        if ln.startswith("```"):
            if in_block:
                return "\n".join(out).rstrip()
            in_block = True
            continue
        if in_block:
            out.append(ln)
    return ("\n".join(out).rstrip()) if (in_block and out) else None

test_command = first_code_block(section_lines("## Test Command"))
verify_command = first_code_block(section_lines("## Verify Command"))
verify_fallback_command = first_code_block(section_lines("## Verify Fallback Command"))


# ---- Allowed Files (bullet list) -----------------------------------------
allowed_files = []
for ln in section_lines("## Allowed Files"):
    s = ln.strip()
    if s.startswith("- ") or s.startswith("* "):
        allowed_files.append(s[2:].strip())


# ---- Required Tools (markdown table) -------------------------------------
# DP-345 D1/D2: canonical handoff source for the ## Required Tools section so
# consumers (env/install-project-deps.sh) read one parser instead of each
# re-implementing a naive `text.find("## Required Tools")` that mis-fires on a
# `## Required Tools` literal inside the frontmatter description.
def parse_required_tools(lns):
    rows = []
    for raw in lns:
        s = raw.strip()
        if not s.startswith("|") or not s.endswith("|"):
            continue
        rows.append([cell.strip().strip("`") for cell in s.strip("|").split("|")])
    if not rows:
        return []

    def norm(value):
        return re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")

    aliases = {"tool": "name", "tool_name": "name", "profile": "runtime_profile"}
    headers = []
    data_rows = []
    for row in rows:
        if not headers:
            headers = [aliases.get(norm(cell), norm(cell)) for cell in row]
            continue
        if all(re.fullmatch(r":?-{3,}:?", cell.strip()) for cell in row):
            continue
        data_rows.append(row)

    tools = []
    for row in data_rows:
        values = {headers[idx]: row[idx].strip() if idx < len(row) else "" for idx in range(len(headers))}
        name = values.get("name", "").strip()
        check = values.get("check_command", "").strip()
        if not name or not check:
            continue
        install = values.get("install_command", "").strip()
        tools.append({
            "name": name,
            "owner": values.get("owner", "").strip(),
            "install_authority": values.get("install_authority", "").strip(),
            "check_command": check,
            "install_command": "" if install.upper() == "N/A" else install,
            "runtime_profile": values.get("runtime_profile", "").strip(),
            "goes_to_mise": values.get("goes_to_mise", "").strip().lower(),
            "handoff_hint": values.get("handoff_hint", "").strip(),
        })
    return tools

required_tools = parse_required_tools(section_lines("## Required Tools"))


out = {
    "task_md_path": path,
    "frontmatter": frontmatter,
    "header": header,
    "metadata": metadata,
    "identity": identity,
    "operational_context": operational_context,
    "test_environment": test_env,
    "verification": verification,
    "test_command": test_command,
    "verify_command": verify_command,
    "verify_fallback_command": verify_fallback_command,
    "allowed_files": allowed_files,
    "required_tools": required_tools,
    "resolved_base": resolved_base,
}

if not field:
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")
else:
    aliases = {
        "status":"frontmatter.status", "task_shape":"frontmatter.task_shape",
        "task_id":"header.task_id", "summary":"header.summary", "story_points":"header.story_points",
        "epic":"metadata.epic", "jira":"metadata.jira", "repo":"metadata.repo",
        "source_type":"identity.source_type", "source_id":"identity.source_id", "work_item_id":"identity.work_item_id",
        "jira_key":"identity.jira_key", "delivery_ticket_key":"identity.delivery_ticket_key",
        "task_jira_key":"operational_context.task_jira_key", "parent_epic":"operational_context.parent_epic",
        "test_sub_tasks":"operational_context.test_sub_tasks", "ac_verification_ticket":"operational_context.ac_verification_ticket",
        "base_branch":"operational_context.base_branch", "branch_chain":"operational_context.branch_chain",
        "task_branch":"operational_context.task_branch", "depends_on":"operational_context.depends_on",
        "references_to_load":"operational_context.references_to_load", "level":"test_environment.level",
        "dev_env_config":"test_environment.dev_env_config", "fixtures":"test_environment.fixtures",
        "runtime_verify_target":"test_environment.runtime_verify_target", "env_bootstrap_command":"test_environment.env_bootstrap_command",
        "verification_visual_regression_expected":"verification.visual_regression.expected",
        "verification_visual_regression_pages":"verification.visual_regression.pages",
        "verification_behavior_contract_applies":"verification.behavior_contract.applies",
        "verification_behavior_contract_mode":"verification.behavior_contract.mode",
        "verification_behavior_contract_fixture_policy":"verification.behavior_contract.fixture_policy",
        "verification_behavior_contract_flow_script":"verification.behavior_contract.flow_script",
        "test_command":"test_command", "verify_command":"verify_command", "verify_fallback_command":"verify_fallback_command",
        "allowed_files":"allowed_files", "required_tools":"required_tools", "resolved_base":"resolved_base",
    }
    for prefix, root_key in (("deliverable_", "frontmatter.deliverable."), ("deliverables_changeset_", "frontmatter.deliverables.changeset."),
                             ("extension_deliverable_", "frontmatter.extension_deliverable.")):
        pass
    aliases.update({
        "deliverable_pr_url":"frontmatter.deliverable.pr_url", "deliverable_pr_state":"frontmatter.deliverable.pr_state",
        "deliverable_head_sha":"frontmatter.deliverable.head_sha", "deliverable_verification_status":"frontmatter.deliverable.verification.status",
        "deliverable_verification_ac_total":"frontmatter.deliverable.verification.ac_counts.ac_total",
        "deliverable_verification_ac_pass":"frontmatter.deliverable.verification.ac_counts.ac_pass",
        "deliverable_verification_ac_fail":"frontmatter.deliverable.verification.ac_counts.ac_fail",
        "deliverable_verification_ac_manual_required":"frontmatter.deliverable.verification.ac_counts.ac_manual_required",
        "deliverable_verification_ac_uncertain":"frontmatter.deliverable.verification.ac_counts.ac_uncertain",
        "deliverables_changeset_package_scope":"frontmatter.deliverables.changeset.package_scope",
        "deliverables_changeset_bump_level_default":"frontmatter.deliverables.changeset.bump_level_default",
        "deliverables_changeset_filename_slug":"frontmatter.deliverables.changeset.filename_slug",
    })
    ext = {"endpoint":"endpoint","extension_id":"extension_id","task_head_sha":"task_head_sha","workspace_commit":"workspace_commit",
           "template_commit":"template_commit","version_tag":"version_tag","release_url":"release_url","completed_at":"completed_at",
           "evidence_ci_local":"evidence.ci_local","evidence_verify":"evidence.verify","evidence_vr":"evidence.vr"}
    aliases.update({f"extension_deliverable_{key}": f"frontmatter.extension_deliverable.{value}" for key, value in ext.items()})
    if field not in aliases:
        die(f"unknown field: {field}", 1)
    value = out
    for key in aliases[field].split("."):
        value = value.get(key) if isinstance(value, dict) else None
    if value is not None:
        if isinstance(value, list):
            print("\n".join(str(item) for item in value))
        elif isinstance(value, bool):
            print(str(value).lower())
        elif isinstance(value, (dict, list)):
            print(json.dumps(value, ensure_ascii=False))
        else:
            print(value)
