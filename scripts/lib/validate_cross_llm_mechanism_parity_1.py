"""Structured validator authority extracted from scripts/validate-cross-llm-mechanism-parity.sh."""

import hashlib
import json
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
specs_root = Path(sys.argv[2]).resolve()

errors = []  # (hook_token, message)


def fail(hook, message):
    errors.append((hook, message))


def die_now():
    for hook, message in errors:
        print(f"POLARIS_CROSS_LLM_PARITY_BLOCKED:{hook} {message}", file=sys.stderr)
    sys.exit(2)


settings_path = repo / ".claude" / "settings.json"
settings_local_path = repo / ".claude" / "settings.local.json"
registry_path = repo / ".claude" / "rules" / "mechanism-registry.md"
hooks_dir = repo / ".claude" / "hooks"

if not settings_path.is_file():
    fail("settings", f"missing .claude/settings.json under {repo}")
    die_now()
if not registry_path.is_file():
    fail("registry", "missing .claude/rules/mechanism-registry.md")
    die_now()


def load_json(path):
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # noqa: BLE001
        fail(path.name, f"unreadable JSON: {exc}")
        die_now()


settings = load_json(settings_path)
settings_local = load_json(settings_local_path) if settings_local_path.is_file() else {}

# ---- active hook command parser (all event families) ----
CANONICAL_RE = re.compile(
    r'^bash\s+"(?:\$CLAUDE_PROJECT_DIR/|[^"]*/)?\.claude/hooks/([A-Za-z0-9._-]+\.sh)"\s*$'
)
NON_CANONICAL_TOKENS = (
    "&&",
    "||",
    ";",
    "|",
    "`",
    "$(",
    " > ",
    " < ",
    ">>",
    "bash -lc",
    "bash -c",
    " -lc",
)


def active_commands_from(source_obj, source_label):
    hooks_block = source_obj.get("hooks")
    if not hooks_block:
        return
    if not isinstance(hooks_block, dict):
        fail(source_label, "hooks block must be an object")
        return
    for event_family, matchers in hooks_block.items():
        if not isinstance(matchers, list):
            continue
        for matcher_entry in matchers:
            for hook_entry in (matcher_entry or {}).get("hooks", []) or []:
                command = (hook_entry or {}).get("command", "")
                if isinstance(command, str) and command.strip():
                    yield (command.strip(), source_label, event_family)


active_commands = list(active_commands_from(settings, "settings.json")) + list(
    active_commands_from(settings_local, "settings.local.json")
)

active_hook_names = set()
for command, source_label, event_family in active_commands:
    env_injected = re.match(r"^[A-Za-z_][A-Za-z0-9_]*=\S", command)
    has_non_canonical = (
        any(tok in command for tok in NON_CANONICAL_TOKENS) or env_injected
    )
    m = CANONICAL_RE.match(command)
    if has_non_canonical or not m:
        fail(
            "non-canonical-hook-command",
            f"{source_label} {event_family} active command is not a single .claude/hooks/*.sh "
            f"invocation: {command}",
        )
        continue
    hook_name = m.group(1)
    if not (hooks_dir / hook_name).is_file():
        fail(hook_name, f"{source_label} {event_family} active hook missing on disk")
        continue
    active_hook_names.add(hook_name)

# ---- Cross-LLM Hook Parity Registry table ----
PARITY_SECTION = "## Cross-LLM Hook Parity Registry"


def parse_table(text, section_header):
    capture = False
    section = []
    for line in text.splitlines():
        if line.strip() == section_header:
            capture = True
            continue
        if capture and line.startswith("## "):
            break
        if capture:
            section.append(line)
    rows = []
    for line in section:
        s = line.strip()
        if not s.startswith("|"):
            continue
        cells = [c.strip().strip("`") for c in s.strip("|").split("|")]
        if cells and all(re.fullmatch(r":?-{3,}:?", c.replace(" ", "")) for c in cells):
            continue
        rows.append(cells)
    return rows


