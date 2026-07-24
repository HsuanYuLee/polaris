"""Validate task.md files and expose focused structured-validation helpers."""

from __future__ import annotations

import argparse
import sys

_raw_args = sys.argv[1:]
_helper_commands = {
    "snapshot",
    "smoke",
    "required-tools",
    "vr-state",
    "behavior-contract",
    "summary-language",
}
_parser = argparse.ArgumentParser(
    add_help=False,
    allow_abbrev=False,
    usage=(
        "validate-task-md.sh <path/to/task.md> | "
        "--snapshot <baseline-snapshot.json> <path/to/task.md> | "
        "--scan <workspace_root>"
    ),
)
_mode = _parser.add_mutually_exclusive_group()
_mode.add_argument("--snapshot", action="store_true")
_mode.add_argument("--scan", action="store_true")
_parser.add_argument("-h", "--help", action="store_true")
_parser.add_argument("arguments", nargs="*")
_parsed = _parser.parse_args(_raw_args)
if _parsed.help:
    _parser.print_usage(sys.stderr)
    raise SystemExit(2)

if _parsed.snapshot:
    command = "snapshot"
    expected_arity = 2
elif _parsed.scan:
    command = "scan"
    expected_arity = 1
elif _parsed.arguments and _parsed.arguments[0] in _helper_commands:
    command = _parsed.arguments.pop(0)
    expected_arity = 3 if command == "smoke" else 1
elif _parsed.arguments:
    command = "validate"
    expected_arity = 1
else:
    _parser.error("a task path or mode is required")

if command == "smoke" and len(_parsed.arguments) == 2:
    pass
elif len(_parsed.arguments) != expected_arity:
    _parser.error(f"{command} expects {expected_arity} argument(s)")
