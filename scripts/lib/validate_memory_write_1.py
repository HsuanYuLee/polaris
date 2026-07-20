"""Structured validator authority extracted from scripts/validate-memory-write.sh."""

from __future__ import annotations

import os
import re
import sys
from datetime import date
from pathlib import Path

candidate_path_raw = os.environ["POLARIS_VALIDATE_MEMORY_WRITE__CANDIDATE_PATH"]
memory_dir_override = (
    os.environ.get("POLARIS_VALIDATE_MEMORY_WRITE__MEMORY_DIR_OVERRIDE") or ""
)
today_override = os.environ.get("POLARIS_VALIDATE_MEMORY_WRITE__TODAY_OVERRIDE") or ""
hot_soft_limit = int(
    os.environ.get("POLARIS_VALIDATE_MEMORY_WRITE__HOT_SOFT_LIMIT") or "15"
)
content = os.environ.get("POLARIS_VALIDATE_MEMORY_WRITE__CONTENT", "")

candidate_path = Path(candidate_path_raw).expanduser()
try:
    candidate_path = candidate_path.resolve()
except OSError:
    candidate_path = candidate_path.absolute()


def find_memory_dir(p: Path) -> Path | None:
    if memory_dir_override:
        return Path(memory_dir_override).expanduser().resolve()
    env_dir = os.environ.get("POLARIS_MEMORY_DIR")
    if env_dir:
        env_path = Path(env_dir).expanduser().resolve()
        try:
            p.resolve().relative_to(env_path)
            return env_path
        except ValueError:
            pass
    for ancestor in [p, *p.parents]:
        if ancestor.name == "memory" and ancestor.is_dir():
            return ancestor
        if ancestor.name == "memory":
            return ancestor
    return None


memory_dir = find_memory_dir(candidate_path)
if memory_dir is None:
    # Not under a memory directory; nothing to enforce.
    sys.exit(0)


def fail(code: str, *lines: str) -> None:
    print(
        f"POLARIS_MEMORY_WRITE_BLOCKED code={code} path={candidate_path}",
        file=sys.stderr,
    )
    for line in lines:
        print(line, file=sys.stderr)
    print(
        "Bypass (apply chain only): POLARIS_MEMORY_HYGIENE_APPLY=1",
        file=sys.stderr,
    )
    sys.exit(2)


# --- Block direct write to MEMORY.md ----------------------------------------
if candidate_path.name == "MEMORY.md" and candidate_path.parent == memory_dir:
    fail(
        "memory_md_direct_write",
        "MEMORY.md is a generated artifact (DP-191 round 3).",
        "Producer: python3 scripts/memory-hygiene-tiering.py --emit-index "
        f"--memory-dir {memory_dir}",
        "Or run /memory-hygiene apply.",
    )


# --- Frontmatter parse ------------------------------------------------------
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---", re.DOTALL)


def parse_frontmatter(text: str) -> dict:
    m = FRONTMATTER_RE.search(text)
    if not m:
        return {}
    body = m.group(1)
    out: dict[str, object] = {}
    for raw in body.splitlines():
        if not raw or raw.startswith("#"):
            continue
        if raw.startswith(" "):
            # Skip nested entries; this validator only inspects flat keys.
            continue
        if ":" not in raw:
            continue
        key, _, value = raw.partition(":")
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        if value.lower() == "true":
            out[key.strip()] = True
        elif value.lower() == "false":
            out[key.strip()] = False
        else:
            out[key.strip()] = value
    return out


fm = parse_frontmatter(content)


def is_topic_index(p: Path) -> bool:
    return (
        p.name == "index.md"
        and p.parent != memory_dir
        and p.parent.parent == memory_dir
    )


# index.md inside a topic folder is generated annotation; not subject to this contract.
if is_topic_index(candidate_path):
    sys.exit(0)


# --- Required fields --------------------------------------------------------
REQUIRED_FIELDS = ("name", "description", "type", "created")
missing = [f for f in REQUIRED_FIELDS if not fm.get(f)]
if missing:
    fail(
        "frontmatter_required_field_missing",
        f"Missing fields: {', '.join(missing)}",
        "Required: name, description, type, created",
        "See .claude/skills/references/memory-tiering-contract.md § Frontmatter Fields.",
    )


# --- pinned ⇒ pinned_reason -------------------------------------------------
if fm.get("pinned") is True and not str(fm.get("pinned_reason") or "").strip():
    fail(
        "pinned_missing_reason",
        "pinned: true requires pinned_reason: (non-empty).",
        "Either remove pinned: true or add pinned_reason: <user-declared reason>.",
    )


# --- topic ⇒ folder must exist (or candidate is inside it) ------------------
topic = fm.get("topic")
if topic:
    topic_str = str(topic).strip()
    if topic_str:
        topic_dir = memory_dir / topic_str
        candidate_in_topic = candidate_path.parent == topic_dir
        if not topic_dir.is_dir() and not candidate_in_topic:
            fail(
                "topic_folder_missing",
                f"topic: {topic_str} → no folder {topic_dir}",
                "Either omit `topic:` (writer rule: flat at memory root when no folder),",
                "or wait for `/memory-hygiene apply` to create the topic folder.",
            )