rows = parse_table(registry_path.read_text(), PARITY_SECTION)
if len(rows) < 2:
    fail("registry", f"missing or empty '{PARITY_SECTION}' table")
    die_now()

header = [c.lower() for c in rows[0]]
required_cols = [
    "hook",
    "runtime",
    "fallback_script",
    "codex_adapter",
    "codex_invocation_point",
    "adapter_selftest",
    "payload_contract",
    "golden_fixture",
    "parity_exception",
]
missing_cols = [c for c in required_cols if c not in header]
if missing_cols:
    fail("registry", f"parity table missing columns: {', '.join(missing_cols)}")
    die_now()

idx = {c: header.index(c) for c in required_cols}
registry_by_hook = {}
for row_no, row in enumerate(rows[1:], start=2):
    if len(row) < len(header):
        fail("registry", f"row {row_no}: malformed parity row")
        continue
    hook = row[idx["hook"]].strip()
    if not hook:
        fail("registry", f"row {row_no}: hook is empty")
        continue
    registry_by_hook[hook] = {c: row[idx[c]].strip() for c in required_cols}

VALID_INVOCATION = {"codex_hook", "guarded_wrapper", "pr_gate"}
INVALID_INVOCATION = {"manual", "skill_prose", "", "N/A", "-"}


def exists(rel):
    rel = rel.strip().strip("`")
    if not rel or rel in ("N/A", "-"):
        return False
    return (repo / rel).exists()


def file_text(rel):
    p = repo / rel.strip().strip("`")
    return p.read_text() if p.is_file() else ""


def parity_exception_valid(token):
    m = re.match(r"^(DP-\d+):(.+)$", token.strip())
    if not m:
        return False, "parity_exception must be DP-NNN:<reason>"
    dp = m.group(1)
    plans_dir = specs_root / "docs-manager/src/content/docs/specs/design-plans"
    # docs-manager specs are local planning artifacts and may be absent from a task
    # worktree / CI runner. When the design-plans tree itself is not present, the
    # carve-out token is accepted as syntactically valid; the main-checkout PR gate
    # (where specs are present) enforces the recorded reason. When the tree IS
    # present, the owning DP plan must exist and record a parity reason.
    if not plans_dir.is_dir():
        return True, ""
    plans = list(plans_dir.glob(f"{dp}-*/index.md"))
    if not plans:
        # Released DPs archive their own container under design-plans/archive/;
        # archive is a normal lifecycle state, so fall back to the archive tree
        # before declaring the owning DP plan missing. The recorded-reason check
        # below still applies to archived plans (archive does not bypass it).
        archive_dir = plans_dir / "archive"
        if archive_dir.is_dir():
            plans = list(archive_dir.glob(f"{dp}-*/index.md"))
    if not plans:
        return False, f"parity_exception owning DP plan not found: {dp}"
    plan_text = "".join(p.read_text() for p in plans)
    if dp not in plan_text or "parity" not in plan_text.lower():
        return False, f"owning DP plan {dp} lacks recorded parity carve-out reason"
    return True, ""


codex_config_text = file_text(".codex/config.toml")


def hook_delegates_fallback(hook_name, fallback):
    return Path(fallback).name in file_text(f".claude/hooks/{hook_name}")


# Decision fields that must survive Claude->Codex payload normalization.
DECISION_FIELDS = [
    "tool_name",
    "matcher",
    "tool_input.path",
    "changed_paths",
    "session_id",
    "transcript",
    "cwd",
    "env_carve_out_token",
]