sys.argv = [sys.argv[0], *_parsed.arguments]
if command == "snapshot":
    import hashlib
    import json
    import re
    import sys
    from pathlib import Path

    snapshot_path = Path(sys.argv[1])
    task_path = Path(sys.argv[2])

    if not task_path.is_file():
        print(f"task.md not found: {task_path}", file=sys.stderr)
        raise SystemExit(2)

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
elif command == "smoke":
    import os
    import re
    import shlex
    import subprocess
    import sys
    import tempfile
    from pathlib import Path
    from urllib.parse import urlparse

    from validate_safe_cli_introspection_1 import (
        UnsafeScriptPathError,
        classify_script_for_introspection,
        run_bounded_command,
    )

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

    def script_supported_flags(script: Path, display_path: str):
        try:
            result = run_bounded_command(
                ["bash", str(script), "--help"],
                cwd=repo_root,
                timeout_seconds=5.0,
            )
        except OSError as exc:
            errors.append(
                "POLARIS_VERIFY_COMMAND_INTROSPECTION_FAILED:"
                f"{display_path}:{exc}"
            )
            return None
        if result.timed_out:
            errors.append(
                "POLARIS_VERIFY_COMMAND_INTROSPECTION_TIMEOUT:"
                f"{display_path}:process group terminated"
            )
            return None
        if result.returncode not in (0, 2):
            errors.append(
                "POLARIS_VERIFY_COMMAND_INTROSPECTION_FAILED:"
                f"{display_path}:exit={result.returncode}"
            )
            return None
        help_text = f"{result.stdout}\n{result.stderr}"
        flags = set(re.findall(r"(?<!\w)--[A-Za-z][A-Za-z0-9_-]*", help_text))
        return flags

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
        used = []
        for token in tokens[script_idx + 1:]:
            if token == "--":
                break
            if token.startswith("--"):
                used.append(token.split("=", 1)[0])
        try:
            script_class = classify_script_for_introspection(
                script,
                tokens[script_idx],
                repo_root,
            )
        except UnsafeScriptPathError as exc:
            errors.append(
                "POLARIS_VERIFY_COMMAND_INVALID_SCRIPT_PATH:"
                f"{tokens[script_idx]}:{exc} (line: {line})"
            )
            return
        if script_class == "test":
            return
        if script_class == "non_cli":
            if used:
                unsupported_diagnostics = ", ".join(
                    f"unsupported flag {flag}" for flag in used
                )
                errors.append(
                    "POLARIS_VERIFY_COMMAND_UNSAFE_INTROSPECTION:"
                    f"{tokens[script_idx]}:{unsupported_diagnostics}; "
                    f"cannot validate flags {', '.join(used)} "
                    f"without the canonical safe CLI help prefix (line: {line})"
                )
            return
        if not used:
            return
        supported = script_supported_flags(script, tokens[script_idx])
        if supported is None:
            return
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
        # DP-445 governs Verify Command introspection. Env bootstrap validation
        # shares this smoke primitive only for command-shape checks; it must not
        # execute or reclassify bootstrap scripts as an incidental side effect.
        if kind == "verify_command":
            if tokens and tokens[0] == "bash" and len(tokens) > 1:
                smoke_script_flags(line, tokens)
            elif tokens and tokens[0].startswith("scripts/") and tokens[0].endswith(".sh"):
                smoke_script_flags(line, tokens)
        smoke_rg_pattern(line, tokens)

    # DP-369 GapA: env_bootstrap executability — first-token command-shape check.
    # Reuses this primitive's command_lines/shlex tokenizer (no second parser).
    # Goal: prose env_bootstrap (e.g. "啟動 app.example.test 三層 stack ...") fails LOCK,
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
elif command == "required-tools":
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
elif command == "vr-state":
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
elif command == "behavior-contract":
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
elif command in {"validate", "scan"}:
    import json
    import re
    import subprocess
    from pathlib import Path
    from urllib.parse import urlparse

    MODULE = Path(__file__).resolve()
    STATUS_VALUES = {"PLANNED", "IN_PROGRESS", "BLOCKED", "IMPLEMENTED", "ABANDONED"}
    NA_VALUES = {"", "n/a", "-", "none", "無"}
    ISO_RE = re.compile(
        r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"
        r"(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:?[0-9]{2})?$"
    )

    def usage() -> int:
        print(
            f"usage: {MODULE.parent.parent / 'validate-task-md.sh'} <path/to/task.md>\n"
            f"       {MODULE.parent.parent / 'validate-task-md.sh'} --snapshot <baseline-snapshot.json> <path/to/task.md>\n"
            f"       {MODULE.parent.parent / 'validate-task-md.sh'} --scan <workspace_root>",
            file=sys.stderr,
        )
        return 2

    def strip_quotes(value: str) -> str:
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            return value[1:-1]
        return value

    def frontmatter_lines(text: str) -> list[str]:
        lines = text.splitlines()
        if not lines or lines[0].strip() != "---":
            return []
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                return lines[1:index]
        return []

    def frontmatter_scalar(lines: list[str], key: str) -> str:
        prefix = f"{key}:"
        for raw in lines:
            if raw[:1].isspace() or not raw.startswith(prefix):
                continue
            return strip_quotes(raw.split(":", 1)[1].strip())
        return ""

    def frontmatter_has(lines: list[str], key: str) -> bool:
        return any(not raw[:1].isspace() and raw.startswith(f"{key}:") for raw in lines)

    def top_block(lines: list[str], key: str) -> list[str]:
        start = None
        for index, raw in enumerate(lines):
            if not raw[:1].isspace() and raw.rstrip() == f"{key}:":
                start = index + 1
                break
        if start is None:
            return []
        end = len(lines)
        for index in range(start, len(lines)):
            raw = lines[index]
            if raw and not raw[:1].isspace() and not raw.lstrip().startswith("#"):
                end = index
                break
        return lines[start:end]

    def indented_scalar(lines: list[str], key: str, indent: int | None = None) -> str:
        pattern = re.compile(rf"^(\s+){re.escape(key)}:\s*(.*?)\s*$")
        for raw in lines:
            match = pattern.match(raw)
            if not match:
                continue
            if indent is not None and len(match.group(1)) != indent:
                continue
            return strip_quotes(match.group(2))
        return ""

    def nested_block(lines: list[str], key: str, indent: int) -> list[str]:
        prefix = " " * indent + key + ":"
        start = None
        for index, raw in enumerate(lines):
            if raw.rstrip() == prefix:
                start = index + 1
                break
        if start is None:
            return []
        end = len(lines)
        for index in range(start, len(lines)):
            raw = lines[index]
            if not raw.strip():
                continue
            current_indent = len(raw) - len(raw.lstrip(" "))
            if current_indent <= indent:
                end = index
                break
        return lines[start:end]

    def body_without_frontmatter(text: str) -> str:
        lines = text.splitlines()
        if not lines or lines[0].strip() != "---":
            return text
        for index in range(1, len(lines)):
            if lines[index].strip() == "---":
                return "\n".join(lines[index + 1 :])
        return text

    def section(text: str, heading: str) -> str:
        marker = f"## {heading}"
        lines = body_without_frontmatter(text).splitlines()
        start = None
        for index, raw in enumerate(lines):
            if raw == marker:
                start = index + 1
                break
        if start is None:
            return ""
        end = len(lines)
        for index in range(start, len(lines)):
            if lines[index].startswith("## "):
                end = index
                break
        return "\n".join(lines[start:end])

    def has_heading(text: str, heading: str) -> bool:
        return any(raw == f"## {heading}" for raw in body_without_frontmatter(text).splitlines())

    def first_fence(block: str) -> str:
        match = re.search(r"^```[^\n]*\n(.*?)^```\s*$", block, re.MULTILINE | re.DOTALL)
        return match.group(1) if match else ""

    def op_field(text: str, field: str) -> str:
        for raw in text.splitlines():
            if not raw.startswith("|"):
                continue
            cells = raw.split("|")
            if len(cells) >= 4 and cells[1].strip() == field:
                return cells[2].strip()
        return ""

    def header_token(text: str, label: str) -> str:
        for raw in text.splitlines():
            if not raw.startswith("> "):
                continue
            for part in raw.split("|"):
                cleaned = re.sub(r"^>\s*", "", part).strip()
                if cleaned.startswith(f"{label}:"):
                    return cleaned.split(":", 1)[1].strip()
        return ""

    def is_na(value: str) -> bool:
        return value.strip().lower() in NA_VALUES

    def valid_source_work_item(value: str) -> bool:
        return bool(re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+-[TV][0-9]+[a-z]*", value))

    def valid_jira(value: str) -> bool:
        return bool(re.fullmatch(r"[A-Z][A-Z0-9]*-[0-9]+", value))

    def valid_identity(value: str) -> bool:
        return valid_jira(value) or valid_source_work_item(value)

    def helper(name: str, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(MODULE), name, *args],
            capture_output=True,
            text=True,
            check=False,
        )

    def docs_manager_page(text: str, target: str) -> bool:
        parsed = urlparse(target)
        if (parsed.hostname or "").lower() in {"127.0.0.1", "localhost"} and parsed.port == 8080:
            return True
        allowed = section(text, "Allowed Files")
        paths = re.findall(r"docs-manager/src/content/docs/[^\s`<>\)]+", allowed)
        return any(not path.startswith("docs-manager/src/content/docs/specs/") for path in paths)

    def list_shape_error(fm: list[str], key: str, label: str) -> str:
        for index, raw in enumerate(fm):
            if not raw.startswith(f"{key}:"):
                continue
            inline = raw.split(":", 1)[1].strip()
            if inline not in {"", "[]", "~", "null"}:
                return f"{label} must be a YAML list (array), not a scalar (got inline value: '{inline}')"
            for item in fm[index + 1 :]:
                if item and not item[:1].isspace():
                    break
                match = re.match(r"^\s+-\s+(.+)$", item)
                if match and ":" not in match.group(1):
                    bad = f"bare scalar entry: {match.group(1)}"
                    return f"{label} entries must be YAML maps (key: value), not bare scalars ({bad})"
            break
        return ""

    def validate_one(path: Path, emit: bool = True) -> tuple[int, str]:
        if not path.is_file():
            diagnostic = f"error: file not found: {path}"
            if emit:
                print(diagnostic, file=sys.stderr)
            return 2, diagnostic
        posix_path = path.as_posix()
        if "/tasks/pr-release/" in posix_path:
            return 0, ""
        text = path.read_text(encoding="utf-8", errors="replace")
        fm = frontmatter_lines(text)
        effective_name = path.parent.name + ".md" if path.name == "index.md" else path.name
        mode = "V" if re.fullmatch(r"V[0-9].*\.md", effective_name) else "T"
        verify_heading = "驗收步驟" if mode == "V" else "Verify Command"
        errors: list[str] = []
        warnings: list[str] = []

        status = frontmatter_scalar(fm, "status")
        if not status:
            errors.append("frontmatter status is required; use PLANNED, IN_PROGRESS, BLOCKED, IMPLEMENTED, or ABANDONED")
        elif status not in STATUS_VALUES:
            errors.append(
                "frontmatter status must be PLANNED|IN_PROGRESS|BLOCKED|IMPLEMENTED|ABANDONED "
                f"(got: '{status}')"
            )
        if status == "IMPLEMENTED":
            diagnostic = (
                f"✗✗ HARD FAIL (exit 2) — task.md completion invariant violated in {path}:\n"
                "   frontmatter 'status: IMPLEMENTED' but file is NOT in tasks/pr-release/.\n"
                "   Fix: run 'scripts/mark-spec-implemented.sh' (move-first: mv tasks/T.md tasks/pr-release/T.md → update frontmatter).\n"
                "   Reference: skills/references/task-md-schema.md § 5.5 + DP-033 D6"
            )
            if emit:
                print(diagnostic, file=sys.stderr)
            return 2, diagnostic

        task_shape = "implementation"
        if frontmatter_has(fm, "task_shape"):
            declared_shape = frontmatter_scalar(fm, "task_shape")
            if declared_shape in {"implementation", "audit", "confirmation"}:
                task_shape = declared_shape
            else:
                errors.append(
                    "frontmatter task_shape must be implementation|audit|confirmation "
                    f"(got: '{declared_shape}')"
                )

        title_re = re.compile(r"^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)", re.MULTILINE)
        if not title_re.search(text):
            errors.append(
                "missing or malformed title: expected '# T{n}[suffix]: {summary} ({SP} pt)' — "
                r"regex: ^# (T|V)[0-9]+[a-z]*: .+\([0-9.]+ ?pt\)"
            )
        else:
            result = helper("summary-language", str(path))
            if result.returncode:
                errors.extend(line for line in result.stderr.splitlines() if line)

        header_jira = header_token(text, "JIRA")
        header_task = header_token(text, "Task")
        if header_task:
            if not valid_identity(header_task):
                errors.append(
                    f"invalid Task identity in metadata line: got '{header_task}' "
                    "(expected JIRA key like PROJ-123 or source work item like DP-047-T1 / BUG-123-T1)"
                )
            if header_jira and not is_na(header_jira) and not valid_jira(header_jira):
                errors.append(
                    f"invalid JIRA key in metadata line: got '{header_jira}' "
                    "(expected real JIRA key like PROJ-123 or N/A for DP-backed task)"
                )
        elif not header_jira:
            errors.append("missing task identity in metadata line: expected legacy 'JIRA: {KEY}' or canonical 'Task: {ID}'")
        elif not valid_identity(header_jira):
            errors.append(
                f"invalid task identity in metadata line: got '{header_jira}' "
                "(expected JIRA key like PROJ-123 or legacy source work item like DP-047-T1 / BUG-123-T1)"
            )
        if not re.search(r"^> .*Repo: \S+", text, re.MULTILINE):
            errors.append("missing Repo in metadata line: expected '> ... | Repo: {repo_name}'")
        if not re.search(r"^> .*Epic: \S+", text, re.MULTILINE) and not re.search(
            r"^> .*Source: \S+", text, re.MULTILINE
        ):
            warnings.append("metadata line missing 'Epic:' cell — Soft required (Bug tasks may omit; warn only)")

        if mode == "T":
            hard = ["Operational Context", "改動範圍", "Allowed Files", "估點理由", "Test Command", "Test Environment"]
            soft = ["目標", "測試計畫（code-level）"]
        else:
            hard = ["Operational Context", "驗收項目", "估點理由", "Test Environment"]
            soft = ["目標", "驗收計畫（AC level）"]
        for heading in hard:
            if not has_heading(text, heading):
                errors.append(f"missing Hard required section: ## {heading}")
        for heading in soft:
            if not has_heading(text, heading):
                warnings.append(f"missing Soft required section: ## {heading} (warn only — presence expected but not enforced)")

        def check_nonempty(heading: str) -> None:
            if not has_heading(text, heading):
                return
            content = [raw for raw in section(text, heading).splitlines() if raw.strip() and not raw.lstrip().startswith(">")]
            if not content:
                errors.append(f"section '## {heading}' body is empty (Hard required — must have at least 1 non-comment line)")

        if mode == "T":
            check_nonempty("改動範圍")
        elif has_heading(text, "驗收項目"):
            rows = [raw for raw in section(text, "驗收項目").splitlines() if raw.lstrip().startswith(("|", "-"))]
            if not rows:
                errors.append("section '## 驗收項目' has no AC entries (Hard required — must have at least one markdown row '|' or bullet '- ')")
        check_nonempty("估點理由")

        if mode == "T" and has_heading(text, "Allowed Files"):
            if not any(raw.lstrip().startswith("-") for raw in section(text, "Allowed Files").splitlines()):
                errors.append("section '## Allowed Files' has no bullet list entries (Hard required — must have at least one '- ' bullet; A7 migration script can backfill)")
        if mode == "T" and has_heading(text, "Required Tools"):
            result = helper("required-tools", str(path))
            errors.extend(line for line in result.stdout.splitlines() if line)

        if has_heading(text, "Operational Context"):
            identity = op_field(text, "Task ID") or op_field(text, "Task JIRA key")
            if not identity:
                errors.append("Operational Context section missing task identity value (expected canonical 'Task ID' or legacy 'Task JIRA key')")
            elif not valid_identity(identity):
                errors.append(
                    f"Operational Context task identity has invalid value '{identity}' "
                    "(expected JIRA key like PROJ-123 or source work item like DP-047-T1 / BUG-123-T1)"
                )
            canonical = any(op_field(text, field) for field in ("Task ID", "Source type", "Source ID", "JIRA key"))
            if canonical:
                source_type = op_field(text, "Source type")
                source_id = op_field(text, "Source ID")
                jira_cell = op_field(text, "JIRA key")
                if source_type not in {"dp", "jira", "bug"}:
                    errors.append(f"Operational Context canonical identity requires Source type = dp|jira|bug (got: '{source_type or '<empty>'}')")
                if not source_id:
                    errors.append("Operational Context canonical identity missing Source ID")
                if not op_field(text, "Task ID"):
                    errors.append("Operational Context canonical identity missing Task ID")
                if not jira_cell:
                    errors.append("Operational Context canonical identity missing JIRA key cell (use N/A when absent)")
                elif not is_na(jira_cell) and not valid_jira(jira_cell):
                    errors.append(f"Operational Context JIRA key must be a real JIRA key or N/A (got: '{jira_cell}')")
                elif source_type == "jira" and is_na(jira_cell):
                    errors.append(f"Operational Context source_type=jira requires a real JIRA key (got: '{jira_cell}')")
            else:
                if not op_field(text, "Task JIRA key"):
                    errors.append("Operational Context legacy identity missing Task JIRA key")
                if not op_field(text, "Parent Epic"):
                    errors.append("Operational Context legacy identity missing Parent Epic")
            cells = (
                ["Test sub-tasks", "AC 驗收單", "Base branch", "Task branch", "References to load"]
                if mode == "T"
                else ["Implementation tasks", "Base branch", "References to load"]
            )
            for cell in cells:
                if cell not in text:
                    errors.append(f"missing Hard required Operational Context cell: '{cell}'")
            if "Depends on" not in text:
                warnings.append("Operational Context missing 'Depends on' cell (Soft — N/A is valid; warn only)")

        level = ""
        target = ""
        bootstrap = ""
        if has_heading(text, "Test Environment"):
            level_match = re.search(r"^(?:- )?\*\*Level\*\*:\s*(\S+)", text, re.MULTILINE)
            if not level_match:
                errors.append("Test Environment section missing 'Level' field (expected '- **Level**: {static|build|runtime}')")
            else:
                level = level_match.group(1).lower().rstrip("\r")
                if level not in {"static", "build", "runtime"}:
                    errors.append(f"Test Environment 'Level' must be one of {{static, build, runtime}} (got: '{level}')")
                    level = ""
            target_match = re.search(r"^(?:- )?\*\*Runtime verify target\*\*:\s*(.*?)\s*$", text, re.MULTILINE)
            bootstrap_match = re.search(r"^(?:- )?\*\*Env bootstrap command\*\*:\s*(.*?)\s*$", text, re.MULTILINE)
            if not target_match:
                errors.append("Test Environment missing 'Runtime verify target' field (expected '- **Runtime verify target**: {url|N/A}')")
            else:
                target = target_match.group(1).strip()
            if not bootstrap_match:
                errors.append("Test Environment missing 'Env bootstrap command' field (expected '- **Env bootstrap command**: {command|N/A}')")
            else:
                bootstrap = bootstrap_match.group(1).strip()

            normalized_target = target.strip("`").strip()
            normalized_bootstrap = bootstrap.strip("`").strip()
            if level == "runtime":
                if is_na(normalized_target):
                    errors.append(f"Level=runtime requires non-N/A Runtime verify target (got: '{normalized_target or '<empty>'}')")
                elif urlparse(normalized_target).scheme not in {"http", "https"}:
                    errors.append(f"Level=runtime requires Runtime verify target to be an http/https URL (got: '{normalized_target}')")
                if is_na(normalized_bootstrap):
                    errors.append("Level=runtime requires non-N/A Env bootstrap command")
                if has_heading(text, verify_heading):
                    verify_cmd = first_fence(section(text, verify_heading))
                    if not verify_cmd.strip():
                        errors.append(f"## {verify_heading} fenced code block is empty (Level=runtime requires a live endpoint URL inside)")
                    else:
                        match = re.search(r"https?://[^\s\"'\)]+", verify_cmd)
                        if not match:
                            errors.append("Level=runtime requires Verify Command fenced block to contain a live http/https endpoint URL")
                        else:
                            verify_url = match.group(0)
                            target_host = (urlparse(normalized_target).hostname or "").lower()
                            verify_host = (urlparse(verify_url).hostname or "").lower()
                            if not target_host or not verify_host:
                                errors.append(f"unable to parse host from Runtime verify target ('{normalized_target}') or Verify Command URL ('{verify_url}')")
                            elif target_host != verify_host:
                                errors.append(f"Level=runtime: Verify Command URL host ({verify_host}) must match Runtime verify target host ({target_host}) — DP-023 Target-first rule")
                            if docs_manager_page(text, normalized_target):
                                if not urlparse(normalized_target).path.startswith("/docs-manager/"):
                                    errors.append(f"docs-manager runtime target must include /docs-manager/ path (got: '{normalized_target}')")
                                if not urlparse(verify_url).path.startswith("/docs-manager/"):
                                    errors.append(f"docs-manager Verify Command URL must include /docs-manager/ path (got: '{verify_url}')")
            elif level == "static":
                if normalized_target and not is_na(normalized_target):
                    errors.append(f"Level=static expects Runtime verify target = N/A (got: '{normalized_target}') — avoid false declarations")
                if normalized_bootstrap and not is_na(normalized_bootstrap):
                    errors.append(f"Level=static expects Env bootstrap command = N/A (got: '{normalized_bootstrap}') — avoid false declarations")
            elif level == "build" and normalized_target and not is_na(normalized_target):
                errors.append(f"Level=build expects Runtime verify target = N/A (got: '{normalized_target}') — build gates should not declare live endpoints")
            if level in {"runtime", "build"} and normalized_bootstrap and not is_na(normalized_bootstrap):
                result = helper("smoke", str(path), normalized_bootstrap, "env_bootstrap")
                if result.returncode:
                    errors.extend(line for line in result.stdout.splitlines() if line)

        vr_result = helper("vr-state", str(path))
        try:
            vr = json.loads(vr_result.stdout or "{}")
        except json.JSONDecodeError:
            vr = {}
        if vr.get("present"):
            if not vr.get("is_map"):
                errors.append("frontmatter verification.visual_regression must be a map with expected and pages")
            expected = vr.get("expected")
            if not vr.get("expected_is_string") or not expected:
                errors.append("frontmatter verification.visual_regression.expected is required")
            elif expected not in {"none_allowed", "baseline_required", "update_baseline"}:
                errors.append(f"frontmatter verification.visual_regression.expected must be none_allowed, baseline_required, or update_baseline (got: '{expected}')")
            if not vr.get("pages_present"):
                errors.append("frontmatter verification.visual_regression.pages is required; use [] to select workspace-config pages")
            elif not vr.get("pages_is_list"):
                errors.append("frontmatter verification.visual_regression.pages must be a YAML list")
            if level != "runtime":
                errors.append(f"frontmatter verification.visual_regression requires Test Environment Level=runtime (got: '{level or '<empty>'}')")

        result = helper("behavior-contract", str(path))
        errors.extend(line for line in result.stdout.splitlines() if line)
        if mode == "T" and has_heading(text, "Verify Command"):
            verify_cmd = first_fence(section(text, "Verify Command"))
            if verify_cmd:
                result = helper("smoke", str(path), verify_cmd, "verify_command")
                if result.returncode:
                    errors.extend(line for line in result.stdout.splitlines() if line)

        if level and level != "static":
            if not has_heading(text, verify_heading):
                errors.append(f"missing Hard required section: ## {verify_heading} (required when Level={level})")
            elif not re.sub(r"\s+", "", first_fence(section(text, verify_heading))):
                errors.append(f"## {verify_heading} section missing executable fenced code block (required when Level={level})")
        elif not level and has_heading(text, verify_heading) and not re.sub(r"\s+", "", first_fence(section(text, verify_heading))):
            errors.append(f"## {verify_heading} section missing executable fenced code block")
        if mode == "T" and has_heading(text, "Test Command") and not re.sub(r"\s+", "", first_fence(section(text, "Test Command"))):
            errors.append("## Test Command section missing executable fenced code block")

        if mode == "T" and not is_na(op_field(text, "Depends on")):
            base = op_field(text, "Base branch")
            if not base or not base.startswith("task/"):
                errors.append(f"DP-028 cross-field: 'Depends on' is non-empty but 'Base branch' is not a task/ branch (got: '{base or '<empty>'}')")

        if mode == "T" and frontmatter_has(fm, "deliverable"):
            block = top_block(fm, "deliverable")
            pr_url = indented_scalar(block, "pr_url", 2)
            pr_state = indented_scalar(block, "pr_state", 2)
            head_sha = indented_scalar(block, "head_sha", 2)
            verification = nested_block(block, "verification", 2)
            verification_status = indented_scalar(verification, "status", 4)
            pr_present = any(re.match(r"^  pr_(?:url|state):", raw) for raw in block)
            if task_shape in {"audit", "confirmation"}:
                if pr_present:
                    errors.append(f"deliverable for task_shape {task_shape} must not contain pr_url or pr_state")
                if verification_status != "PASS":
                    errors.append(f"deliverable.verification.status must be PASS for task_shape {task_shape} (got: '{verification_status or '<empty>'}')")
            else:
                if not pr_url:
                    errors.append("deliverable.pr_url is missing or empty for task_shape implementation")
                elif not re.fullmatch(r"https://github\.com/.+/pull/[0-9]+", pr_url):
                    errors.append(f"deliverable.pr_url must match '^https://github\\.com/.+/pull/[0-9]+$' (got: '{pr_url}')")
                if not pr_state:
                    errors.append("deliverable.pr_state is missing or empty for task_shape implementation")
                elif pr_state not in {"OPEN", "MERGED", "CLOSED"}:
                    errors.append(f"deliverable.pr_state must be OPEN, MERGED, or CLOSED (got: '{pr_state}')")
            if not head_sha:
                errors.append("deliverable.head_sha is missing or empty (required when deliverable block is present)")
            elif not re.fullmatch(r"[0-9a-fA-F]{7,}", head_sha):
                errors.append(f"deliverable.head_sha must be a hex string of ≥ 7 characters (got: '{head_sha}')")

        if mode == "T" and frontmatter_has(fm, "extension_deliverable"):
            block = top_block(fm, "extension_deliverable")
            evidence = nested_block(block, "evidence", 2)
            values = {key: indented_scalar(block, key, 2) for key in (
                "endpoint", "extension_id", "task_head_sha", "workspace_commit", "template_commit",
                "version_tag", "release_url", "completed_at"
            )}
            if values["endpoint"] != "local_extension":
                errors.append(f"extension_deliverable.endpoint must be local_extension (got: '{values['endpoint'] or '<empty>'}')")
            if not values["extension_id"]:
                errors.append("extension_deliverable.extension_id is missing or empty")
            elif not re.fullmatch(r"[A-Za-z0-9._-]+", values["extension_id"]):
                errors.append(f"extension_deliverable.extension_id contains unsupported characters (got: '{values['extension_id']}')")
            for field in ("task_head_sha", "workspace_commit", "template_commit"):
                value = values[field]
                if not value:
                    errors.append(f"extension_deliverable.{field} is missing or empty")
                elif not re.fullmatch(r"[0-9a-fA-F]{7,40}", value):
                    errors.append(f"extension_deliverable.{field} must be a 7-40 char hex SHA (got: '{value}')")
            version = values["version_tag"]
            if not version:
                errors.append("extension_deliverable.version_tag is missing or empty")
            elif version != "N/A" and not re.fullmatch(r"v[0-9][A-Za-z0-9._-]*", version):
                errors.append(f"extension_deliverable.version_tag must look like v1.2.3 or be N/A (got: '{version}')")
            release = values["release_url"]
            if release and release != "N/A" and not re.fullmatch(r"https://github\.com/.+/releases/tag/.+", release):
                errors.append(f"extension_deliverable.release_url must be a GitHub release URL or N/A (got: '{release}')")
            completed = values["completed_at"]
            if not completed:
                errors.append("extension_deliverable.completed_at is missing or empty")
            elif not ISO_RE.fullmatch(completed):
                errors.append(f"extension_deliverable.completed_at must be ISO 8601 timestamp (got: '{completed}')")
            ci_value = indented_scalar(evidence, "ci_local", 4)
            verify_value = indented_scalar(evidence, "verify", 4)
            vr_value = indented_scalar(evidence, "vr", 4)
            if not ci_value:
                errors.append("extension_deliverable.evidence.ci_local is missing (use N/A when no ci-local is declared)")
            if not verify_value or verify_value == "N/A":
                errors.append("extension_deliverable.evidence.verify is missing or N/A")
            if not vr_value:
                errors.append("extension_deliverable.evidence.vr is missing (use N/A when VR did not run)")

        if mode == "V" and frontmatter_has(fm, "ac_verification"):
            block = top_block(fm, "ac_verification")
            av = {key: indented_scalar(block, key) for key in (
                "status", "last_run_at", "ac_total", "ac_pass", "ac_fail", "ac_manual_required",
                "ac_uncertain", "human_disposition", "disposition"
            )}
            if not av["status"] and av["disposition"]:
                if av["disposition"] not in {"pending", "pass", "fail", "drift_retry"}:
                    errors.append(f"ac_verification.disposition must be pending|pass|fail|drift_retry (got: '{av['disposition']}')")
            elif not av["status"]:
                errors.append("ac_verification.status is missing or empty (required when ac_verification block is present; pending form must declare disposition: pending|pass|fail|drift_retry)")
            else:
                if av["status"] not in {"PASS", "FAIL", "MANUAL_REQUIRED", "UNCERTAIN", "BLOCKED_ENV", "IN_PROGRESS"}:
                    errors.append(f"ac_verification.status must be PASS|FAIL|MANUAL_REQUIRED|UNCERTAIN|BLOCKED_ENV|IN_PROGRESS (got: '{av['status']}')")
                if not av["last_run_at"]:
                    errors.append("ac_verification.last_run_at is missing or empty (required when ac_verification block is present)")
                elif not ISO_RE.fullmatch(av["last_run_at"]):
                    errors.append(f"ac_verification.last_run_at must be ISO 8601 timestamp (got: '{av['last_run_at']}')")
                count_error = False
                for field in ("ac_total", "ac_pass", "ac_fail", "ac_manual_required", "ac_uncertain"):
                    if not av[field]:
                        errors.append(f"ac_verification.{field} is missing or empty (required when ac_verification block is present)")
                        count_error = True
                    elif not re.fullmatch(r"[0-9]+", av[field]):
                        errors.append(f"ac_verification.{field} must be a non-negative integer (got: '{av[field]}')")
                        count_error = True
                if not count_error:
                    total = sum(int(av[field]) for field in ("ac_pass", "ac_fail", "ac_manual_required", "ac_uncertain"))
                    if total != int(av["ac_total"]):
                        errors.append(f"ac_verification: ac_pass + ac_fail + ac_manual_required + ac_uncertain ({total}) must equal ac_total ({av['ac_total']})")
                disposition = av["human_disposition"]
                if av["status"] not in {"PASS", "IN_PROGRESS"} and not disposition:
                    errors.append(f"ac_verification.human_disposition is required when status='{av['status']}' (FAIL/MANUAL_REQUIRED/UNCERTAIN/BLOCKED_ENV need human triage)")
                elif disposition and disposition not in {"passed", "rejected", "deferred"}:
                    errors.append(f"ac_verification.human_disposition must be passed|rejected|deferred (got: '{disposition}')")

        for key in (["ac_verification_log"] if mode == "V" else []) + ["jira_transition_log"]:
            if frontmatter_has(fm, key):
                error = list_shape_error(fm, key, key)
                if error:
                    errors.append(error)

        chunks: list[str] = []
        if warnings:
            chunks.append(f"⚠ task.md soft warnings in {path}:\n" + "\n".join(f"  ~ {warning}" for warning in warnings))
        if errors:
            chunks.append(
                f"✗ task.md schema violations in {path}:\n"
                + "\n".join(f"  - {error}" for error in errors)
                + "\n\nContract: skills/references/task-md-schema.md (DP-033 A2 full enforcer)"
            )
        diagnostic = "\n\n".join(chunks)
        if diagnostic and emit:
            print(diagnostic, file=sys.stderr)
        return (1 if errors else 0), diagnostic

    if command == "validate":
        if len(sys.argv) != 2:
            raise SystemExit(usage())
        raise SystemExit(validate_one(Path(sys.argv[1]))[0])

    if len(sys.argv) != 2:
        raise SystemExit(usage())
    scan_root = Path(sys.argv[1])
    if not scan_root.is_dir():
        print(f"error: scan root not found: {scan_root}", file=sys.stderr)
        raise SystemExit(2)
    candidates: list[Path] = []
    for candidate in scan_root.rglob("*"):
        if not candidate.is_file() or candidate.suffix != ".md":
            continue
        parts = candidate.parts
        if ".worktrees" in parts or "node_modules" in parts or "pr-release" in parts:
            continue
        effective = candidate.parent.name if candidate.name == "index.md" else candidate.stem
        if "specs" in parts and "tasks" in parts and re.fullmatch(r"[TV][0-9]+[a-z]*", effective):
            candidates.append(candidate)
    passed = failed = hard = 0
    for candidate in sorted(candidates):
        rc, diagnostic = validate_one(candidate, emit=False)
        if rc == 0:
            print(f"PASS  {candidate}")
            passed += 1
        elif rc == 2:
            print(f"HARD  {candidate}")
            if diagnostic:
                print("\n".join(f"      {line}" for line in diagnostic.splitlines()), file=sys.stderr)
            hard += 1
            failed += 1
        else:
            print(f"FAIL  {candidate}")
            if diagnostic:
                print("\n".join(f"      {line}" for line in diagnostic.splitlines()), file=sys.stderr)
            failed += 1
    print(f"\ntask.md scan: {passed} pass, {failed} fail ({hard} hard-fail) — total {passed + failed}")
    raise SystemExit(0)
elif command == "summary-language":
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
else:
    print(f"unknown validate_task_md helper: {command}", file=sys.stderr)
    raise SystemExit(2)