# --- Hot soft-limit ---------------------------------------------------------
HOT_DAYS = 30
HOT_TRIGGER_THRESHOLD = 5
FRESH_WRITE_GRACE_DAYS = 7

if today_override:
    today = date.fromisoformat(today_override)
else:
    today = date.today()


def parse_date(value) -> date | None:
    if not value:
        return None
    s = str(value).strip()
    if not s:
        return None
    try:
        return date.fromisoformat(s)
    except ValueError:
        return None


def is_hot_overflow_demoted(fm: dict) -> bool:
    """DP-282: a flat-root file carrying the durable hot_overflow_demoted signal
    was demoted out of Hot by the last hygiene apply and must NOT count toward the
    15-cap. Cheap: read only the file's own flat frontmatter, no MEMORY.md index
    parse (AC5). pinned / graduated_to never carry the signal (D4)."""
    return fm.get("hot_overflow_demoted") is True


def candidate_would_be_hot(fm: dict, written_path: Path) -> bool:
    if fm.get("graduated_to"):
        return False
    if is_hot_overflow_demoted(fm):
        return False
    if fm.get("pinned") is True:
        return True
    tc = fm.get("trigger_count")
    try:
        tc_int = int(tc) if tc is not None else 0
    except (TypeError, ValueError):
        tc_int = 0
    if tc_int >= HOT_TRIGGER_THRESHOLD:
        return True
    lt = parse_date(fm.get("last_triggered"))
    if lt is not None:
        return (today - lt).days <= HOT_DAYS
    # No last_triggered → fresh-write grace based on created.
    cr = parse_date(fm.get("created"))
    if cr is not None:
        return (today - cr).days <= FRESH_WRITE_GRACE_DAYS
    return False


def file_is_hot(p: Path) -> bool:
    try:
        text = p.read_text()
    except OSError:
        return False
    file_fm = parse_frontmatter(text)
    if file_fm.get("graduated_to"):
        return False
    if is_hot_overflow_demoted(file_fm):
        return False
    if file_fm.get("pinned") is True:
        return True
    tc = file_fm.get("trigger_count")
    try:
        tc_int = int(tc) if tc is not None else 0
    except (TypeError, ValueError):
        tc_int = 0
    if tc_int >= HOT_TRIGGER_THRESHOLD:
        return True
    lt = parse_date(file_fm.get("last_triggered"))
    if lt is not None:
        return (today - lt).days <= HOT_DAYS
    cr = parse_date(file_fm.get("created"))
    if cr is not None:
        return (today - cr).days <= FRESH_WRITE_GRACE_DAYS
    return False


def hot_files_after_write() -> list[tuple[Path, date | None, date | None]]:
    """Return list of (path, last_triggered, created) for files that would be Hot post-write."""
    candidate_is_under_root = candidate_path.parent == memory_dir
    hot: list[tuple[Path, date | None, date | None]] = []
    seen_candidate = False
    if memory_dir.is_dir():
        for entry in memory_dir.iterdir():
            if not entry.is_file():
                continue
            if entry.suffix != ".md":
                continue
            if entry.name == "MEMORY.md":
                continue
            if entry == candidate_path:
                seen_candidate = True
                if candidate_would_be_hot(fm, candidate_path):
                    hot.append(
                        (
                            candidate_path,
                            parse_date(fm.get("last_triggered")),
                            parse_date(fm.get("created")),
                        )
                    )
                continue
            if file_is_hot(entry):
                t = parse_frontmatter(entry.read_text())
                hot.append(
                    (
                        entry,
                        parse_date(t.get("last_triggered")),
                        parse_date(t.get("created")),
                    )
                )
    if (
        not seen_candidate
        and candidate_is_under_root
        and candidate_would_be_hot(fm, candidate_path)
    ):
        hot.append(
            (
                candidate_path,
                parse_date(fm.get("last_triggered")),
                parse_date(fm.get("created")),
            )
        )
    return hot


# Only enforce soft limit when candidate is a flat (root) memory file. Files inside
# topic folders are Warm by design and do not count toward Hot.
if candidate_path.parent == memory_dir:
    hot = hot_files_after_write()
    new_n = len(hot)
    if new_n > hot_soft_limit:
        # Surface the 3 oldest candidates for demotion (lowest last_triggered first).
        def sort_key(item):
            p, lt, cr = item
            anchor = lt or cr or date(1970, 1, 1)
            return anchor.isoformat()

        sorted_hot = sorted(hot, key=sort_key)
        oldest = sorted_hot[:3]
        lines = [
            f"Hot would become {new_n} after this write (soft limit {hot_soft_limit}).",
            "Oldest candidates for demotion:",
        ]
        for p, lt, cr in oldest:
            anchor = (
                (lt and f"last_triggered={lt.isoformat()}")
                or (cr and f"created={cr.isoformat()}")
                or "no-date"
            )
            lines.append(f"  - {p.name} ({anchor})")
        lines.append(
            "Run: /memory-hygiene "
            "(or `python3 scripts/memory-hygiene-tiering.py dry-run --json | "
            "bash scripts/validate-memory-hygiene-plan.sh | "
            "python3 scripts/memory-hygiene-tiering.py apply`)"
        )
        fail("hot_soft_limit_exceeded", *lines)

sys.exit(0)