def deep_get(obj, dotted):
    cur = obj
    for part in dotted.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def normalized_digest(payload):
    norm = {f: deep_get(payload, f) for f in DECISION_FIELDS}
    blob = json.dumps(norm, sort_keys=True, ensure_ascii=True)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def golden_digest_parity(hook_name, reg):
    """Golden fixture is JSON: {claude_payload, codex_payload, fallback_decision}.
    Claude and Codex normalized decision-field digests must match, and both must
    carry the same fallback PASS/FAIL decision."""
    rel = reg["golden_fixture"]
    p = repo / rel.strip().strip("`")
    try:
        data = json.loads(p.read_text())
    except Exception as exc:  # noqa: BLE001
        return f"golden_fixture unreadable JSON: {exc}"
    claude_payload = data.get("claude_payload")
    codex_payload = data.get("codex_payload")
    decision = data.get("fallback_decision")
    if claude_payload is None or codex_payload is None:
        return "golden_fixture missing claude_payload / codex_payload"
    if decision not in ("PASS", "FAIL"):
        return "golden_fixture fallback_decision must be PASS or FAIL"
    cd = normalized_digest(claude_payload)
    xd = normalized_digest(codex_payload)
    if cd != xd:
        return "normalized decision-field digest mismatch between Claude and Codex payloads"
    # PASS/FAIL parity is recorded once and must apply to both runtimes; mismatch
    # is expressed as differing per-runtime decisions in the fixture.
    cdec = data.get("claude_decision", decision)
    xdec = data.get("codex_decision", decision)
    if cdec != xdec:
        return "fallback PASS/FAIL mismatch between Claude and Codex runtimes"
    return ""


for hook_name in sorted(active_hook_names):
    reg = registry_by_hook.get(hook_name)
    if reg is None:
        fail(hook_name, "active hook has no Cross-LLM Hook Parity Registry entry")
        continue

    parity_exc = reg["parity_exception"]
    if parity_exc and parity_exc not in ("N/A", "-"):
        ok, why = parity_exception_valid(parity_exc)
        if not ok:
            fail(hook_name, why)
        continue  # valid carve-out short-circuits remaining parity checks

    runtime = reg["runtime"]
    if runtime not in ("portable", "claude-code-only"):
        fail(hook_name, f"unsupported runtime: {runtime}")
        continue

    fallback = reg["fallback_script"]
    if not fallback or fallback in ("N/A", "-"):
        fail(hook_name, "missing fallback_script")
    elif not exists(fallback):
        fail(hook_name, f"fallback_script missing on disk: {fallback}")
    elif not hook_delegates_fallback(hook_name, fallback):
        fail(
            hook_name,
            f"active hook does not delegate declared fallback_script: {fallback}",
        )

    inv = reg["codex_invocation_point"]
    if inv in INVALID_INVOCATION or inv not in VALID_INVOCATION:
        fail(
            hook_name,
            f"codex_invocation_point must be codex_hook/guarded_wrapper/pr_gate, got: {inv!r}",
        )
        continue

    adapter = reg["codex_adapter"]
    if not exists(adapter):
        fail(hook_name, f"codex_adapter target missing on disk: {adapter}")
    if not exists(reg["adapter_selftest"]):
        fail(hook_name, f"adapter_selftest missing on disk: {reg['adapter_selftest']}")
    if not exists(reg["payload_contract"]):
        fail(hook_name, f"payload_contract missing on disk: {reg['payload_contract']}")
    if not exists(reg["golden_fixture"]):
        fail(hook_name, f"golden_fixture missing on disk: {reg['golden_fixture']}")
        continue

    if inv == "codex_hook":
        if Path(adapter).name not in codex_config_text:
            fail(
                hook_name,
                "codex_hook adapter not actively registered in .codex/config.toml",
            )
    else:  # guarded_wrapper / pr_gate
        ct = file_text(adapter)
        if (
            fallback
            and Path(fallback).name not in ct
            and "validate-cross-llm-mechanism-parity" not in ct
        ):
            fail(
                hook_name, f"{inv} callsite does not invoke adapter/fallback: {adapter}"
            )

    digest_err = golden_digest_parity(hook_name, reg)
    if digest_err:
        fail(hook_name, digest_err)

if errors:
    die_now()
