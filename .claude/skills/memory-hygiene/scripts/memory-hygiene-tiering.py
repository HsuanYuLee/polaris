#!/usr/bin/env python3
"""
Memory hygiene — Hot/Warm/Cold tiering (DP-015 Part B).

Four modes:
  dry-run     Classify every memory file into Hot / Warm / Cold and print a report.
              Does not move, edit, or delete anything.
  apply       Move files according to a prior dry-run (reads plan from stdin JSON)
              and update MEMORY.md links. Writes `.migration-log.md`.
  decay-scan  Session-start mode: promote expired Hot → Warm, Warm → Cold/archive.
              Advisory only — prints what would change, no moves.
  emit-index  Regenerate `MEMORY.md` from live memory frontmatter.
              Owned writer for the generated MEMORY.md index (DP-191 round 3).
              Bounds rewrite to the marker-delimited block; annotation outside the
              markers is preserved byte-equal. `--dry-run` prints a unified diff
              to stdout and exits without writing.

Classification rules (D7.1 / B7):
  pinned == true                                 → Hot
  last_triggered >= today - 30 days              → Hot
  trigger_count >= 5                             → Hot
  last_triggered >= today - 90 days              → Warm (grouped by `topic` if set)
  else                                           → Cold  (archive/)

Default inference:
  last_triggered missing → file mtime
  trigger_count missing  → 0
  topic missing          → heuristic slug from name/description; Warm fallback = flat

MEMORY.md hygiene:
  Entries prefixed with `~~...~~` in MEMORY.md are treated as "already archived" —
  their underlying files are candidates for Cold regardless of trigger state.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Optional

DEFAULT_MEMORY_DIR = Path.home() / ".claude" / "projects" / "-Users-hsuanyu-lee-work" / "memory"

HOT_DAYS = 30
WARM_DAYS = 90
HOT_TRIGGER_THRESHOLD = 5
FRESH_WRITE_GRACE_DAYS = 7  # files with no last_triggered but recently written count as Hot
MEMORY_HOT_CAPACITY = int(os.environ.get("MEMORY_HOT_CAPACITY", "15"))
OVERFLOW_REASON_PREFIX = "overflowed-hot-capacity"
# Durable per-file frontmatter signal (DP-282 D1/D2): apply demotion stamps this
# on flat-root files that overflow Hot capacity but stay flat (no topic move), so
# validate-memory-write.sh can treat them as NOT Hot without re-deriving capacity.
# Removed on re-qualification (D3); never written to pinned / graduated_to (D4).
HOT_OVERFLOW_DEMOTED_FIELD = "hot_overflow_demoted"


@dataclass
class Frontmatter:
    name: str = ""
    description: str = ""
    type: str = ""
    company: Optional[str] = None
    trigger_count: int = 0
    last_triggered: Optional[date] = None
    created: Optional[date] = None
    pinned: bool = False
    pinned_reason: Optional[str] = None
    topic: Optional[str] = None
    hot_overflow_demoted: bool = False
    snapshot_of: Optional[str] = None
    snapshot_taken: Optional[date] = None
    graduated_to: Optional[str] = None
    origin_session_id: Optional[str] = None
    nested_metadata: bool = False
    raw: dict = field(default_factory=dict)


@dataclass
class Classification:
    path: Path
    tier: str                   # "hot" | "warm" | "cold"
    topic: Optional[str]        # warm destination slug (None for hot/cold or flat-warm)
    reason: str                 # human-readable why
    frontmatter: Frontmatter = field(default_factory=Frontmatter)
    mtime: Optional[date] = None
    archived_in_index: bool = False
    flags: dict = field(default_factory=dict)
    created_backfill: Optional[str] = None

    @property
    def destination(self) -> str:
        if self.tier == "hot":
            return "MEMORY.md (Hot)"
        if self.tier == "cold":
            return "archive/"
        if self.topic:
            return f"{self.topic}/"
        return "(flat — Warm, no topic)"


FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def parse_frontmatter(text: str) -> Frontmatter:
    """Minimal YAML-ish parser (memory files use a flat subset)."""
    fm = Frontmatter()
    m = FRONTMATTER_RE.match(text)
    if not m:
        return fm
    body = m.group(1)
    data: dict = {}
    nested_metadata = False
    for line in body.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if key == "metadata" and not value:
            nested_metadata = True
            continue
        if line[:1].isspace() and nested_metadata:
            key = key.strip()
        # Strip surrounding quotes
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        data.setdefault(key, value)
    fm.raw = data
    fm.nested_metadata = nested_metadata
    fm.name = data.get("name", "")
    fm.description = data.get("description", "")
    fm.type = data.get("type", "")
    fm.company = data.get("company") or None
    try:
        fm.trigger_count = int(data.get("trigger_count", "0") or "0")
    except ValueError:
        fm.trigger_count = 0
    lt = data.get("last_triggered")
    if lt:
        fm.last_triggered = parse_date(lt)
    created = data.get("created")
    if created:
        fm.created = parse_date(created)
    pinned = data.get("pinned", "").lower()
    fm.pinned = pinned in ("true", "yes", "1")
    fm.pinned_reason = data.get("pinned_reason") or None
    fm.topic = data.get("topic") or None
    hot_overflow_demoted = data.get("hot_overflow_demoted", "").lower()
    fm.hot_overflow_demoted = hot_overflow_demoted in ("true", "yes", "1")
    fm.snapshot_of = data.get("snapshot_of") or None
    snapshot_taken = data.get("snapshot_taken")
    if snapshot_taken:
        fm.snapshot_taken = parse_date(snapshot_taken)
    fm.graduated_to = data.get("graduated_to") or None
    fm.origin_session_id = data.get("originSessionId") or data.get("origin_session_id") or None
    return fm


def parse_date(value: str) -> Optional[date]:
    try:
        return datetime.strptime(value.strip(), "%Y-%m-%d").date()
    except (ValueError, AttributeError):
        return None


def repo_root() -> Optional[Path]:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=True,
        )
    except Exception:
        return None
    return Path(proc.stdout.strip())


def frontmatter_status(path: Path) -> Optional[str]:
    try:
        fm = parse_frontmatter(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    status = fm.raw.get("status")
    return status.upper() if isinstance(status, str) and status else None


def source_status(source_id: str) -> Optional[str]:
    specs_env = os.environ.get("POLARIS_SPECS_ROOT")
    if specs_env:
        specs = Path(specs_env)
    else:
        root = repo_root()
        if root is None:
            return None
        specs = root / "docs-manager" / "src" / "content" / "docs" / "specs"
    if re.match(r"^DP-[0-9]{3}$", source_id):
        for parent in [specs / "design-plans", specs / "design-plans" / "archive"]:
            for container in parent.glob(f"{source_id}-*"):
                for name in ("index.md", "plan.md", "refinement.md"):
                    status = frontmatter_status(container / name)
                    if status:
                        return status
        return None
    for candidate in specs.glob(f"companies/**/{source_id}/**/*.md"):
        status = frontmatter_status(candidate)
        if status:
            return status
    return None


def snapshot_is_stale(fm: Frontmatter, today: date) -> tuple[bool, str]:
    if not fm.snapshot_of:
        return False, ""
    status = source_status(fm.snapshot_of)
    if status in {"IMPLEMENTED", "SUPERSEDED", "ABANDONED"}:
        return True, f"snapshot_of={fm.snapshot_of} status={status}"
    if fm.snapshot_taken:
        age = (today - fm.snapshot_taken).days
        if age > 14:
            return True, f"snapshot_taken {age}d ago"
    return False, f"snapshot_of={fm.snapshot_of} status={status or 'unknown'}"


def grace_baseline(fm: Frontmatter, mtime: date) -> tuple[date, str, Optional[str]]:
    if fm.created:
        return fm.created, "created", None
    return mtime, "mtime_fallback", mtime.isoformat()


# --- Topic inference ------------------------------------------------------

# Patterns → canonical topic slug. First match wins.
# Slugs use lowercase kebab-case. A missing match leaves topic=None (flat Warm).
TOPIC_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bGT-?(478|479|480|482|483|490|491|495|509)\b", re.I), "cwv-epics"),
    (re.compile(r"\bGT-?521\b|breadcrumb", re.I), "gt-521-breadcrumb"),
    (re.compile(r"\bKB2CW-?3847\b|duplicate[-_ ]fetch", re.I), "kb2cw-3847"),
    (re.compile(r"\bKB2CW-?3657\b", re.I), "kb2cw-3657"),
    (re.compile(r"\bKB2CW-?2863\b|multidate", re.I), "kb2cw-2863"),
    (re.compile(r"\bDP-?005\b|engineering[-_ ]test", re.I), "dp-005"),
    (re.compile(r"\bDP-?009\b|context[-_ ]optim", re.I), "dp-009"),
    (re.compile(r"\bDP-?015\b|polaris[-_ ]context", re.I), "dp-015"),
    (re.compile(r"refinement[-_ ]v", re.I), "refinement-v2"),
    (re.compile(r"\bworkon\b|work[-_ ]on|engineer.*mindset", re.I), "workon-redesign"),
    (re.compile(r"visual[-_ ]regression|\bvr\b|mockoon", re.I), "visual-regression"),
    (re.compile(r"handbook|repo[-_ ]knowledge", re.I), "handbook-lifecycle"),
    (re.compile(r"review[-_ ]inbox|check[-_ ]pr", re.I), "pr-review-flow"),
    (re.compile(r"skill[-_ ](consolidation|architecture|script)", re.I), "skill-architecture"),
    (re.compile(r"lighthouse|cwv|core[-_ ]web|ttfb", re.I), "cwv-benchmark"),
    (re.compile(r"intake[-_ ]triage|epic[-_ ]status|execution[-_ ]queue", re.I), "intake-flow"),
    (re.compile(r"library|module.*replace|no[-_ ]replace", re.I), "library-protocol"),
    (re.compile(r"session[-_ ]split|checkpoint", re.I), "session-management"),
    (re.compile(r"slack|confluence|jira.*convention|worklog", re.I), "tooling"),
    (re.compile(r"polaris[-_ ](roadmap|evolution|sync|mindset|framework|next|docs)", re.I), "polaris-framework"),
    (re.compile(r"init[-_ ]v|three[-_ ]layer|workspace[-_ ]", re.I), "polaris-framework"),
    (re.compile(r"\bai[-_ ]changes|ai[-_ ]env|ai[-_ ]guidelines", re.I), "legacy-config-deploy"),
    (re.compile(r"gt-?483", re.I), "gt-483-i18n"),
    (re.compile(r"permission|hook[-_ ]vs|bash|python[-_ ]pipe", re.I), "permissions"),
    (re.compile(r"\bpm\b|epic[-_ ]quality", re.I), "pm-collaboration"),
]


def infer_topic(fm: Frontmatter, filename: str) -> Optional[str]:
    if fm.topic:
        return fm.topic.strip().lower().replace(" ", "-")
    haystack = " ".join([filename, fm.name, fm.description])
    for pattern, slug in TOPIC_PATTERNS:
        if pattern.search(haystack):
            return slug
    return None


# --- Classification -------------------------------------------------------

def classify(path: Path, text: str, today: date, archived_set: set[str]) -> Classification:
    """Classify a memory file.

    Hot requires an explicit signal of active use:
      - pinned: true
      - trigger_count >= HOT_TRIGGER_THRESHOLD
      - last_triggered within HOT_DAYS
      - OR no last_triggered but file written within FRESH_WRITE_GRACE_DAYS
        (freshly-written file, not yet referenced — presumed active)

    mtime is NOT a general fallback for Hot. Stale files without trigger data
    default to Warm (never-used → not actively needed).
    """
    fm = parse_frontmatter(text)
    mtime = date.fromtimestamp(path.stat().st_mtime)
    archived = path.name in archived_set
    baseline, baseline_source, created_backfill = grace_baseline(fm, mtime)
    stale_snapshot, stale_reason = snapshot_is_stale(fm, today)
    flags = {
        "stale_snapshot": stale_snapshot,
        "graduated_feedback": bool(fm.graduated_to),
        "nested_frontmatter": fm.nested_metadata,
        "fresh_write_hot": False,
        "grace_baseline": baseline_source,
    }

    # pinned=true is an unconditional Hot signal — it must short-circuit BEFORE
    # any demotion branch (archived / graduated_to / stale_snapshot), otherwise a
    # pinned file that also hits a demotion branch would be wrongly cold/warm.
    if fm.pinned:
        return Classification(
            path=path, tier="hot", topic=None,
            reason="pinned=true", frontmatter=fm, mtime=mtime,
            flags=flags, created_backfill=created_backfill,
        )

    # Archived-in-index takes priority → Cold
    if archived:
        return Classification(
            path=path, tier="cold", topic=None,
            reason="strikethrough in MEMORY.md", frontmatter=fm,
            mtime=mtime, archived_in_index=True, flags=flags,
            created_backfill=created_backfill,
        )

    if fm.graduated_to:
        return Classification(
            path=path, tier="cold", topic=None,
            reason=f"graduated_to={fm.graduated_to}", frontmatter=fm,
            mtime=mtime, flags=flags, created_backfill=created_backfill,
        )

    if stale_snapshot:
        topic = infer_topic(fm, path.name)
        return Classification(
            path=path, tier="warm", topic=topic,
            reason=f"stale snapshot ({stale_reason})"
                   + (f", topic={topic}" if topic else ", no topic"),
            frontmatter=fm, mtime=mtime, flags=flags,
            created_backfill=created_backfill,
        )
    if fm.trigger_count >= HOT_TRIGGER_THRESHOLD:
        return Classification(
            path=path, tier="hot", topic=None,
            reason=f"trigger_count={fm.trigger_count}",
            frontmatter=fm, mtime=mtime, flags=flags,
            created_backfill=created_backfill,
        )
    if fm.last_triggered is not None:
        age = (today - fm.last_triggered).days
        if age <= HOT_DAYS:
            return Classification(
                path=path, tier="hot", topic=None,
                reason=f"last_triggered {age}d ago",
                frontmatter=fm, mtime=mtime, flags=flags,
                created_backfill=created_backfill,
            )
        if age <= WARM_DAYS:
            topic = infer_topic(fm, path.name)
            return Classification(
                path=path, tier="warm", topic=topic,
                reason=f"warm ({age}d since last_triggered)"
                       + (f", topic={topic}" if topic else ", no topic"),
                frontmatter=fm, mtime=mtime, flags=flags,
                created_backfill=created_backfill,
            )
        return Classification(
            path=path, tier="cold", topic=None,
            reason=f"stale ({age}d since last_triggered)",
            frontmatter=fm, mtime=mtime, flags=flags,
            created_backfill=created_backfill,
        )
    # No last_triggered, no trigger_count — use mtime only as fresh-write grace
    age = (today - baseline).days
    if age <= FRESH_WRITE_GRACE_DAYS:
        flags["fresh_write_hot"] = True
        return Classification(
            path=path, tier="hot", topic=None,
            reason=f"fresh-write ({age}d, no trigger data yet, baseline={baseline_source})",
            frontmatter=fm, mtime=mtime, flags=flags,
            created_backfill=created_backfill,
        )
    topic = infer_topic(fm, path.name)
    if age <= WARM_DAYS:
        return Classification(
            path=path, tier="warm", topic=topic,
            reason=f"never-triggered, mtime {age}d"
                   + (f", topic={topic}" if topic else ", no topic"),
            frontmatter=fm, mtime=mtime, flags=flags,
            created_backfill=created_backfill,
        )
    return Classification(
        path=path, tier="cold", topic=None,
        reason=f"never-triggered, stale ({age}d)",
        frontmatter=fm, mtime=mtime, flags=flags,
        created_backfill=created_backfill,
    )


# --- MEMORY.md parsing ----------------------------------------------------

STRIKETHROUGH_RE = re.compile(r"~~([a-zA-Z0-9_\-\.]+\.md)~~")
LINK_RE = re.compile(r"\[([^\]]+)\]\(([a-zA-Z0-9_\-\.]+\.md)\)")


def parse_memory_index(index_path: Path) -> tuple[set[str], set[str]]:
    """Return (archived_filenames, linked_filenames) from MEMORY.md."""
    archived: set[str] = set()
    linked: set[str] = set()
    if not index_path.exists():
        return archived, linked
    text = index_path.read_text(encoding="utf-8")
    for m in STRIKETHROUGH_RE.finditer(text):
        archived.add(m.group(1))
    for m in LINK_RE.finditer(text):
        linked.add(m.group(2))
    return archived, linked


# --- Report rendering -----------------------------------------------------

def render_report(classifications: list[Classification], today: date,
                  orphan_files: list[Path], missing_files: list[str]) -> str:
    hot = [c for c in classifications if c.tier == "hot"]
    warm = [c for c in classifications if c.tier == "warm"]
    cold = [c for c in classifications if c.tier == "cold"]
    summary = summarize_classifications(classifications)

    topics: dict[str, list[Classification]] = {}
    warm_flat: list[Classification] = []
    for c in warm:
        if c.topic:
            topics.setdefault(c.topic, []).append(c)
        else:
            warm_flat.append(c)

    lines: list[str] = []
    lines.append("# Memory Hygiene — Dry-Run Report")
    lines.append("")
    lines.append(f"- Date: {today.isoformat()}")
    lines.append(f"- Total memory files scanned: {len(classifications)}")
    lines.append(f"- Hot: {len(hot)}  |  Warm: {len(warm)} ({len(topics)} topics, {len(warm_flat)} flat)  |  Cold: {len(cold)}")
    lines.append(
        f"- Flags: stale_snapshot={summary['stale_snapshot']}, "
        f"graduated_feedback={summary['graduated_feedback']}, "
        f"nested_frontmatter={summary['nested_frontmatter']}, "
        f"fresh_write_hot={summary['fresh_write_hot']}, "
        f"created_backfill={summary['created_backfill']}"
    )
    if orphan_files:
        lines.append(f"- Orphan files (exist on disk but not linked in MEMORY.md): {len(orphan_files)}")
    if missing_files:
        lines.append(f"- Missing files (linked in MEMORY.md but missing on disk): {len(missing_files)}")
    lines.append("")
    lines.append("## Classification rules")
    lines.append(f"- Hot: pinned OR last_triggered within {HOT_DAYS}d OR trigger_count ≥ {HOT_TRIGGER_THRESHOLD} OR fresh-write grace ≤ {FRESH_WRITE_GRACE_DAYS}d")
    lines.append(f"- Warm: last_triggered/created/mtime within {WARM_DAYS}d (grouped by topic)")
    lines.append("- Cold: older OR strikethrough in MEMORY.md → archive/")
    lines.append("")

    lines.append(f"## Hot ({len(hot)}) — stays in MEMORY.md")
    lines.append("")
    for c in sorted(hot, key=hot_sort_key_classification, reverse=True):
        lt = c.frontmatter.last_triggered or c.mtime
        lines.append(f"- `{c.path.name}` — {c.reason}  (lt={lt}, tc={c.frontmatter.trigger_count})")
    lines.append("")

    lines.append(f"## Warm ({len(warm)}) — move to `memory/{{topic}}/`")
    lines.append("")
    for topic in sorted(topics.keys()):
        group = topics[topic]
        lines.append(f"### `{topic}/` ({len(group)})")
        for c in sorted(group, key=lambda x: x.path.name):
            lt = c.frontmatter.last_triggered or c.mtime
            lines.append(f"- `{c.path.name}` — lt={lt}, tc={c.frontmatter.trigger_count}")
        lines.append("")
    if warm_flat:
        lines.append(f"### Flat ({len(warm_flat)}) — no topic matched, stays flat until decay")
        for c in sorted(warm_flat, key=lambda x: x.path.name):
            lt = c.frontmatter.last_triggered or c.mtime
            lines.append(f"- `{c.path.name}` — lt={lt}, tc={c.frontmatter.trigger_count}")
        lines.append("")

    lines.append(f"## Cold ({len(cold)}) — move to `memory/archive/`")
    lines.append("")
    for c in sorted(cold, key=lambda x: (x.frontmatter.last_triggered or x.mtime or today)):
        lt = c.frontmatter.last_triggered or c.mtime
        tag = " [archived-in-index]" if c.archived_in_index else ""
        lines.append(f"- `{c.path.name}` — {c.reason}{tag}  (lt={lt})")
    lines.append("")

    if orphan_files:
        lines.append(f"## Orphan files ({len(orphan_files)}) — on disk but not in MEMORY.md")
        lines.append("")
        for p in sorted(orphan_files):
            lines.append(f"- `{p.name}`")
        lines.append("")
    if missing_files:
        lines.append(f"## Missing files ({len(missing_files)}) — linked in MEMORY.md but not on disk")
        lines.append("")
        for name in sorted(missing_files):
            lines.append(f"- `{name}`")
        lines.append("")

    lines.append("## Next steps")
    lines.append("")
    lines.append("1. Review this report. Correct any misclassifications by adjusting frontmatter:")
    lines.append("   - Want Hot? add `pinned: true` or bump `last_triggered` to today.")
    lines.append("   - Want a specific Warm topic? set `topic: <slug>`.")
    lines.append("2. When satisfied, pipe this report's JSON plan to `--apply`:")
    lines.append("   `memory-hygiene-tiering.py dry-run --json > plan.json && memory-hygiene-tiering.py apply < plan.json`")
    lines.append("3. Orphan files will be archived by default in `apply`. Missing files will be pruned from MEMORY.md.")
    return "\n".join(lines)


def summarize_classifications(classifications: list[Classification]) -> dict[str, int]:
    return {
        "stale_snapshot": sum(1 for c in classifications if c.flags.get("stale_snapshot")),
        "graduated_feedback": sum(1 for c in classifications if c.flags.get("graduated_feedback")),
        "nested_frontmatter": sum(1 for c in classifications if c.flags.get("nested_frontmatter")),
        "fresh_write_hot": sum(1 for c in classifications if c.flags.get("fresh_write_hot")),
        "created_backfill": sum(1 for c in classifications if c.created_backfill),
    }


def hot_sort_key_classification(c: Classification) -> tuple[int, str]:
    if c.frontmatter.last_triggered:
        return (1, c.frontmatter.last_triggered.isoformat())
    return (0, c.mtime.isoformat() if c.mtime else "1970-01-01")


def render_json(classifications: list[Classification], today: date) -> str:
    hot = [c for c in classifications if c.tier == "hot"]
    payload = {
        "date": today.isoformat(),
        "hot_days": HOT_DAYS,
        "warm_days": WARM_DAYS,
        "trigger_threshold": HOT_TRIGGER_THRESHOLD,
        "fresh_write_grace_days": FRESH_WRITE_GRACE_DAYS,
        "summary": summarize_classifications(classifications),
        "hot_order": [c.path.name for c in sorted(hot, key=hot_sort_key_classification, reverse=True)],
        "classifications": [
            {
                "file": c.path.name,
                "tier": c.tier,
                "topic": c.topic,
                "reason": c.reason,
                "last_triggered": (
                    c.frontmatter.last_triggered.isoformat() if c.frontmatter.last_triggered else None
                ),
                "mtime": c.mtime.isoformat() if c.mtime else None,
                "trigger_count": c.frontmatter.trigger_count,
                "pinned": c.frontmatter.pinned,
                "pinned_reason": c.frontmatter.pinned_reason,
                "archived_in_index": c.archived_in_index,
                "flags": c.flags,
                "created_backfill": c.created_backfill,
            }
            for c in classifications
        ],
    }
    return json.dumps(payload, indent=2, ensure_ascii=False)


# --- Modes ----------------------------------------------------------------

def apply_hot_capacity_ceiling(
    classifications: list[Classification],
    today: date,
    capacity: int = MEMORY_HOT_CAPACITY,
) -> list[Classification]:
    """Demote overflowing Hot entries to Warm using a deterministic ranking.

    Contract (DP-213):
      - pinned=True entries always stay Hot (never demoted by ceiling).
      - graduated_to entries are already Cold by classify(); not considered here.
      - Among non-pinned Hot candidates, rank by:
          1. trigger_count desc
          2. last_triggered recency (None pushed to oldest)
          3. mtime desc (tie-breaker)
          4. filename asc (final deterministic tie-breaker)
      - Keep top (capacity - pinned_count) in Hot; demote the rest to Warm.
      - Demoted entries get tier="warm" and reason prefixed with
        OVERFLOW_REASON_PREFIX so apply path can log them even when they
        stay flat (no topic move).
    """
    if capacity <= 0:
        return classifications
    hot_idx = [i for i, c in enumerate(classifications) if c.tier == "hot"]
    if len(hot_idx) <= capacity:
        return classifications
    pinned_idx = [i for i in hot_idx if classifications[i].frontmatter.pinned]
    non_pinned_idx = [i for i in hot_idx if not classifications[i].frontmatter.pinned]
    keep_slots = max(capacity - len(pinned_idx), 0)

    def rank_key(i: int):
        c = classifications[i]
        lt = c.frontmatter.last_triggered
        recency_days = (today - lt).days if lt else 10**6
        return (
            -c.frontmatter.trigger_count,
            recency_days,
            -int(c.mtime.toordinal()) if c.mtime else 0,
            c.path.name,
        )

    ranked = sorted(non_pinned_idx, key=rank_key)
    keep = set(ranked[:keep_slots]) | set(pinned_idx)

    updated = list(classifications)
    for i in non_pinned_idx:
        if i in keep:
            continue
        c = classifications[i]
        topic = infer_topic(c.frontmatter, c.path.name)
        new_flags = dict(c.flags)
        new_flags["overflowed_hot_capacity"] = True
        topic_part = f", topic={topic}" if topic else ", no topic"
        updated[i] = Classification(
            path=c.path,
            tier="warm",
            topic=topic,
            reason=f"{OVERFLOW_REASON_PREFIX} (was Hot: {c.reason}){topic_part}",
            frontmatter=c.frontmatter,
            mtime=c.mtime,
            archived_in_index=c.archived_in_index,
            flags=new_flags,
            created_backfill=c.created_backfill,
        )
    return updated


def collect(memory_dir: Path, today: date) -> tuple[list[Classification], list[Path], list[str]]:
    """Scan memory_dir, return (classifications, orphan_paths, missing_filenames)."""
    index_path = memory_dir / "MEMORY.md"
    archived, linked = parse_memory_index(index_path)

    on_disk: list[Path] = []
    for p in memory_dir.iterdir():
        if not p.is_file():
            continue
        if p.suffix != ".md":
            continue
        if p.name == "MEMORY.md":
            continue
        on_disk.append(p)

    classifications: list[Classification] = []
    for p in on_disk:
        try:
            text = p.read_text(encoding="utf-8")
        except Exception as e:
            print(f"Warning: could not read {p.name}: {e}", file=sys.stderr)
            continue
        classifications.append(classify(p, text, today, archived))

    classifications = apply_hot_capacity_ceiling(classifications, today)

    # Orphan = on disk, not archived, not linked
    on_disk_names = {p.name for p in on_disk}
    orphans = [p for p in on_disk if p.name not in linked and p.name not in archived]
    missing = [name for name in linked if name not in on_disk_names]
    return classifications, orphans, missing


def run_dry_run(memory_dir: Path, today: date, emit_json: bool) -> int:
    classifications, orphans, missing = collect(memory_dir, today)
    if emit_json:
        sys.stdout.write(render_json(classifications, today))
    else:
        sys.stdout.write(render_report(classifications, today, orphans, missing))
    sys.stdout.write("\n")
    return 0


def run_decay_scan(memory_dir: Path, today: date) -> int:
    """Session-start advisory: list files whose tier would demote today.
    Does NOT move anything. Non-zero exit code if there are items to review.
    """
    classifications, _orphans, _missing = collect(memory_dir, today)
    to_demote = [c for c in classifications if c.tier != "hot" and c.path.parent == memory_dir]
    stale = [c for c in classifications if c.flags.get("stale_snapshot")]
    graduated = [c for c in classifications if c.flags.get("graduated_feedback")]
    if not to_demote:
        print(f"[memory-decay] No files need demotion (scanned {len(classifications)} files).")
        return 0
    print(f"[memory-decay] {len(to_demote)} flat file(s) could be demoted to Warm/Cold:")
    for c in to_demote[:20]:
        print(f"  - {c.path.name} → {c.tier}  ({c.reason})")
    if len(to_demote) > 20:
        print(f"  ... and {len(to_demote) - 20} more")
    if stale:
        print("[memory-decay] stale snapshot candidates:")
        for c in stale[:20]:
            print(f"  - {c.path.name} → {c.tier}  ({c.reason})")
    if graduated:
        print("[memory-decay] graduated feedback candidates:")
        for c in graduated[:20]:
            print(f"  - {c.path.name} → {c.tier}  ({c.reason})")
    print("Run: memory-hygiene-tiering.py dry-run   (for full report)")
    print("Or:  /memory-hygiene                     (to migrate)")
    return 0  # advisory — never blocks session


INDEX_ENTRY_RE = re.compile(r"^- \[([^\]]+)\]\(([^)]+\.md)\)(?:\s+—\s+(.*))?$")
STRIKETHROUGH_ENTRY_RE = re.compile(r"^- ~~([^~]+\.md)~~(.*)$")
MIGRATION_HEADER_RE = re.compile(r"^## Migrated to Company Handbook", re.M)


def parse_memory_index_entries(index_path: Path) -> tuple[dict[str, dict], str]:
    """Parse MEMORY.md, returning (entries_by_filename, footer_to_preserve).

    Entries dict: filename.md -> {'title': str, 'description': str, 'strikethrough': bool}
    Footer: the "## Migrated to Company Handbook" section and everything after (preserved verbatim).
    """
    entries: dict[str, dict] = {}
    footer = ""
    if not index_path.exists():
        return entries, footer
    text = index_path.read_text(encoding="utf-8")
    m = MIGRATION_HEADER_RE.search(text)
    body = text[:m.start()] if m else text
    footer = text[m.start():] if m else ""
    for line in body.splitlines():
        m1 = INDEX_ENTRY_RE.match(line)
        if m1:
            title, filename, desc = m1.group(1), m1.group(2), m1.group(3) or ""
            entries[filename] = {"title": title, "description": desc, "strikethrough": False}
            continue
        m2 = STRIKETHROUGH_ENTRY_RE.match(line)
        if m2:
            filename = m2.group(1)
            # Only track if it points to a real .md file (not a description note)
            entries[filename] = {"title": filename, "description": m2.group(2).lstrip(" —"), "strikethrough": True}
    return entries, footer


def normalize_memory_file(path: Path) -> bool:
    """Normalize flat frontmatter enough for hygiene apply.

    - flatten one-level `metadata:` blocks into top-level fields
    - add `created: <original_mtime_date>` when missing
    """
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER_RE.match(text)
    if not match:
        return False
    body = match.group(1)
    lines = body.splitlines()
    existing_keys: set[str] = set()
    for line in lines:
        if ":" not in line or line[:1].isspace():
            continue
        key, _, _ = line.partition(":")
        existing_keys.add(key.strip())

    new_lines: list[str] = []
    changed = False
    in_metadata = False
    flattened: list[str] = []
    for line in lines:
        if line.strip() == "metadata:":
            in_metadata = True
            changed = True
            continue
        if in_metadata and line[:1].isspace() and ":" in line:
            key, _, value = line.strip().partition(":")
            if key not in existing_keys:
                flattened.append(f"{key}: {value.strip()}")
                existing_keys.add(key)
            changed = True
            continue
        if in_metadata and line.strip() and not line[:1].isspace():
            in_metadata = False
        new_lines.append(line)

    if "created" not in existing_keys:
        created = date.fromtimestamp(path.stat().st_mtime).isoformat()
        new_lines.append(f"created: {created}")
        changed = True
    new_lines.extend(flattened)
    if not changed:
        return False
    rest = text[match.end():]
    path.write_text("---\n" + "\n".join(new_lines) + "\n---\n" + rest, encoding="utf-8")
    return True


def set_frontmatter_bool_flag(path: Path, field_name: str, present: bool) -> bool:
    """Add or remove a flat boolean frontmatter field. Idempotent.

    When ``present`` is True the field is written as ``<field_name>: true`` (added
    if absent, left untouched if already true). When False the field line is
    removed if present. Returns True only when the file content actually changed,
    so callers can log / count real mutations and re-runs are no-ops (EC4).

    Only flat top-level frontmatter is touched; the body is preserved byte-equal.
    """
    text = path.read_text(encoding="utf-8")
    match = FRONTMATTER_RE.match(text)
    if not match:
        return False
    body = match.group(1)
    lines = body.splitlines()
    rest = text[match.end():]

    new_lines: list[str] = []
    found = False
    changed = False
    for line in lines:
        key = line.partition(":")[0].strip() if (":" in line and not line[:1].isspace()) else None
        if key == field_name:
            found = True
            if present:
                # Normalise the existing value to `true`; drop duplicates.
                normalized = f"{field_name}: true"
                if line != normalized:
                    changed = True
                if normalized not in new_lines:
                    new_lines.append(normalized)
            else:
                # Removal: skip the line.
                changed = True
            continue
        new_lines.append(line)

    if present and not found:
        new_lines.append(f"{field_name}: true")
        changed = True

    if not changed:
        return False
    path.write_text("---\n" + "\n".join(new_lines) + "\n---\n" + rest, encoding="utf-8")
    return True


def run_apply(memory_dir: Path, today: date, plan_stream) -> int:
    """Read a classification plan JSON from stdin and execute it.

    Actions per tier:
      - Hot: no move; appears in MEMORY.md Hot section.
      - Warm with topic: move to memory/{topic}/filename; record in {topic}/index.md.
      - Warm without topic: no move; stays flat; listed in MEMORY.md Warm-flat section.
      - Cold: move to memory/archive/filename; removed from MEMORY.md.

    Also: rewrites MEMORY.md, creates topic index files, writes .migration-log.md.
    """
    try:
        plan = json.load(plan_stream)
    except json.JSONDecodeError as e:
        print(f"Error: plan stdin is not valid JSON: {e}", file=sys.stderr)
        return 2

    classifications = plan.get("classifications", [])
    if not classifications:
        print("Error: plan has no classifications — nothing to do", file=sys.stderr)
        return 2

    index_path = memory_dir / "MEMORY.md"
    existing_entries, footer = parse_memory_index_entries(index_path)

    normalized_files: list[str] = []
    for c in classifications:
        src = memory_dir / c.get("file", "")
        if src.exists() and normalize_memory_file(src):
            normalized_files.append(src.name)

    # --- DP-282: durable per-file hot-overflow-demoted signal ----------------
    # Flat-root files that overflow Hot capacity stay flat (no move), so the only
    # canonical signal that they are no longer Hot must live in the file's own
    # frontmatter — MEMORY.md index alone is not consulted by validate-memory-
    # write.sh. Stamp the signal on overflow-demoted flat files (D1/D2); remove
    # it from every other flat file so re-qualified entries self-heal (D3).
    # pinned / graduated_to files are never overflow-demoted, so they never carry
    # the signal (D4). Must run BEFORE MEMORY.md rewrite / emit-index (EC3).
    overflow_demoted_signaled: list[str] = []
    overflow_signal_cleared: list[str] = []
    for c in classifications:
        fn = c.get("file", "")
        src = memory_dir / fn
        if not src.exists():
            continue
        # Only flat-root files are affected; topic-moved / cold files have already
        # been relocated by their own tier handling and leave the flat layer.
        is_overflow_demoted = (
            c.get("tier") == "warm"
            and not c.get("topic")
            and (c.get("reason", "") or "").startswith(OVERFLOW_REASON_PREFIX)
        )
        # D4 guard: never stamp pinned / graduated_to files even if a plan tried.
        fm = parse_frontmatter(src.read_text(encoding="utf-8"))
        if fm.pinned or fm.graduated_to:
            is_overflow_demoted = False
        if is_overflow_demoted:
            if set_frontmatter_bool_flag(src, HOT_OVERFLOW_DEMOTED_FIELD, True):
                overflow_demoted_signaled.append(fn)
        else:
            if set_frontmatter_bool_flag(src, HOT_OVERFLOW_DEMOTED_FIELD, False):
                overflow_signal_cleared.append(fn)

    # Fill in frontmatter fallback for orphans (files on disk but not in MEMORY.md)
    for c in classifications:
        fn = c["file"]
        if fn in existing_entries and existing_entries[fn].get("description"):
            continue
        src = memory_dir / fn
        if src.exists():
            try:
                fm = parse_frontmatter(src.read_text(encoding="utf-8"))
                existing_entries[fn] = {
                    "title": fm.name or fn,
                    "description": fm.description or "",
                    "strikethrough": False,
                }
            except Exception:
                pass

    # Group classifications
    hot: list[dict] = []
    warm_flat: list[dict] = []
    warm_topics: dict[str, list[dict]] = {}
    cold: list[dict] = []
    for c in classifications:
        if c["tier"] == "hot":
            hot.append(c)
        elif c["tier"] == "warm":
            if c["topic"]:
                warm_topics.setdefault(c["topic"], []).append(c)
            else:
                warm_flat.append(c)
        elif c["tier"] == "cold":
            cold.append(c)

    # Plan moves
    moves: list[tuple[Path, Path, str]] = []  # (src, dst, reason)
    archive_dir = memory_dir / "archive"
    for c in cold:
        src = memory_dir / c["file"]
        dst = archive_dir / c["file"]
        moves.append((src, dst, c["reason"]))
    for topic, items in warm_topics.items():
        topic_dir = memory_dir / topic
        for c in items:
            src = memory_dir / c["file"]
            dst = topic_dir / c["file"]
            moves.append((src, dst, c["reason"]))

    # Safety: check sources exist and destinations don't clash
    errors: list[str] = []
    for src, dst, _ in moves:
        if not src.exists():
            errors.append(f"source missing: {src.name}")
            continue
        if dst.exists():
            errors.append(f"destination already exists: {dst}")
    if errors:
        print("Error: cannot apply — safety checks failed:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 3

    # Create target folders
    for topic in warm_topics:
        (memory_dir / topic).mkdir(exist_ok=True)
    if cold:
        archive_dir.mkdir(exist_ok=True)

    # Execute moves
    log_entries: list[str] = []
    log_entries.append("# Memory Migration Log")
    log_entries.append("")
    log_entries.append(f"- Timestamp: {datetime.now().isoformat(timespec='seconds')}")
    log_entries.append(f"- Plan date: {plan.get('date', 'unknown')}")
    log_entries.append(f"- Moved: {len(moves)} file(s)")
    log_entries.append(f"- Hot (no move): {len(hot)}")
    log_entries.append(f"- Warm flat (no move): {len(warm_flat)}")
    log_entries.append(f"- Normalized frontmatter: {len(normalized_files)}")
    log_entries.append("")
    log_entries.append("## Moves")
    log_entries.append("")

    for src, dst, reason in moves:
        src.rename(dst)
        rel = dst.relative_to(memory_dir)
        log_entries.append(f"- `{src.name}` → `{rel}`  _(reason: {reason})_")
        print(f"  moved: {src.name} → {rel}")

    overflow_entries = [
        c for c in classifications
        if (c.get("reason", "") or "").startswith(OVERFLOW_REASON_PREFIX)
    ]
    if overflow_entries:
        log_entries.append("")
        log_entries.append("## Overflowed Hot capacity")
        log_entries.append("")
        log_entries.append(
            f"- Capacity: {MEMORY_HOT_CAPACITY} (env: MEMORY_HOT_CAPACITY)"
        )
        for c in sorted(overflow_entries, key=lambda x: x["file"]):
            topic = c.get("topic") or "(no topic)"
            log_entries.append(
                f"- `{c['file']}` → warm/{topic} — {OVERFLOW_REASON_PREFIX}"
            )

    if overflow_demoted_signaled or overflow_signal_cleared:
        log_entries.append("")
        log_entries.append("## Hot-overflow per-file signal")
        log_entries.append("")
        for name in sorted(overflow_demoted_signaled):
            log_entries.append(f"- `{name}` — stamped {HOT_OVERFLOW_DEMOTED_FIELD}: true")
        for name in sorted(overflow_signal_cleared):
            log_entries.append(f"- `{name}` — cleared {HOT_OVERFLOW_DEMOTED_FIELD}")

    if normalized_files:
        log_entries.append("")
        log_entries.append("## Frontmatter normalization")
        log_entries.append("")
        for name in sorted(normalized_files):
            log_entries.append(f"- `{name}`")

    # Write topic index files. Moves already executed above, so the shared
    # enumerator sees existing + just-moved files and reads each file's OWN
    # frontmatter for link text / summary (DP-277 T1 AC1/AC4).
    for topic in sorted(warm_topics):
        topic_index = memory_dir / topic / "index.md"
        folder_entries = enumerate_topic_folder(memory_dir, topic)
        lines = [f"# {topic} — Warm Memory", "",
                 "Topic folder for memory files moved out of Hot index.",
                 f"These files are loaded on-demand when {topic}-related work is active.",
                 "", "## Files", ""]
        for entry in folder_entries:
            title = entry["title"]
            fn = entry["file"]
            desc = entry["description"]
            if desc:
                lines.append(f"- [{title}]({fn}) — {desc}")
            else:
                lines.append(f"- [{title}]({fn})")
        lines.append("")
        topic_index.write_text("\n".join(lines), encoding="utf-8")
        print(f"  wrote index: {topic}/index.md ({len(folder_entries)} entries)")

    # Rewrite MEMORY.md
    def format_entry(c: dict, path_prefix: str = "") -> str:
        fn = c["file"]
        existing = existing_entries.get(fn, {})
        title = existing.get("title") or fn
        desc = existing.get("description") or ""
        link_target = f"{path_prefix}{fn}" if path_prefix else fn
        if desc:
            return f"- [{title}]({link_target}) — {desc}"
        return f"- [{title}]({link_target})"

    new_lines: list[str] = ["# Memory Index", ""]
    new_lines.append(f"_Last tiered: {today.isoformat()} ({len(hot)} Hot, "
                     f"{sum(len(v) for v in warm_topics.values()) + len(warm_flat)} Warm, "
                     f"{len(cold)} Cold → archive)_")
    new_lines.append("")

    new_lines.append(f"## Hot ({len(hot)}) — active, ≤{HOT_DAYS}d or pinned or trigger_count ≥ {HOT_TRIGGER_THRESHOLD}")
    new_lines.append("")
    # Sort Hot by last_triggered desc, mtime desc as tiebreak
    def hot_sort_key(c):
        lt = c.get("last_triggered")
        if lt:
            return (1, lt)
        return (0, c.get("mtime") or "1970-01-01")
    for c in sorted(hot, key=hot_sort_key, reverse=True):
        new_lines.append(format_entry(c))
    new_lines.append("")

    if warm_topics:
        new_lines.append(f"## Warm — per-topic folders ({len(warm_topics)} topics, "
                         f"{sum(len(v) for v in warm_topics.values())} files)")
        new_lines.append("")
        new_lines.append("Topic folders contain memory loaded on-demand. "
                         "Main session only pulls when relevant. "
                         "Click through to each folder's index.")
        new_lines.append("")
        for topic in sorted(warm_topics.keys()):
            count = len(warm_topics[topic])
            new_lines.append(f"- [{topic}/]({topic}/index.md) — {count} entries")
        new_lines.append("")

    if warm_flat:
        new_lines.append(f"## Warm — flat ({len(warm_flat)}) — no topic match yet")
        new_lines.append("")
        for c in sorted(warm_flat, key=lambda x: x["file"]):
            new_lines.append(format_entry(c))
        new_lines.append("")

    if cold:
        new_lines.append(f"## Archived ({len(cold)}) — moved to `archive/`")
        new_lines.append("")
        new_lines.append("Deprecated entries removed from active index. "
                         "See `archive/` for files and `.migration-log.md` for history.")
        new_lines.append("")

    # Preserve footer (Migrated to Company Handbook section)
    if footer:
        if new_lines and new_lines[-1] != "":
            new_lines.append("")
        new_lines.append(footer.rstrip())
        new_lines.append("")

    index_path.write_text("\n".join(new_lines), encoding="utf-8")
    print(f"  rewrote: MEMORY.md ({len(new_lines)} lines)")

    # Write migration log
    log_path = memory_dir / ".migration-log.md"
    existing_log = log_path.read_text(encoding="utf-8") if log_path.exists() else ""
    log_body = "\n".join(log_entries) + "\n"
    log_path.write_text(existing_log + log_body + "\n", encoding="utf-8")
    print("  appended: .migration-log.md")

    print()
    print(f"Migration complete: {len(moves)} moves, {len(hot)} Hot kept, "
          f"{len(warm_topics)} topic folders created.")
    print(f"Review: {index_path}")
    print(f"       {log_path}")
    return 0


# --- emit-index (DP-191 round 3) -----------------------------------------

EMIT_INDEX_START_MARKER = (
    "<!-- generated by memory-hygiene-tiering.py --emit-index | "
    "DO NOT EDIT THIS BLOCK -->"
)
EMIT_INDEX_END_MARKER = "<!-- end: memory-index generated block -->"


def split_emit_index_boundary(text: str) -> tuple[str, str]:
    """Split MEMORY.md text into (prefix_annotation, suffix_annotation).

    The rewrite target is the region between the markers; everything outside
    is preserved byte-equal.

    First emit (no markers present):
      - If a legacy `## Migrated to Company Handbook` footer exists, treat it
        as suffix annotation.
      - Otherwise, prefix and suffix are empty (whole file is regenerated).
    """
    if EMIT_INDEX_START_MARKER in text:
        start_idx = text.index(EMIT_INDEX_START_MARKER)
        prefix = text[:start_idx]
        rest = text[start_idx + len(EMIT_INDEX_START_MARKER):]
        if EMIT_INDEX_END_MARKER in rest:
            end_idx = rest.index(EMIT_INDEX_END_MARKER) + len(EMIT_INDEX_END_MARKER)
            suffix = rest[end_idx:]
            return prefix, suffix
        return prefix, ""
    m = MIGRATION_HEADER_RE.search(text)
    if m:
        suffix = text[m.start():]
        if not suffix.startswith("\n"):
            suffix = "\n\n" + suffix
        return "", suffix
    return "", ""


def emit_index_hot_sort_key(c: Classification) -> tuple[int, str]:
    if c.frontmatter.last_triggered:
        return (1, c.frontmatter.last_triggered.isoformat())
    return (0, c.mtime.isoformat() if c.mtime else "1970-01-01")


def emit_index_format_entry(
    c: Classification, existing_entries: dict[str, dict], path_prefix: str = ""
) -> str:
    fn = c.path.name
    existing = existing_entries.get(fn, {})
    title = existing.get("title") or c.frontmatter.name or fn
    desc = existing.get("description") or c.frontmatter.description or ""
    link_target = f"{path_prefix}{fn}" if path_prefix else fn
    if desc:
        return f"- [{title}]({link_target}) — {desc}"
    return f"- [{title}]({link_target})"


# Reserved subdirectories under memory_dir that are NOT topic folders.
RESERVED_MEMORY_SUBDIRS = {"archive"}


def discover_topic_folders(memory_dir: Path) -> list[str]:
    """Return sorted topic-folder names on disk, excluding reserved areas
    (archive/ Cold zone) and hidden dirs. Disk is the source of truth — a
    topic whose flat files are already migrated still appears."""
    topics = []
    for p in sorted(memory_dir.iterdir(), key=lambda x: x.name):
        if not p.is_dir():
            continue
        if p.name in RESERVED_MEMORY_SUBDIRS or p.name.startswith("."):
            continue
        topics.append(p.name)
    return topics


def enumerate_topic_folder(memory_dir: Path, topic: str) -> list[dict]:
    """Enumerate every memory .md in a topic folder, reading each file's own
    frontmatter for link text / summary. Returns dicts
    {"file","title","description"} sorted by filename, deduped by resolved real
    path. index.md and non-.md excluded. Missing frontmatter falls back to
    filename for link text and empty summary (no crash)."""
    folder = memory_dir / topic
    if not folder.is_dir():
        return []
    seen = set()
    entries = []
    for p in sorted(folder.iterdir(), key=lambda x: x.name):
        if not p.is_file() or p.suffix != ".md" or p.name == "index.md":
            continue
        key = str(p.resolve())
        if key in seen:
            continue
        seen.add(key)
        title, desc = p.name, ""
        try:
            fm = parse_frontmatter(p.read_text(encoding="utf-8"))
            title = fm.name or p.name
            desc = fm.description or ""
        except Exception:
            pass
        entries.append({"file": p.name, "title": title, "description": desc})
    return entries


def count_topic_folder_entries(memory_dir: Path, topic: str) -> int:
    return len(enumerate_topic_folder(memory_dir, topic))


def render_emit_index_block(
    memory_dir: Path,
    today: date,
    classifications: list[Classification],
    existing_entries: dict[str, dict],
) -> str:
    """Return the full marker-delimited generated block (markers included)."""
    hot = [c for c in classifications if c.tier == "hot"]
    warm = [c for c in classifications if c.tier == "warm"]
    cold = [c for c in classifications if c.tier == "cold"]
    warm_topics: dict[str, list[Classification]] = {}
    warm_flat: list[Classification] = []
    for c in warm:
        if c.topic:
            warm_topics.setdefault(c.topic, []).append(c)
        else:
            warm_flat.append(c)

    lines: list[str] = []
    lines.append(EMIT_INDEX_START_MARKER)
    lines.append("# Memory Index")
    lines.append("")
    lines.append(
        f"_Last tiered: {today.isoformat()} ({len(hot)} Hot, {len(warm)} Warm, "
        f"{len(cold)} Cold → archive)_"
    )
    lines.append("")

    lines.append(
        f"## Hot ({len(hot)}) — active, ≤{HOT_DAYS}d or pinned or trigger_count "
        f"≥ {HOT_TRIGGER_THRESHOLD}"
    )
    lines.append("")
    for c in sorted(hot, key=emit_index_hot_sort_key, reverse=True):
        lines.append(emit_index_format_entry(c, existing_entries))
    lines.append("")

    # Per-topic list is DISK-driven (DP-277 T1 AC2): a folder with files always
    # shows its pointer + count even when the flat layer has no topic-T file.
    all_topics = sorted(set(warm_topics) | set(discover_topic_folders(memory_dir)))
    if all_topics:
        topic_counts = {
            topic: (
                count_topic_folder_entries(memory_dir, topic)
                or len(warm_topics.get(topic, []))
            )
            for topic in all_topics
        }
        topic_total = sum(topic_counts.values())
        lines.append(
            f"## Warm — per-topic folders ({len(all_topics)} topics, "
            f"{topic_total} files)"
        )
        lines.append("")
        lines.append(
            "Topic folders contain memory loaded on-demand. Main session only "
            "pulls when relevant. Click through to each folder's index."
        )
        lines.append("")
        for topic in all_topics:
            count = topic_counts[topic]
            lines.append(f"- [{topic}/]({topic}/index.md) — {count} entries")
        lines.append("")

    if warm_flat:
        lines.append(
            f"## Warm — flat ({len(warm_flat)}) — no topic match yet"
        )
        lines.append("")
        for c in sorted(warm_flat, key=lambda x: x.path.name):
            lines.append(emit_index_format_entry(c, existing_entries))
        lines.append("")

    if cold:
        lines.append(f"## Archived ({len(cold)}) — moved to `archive/`")
        lines.append("")
        lines.append(
            "Deprecated entries removed from active index. See `archive/` for "
            "files and `.migration-log.md` for history."
        )
        lines.append("")

    lines.append(EMIT_INDEX_END_MARKER)
    return "\n".join(lines)


def assemble_emit_index_content(
    prefix: str, generated_block: str, suffix: str
) -> str:
    """Assemble (prefix + generated + suffix), normalising boundary newlines."""
    parts: list[str] = []
    if prefix:
        parts.append(prefix)
        if not prefix.endswith("\n"):
            parts.append("\n")
    parts.append(generated_block)
    if suffix:
        if not suffix.startswith("\n"):
            parts.append("\n")
        parts.append(suffix)
    else:
        parts.append("\n")
    return "".join(parts)


def run_emit_index(memory_dir: Path, today: date, dry_run: bool) -> int:
    classifications, _orphans, _missing = collect(memory_dir, today)
    index_path = memory_dir / "MEMORY.md"
    old_text = (
        index_path.read_text(encoding="utf-8") if index_path.exists() else ""
    )
    existing_entries, _legacy_footer = parse_memory_index_entries(index_path)

    prefix, suffix = split_emit_index_boundary(old_text)
    generated_block = render_emit_index_block(
        memory_dir, today, classifications, existing_entries
    )
    new_text = assemble_emit_index_content(prefix, generated_block, suffix)

    if dry_run:
        diff = "".join(
            difflib.unified_diff(
                old_text.splitlines(keepends=True),
                new_text.splitlines(keepends=True),
                fromfile=str(index_path),
                tofile=str(index_path) + ".emit-index",
            )
        )
        if diff:
            sys.stdout.write(diff)
            if not diff.endswith("\n"):
                sys.stdout.write("\n")
        else:
            print(f"[emit-index] no changes: {index_path}")
        return 0

    if new_text == old_text:
        print(f"[emit-index] unchanged: {index_path}")
        return 0

    index_path.write_text(new_text, encoding="utf-8")
    print(f"[emit-index] wrote: {index_path}")
    return 0


# --- Entry point ----------------------------------------------------------

def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Memory Hot/Warm/Cold tiering helper (DP-015 Part B).")
    parser.add_argument("mode", nargs="?",
                        choices=["dry-run", "apply", "decay-scan"],
                        default=None,
                        help="legacy positional modes; use --emit-index for the round 3 producer")
    parser.add_argument("--emit-index", action="store_true",
                        help="regenerate MEMORY.md from live memory frontmatter "
                             "(round 3 generated artifact producer)")
    parser.add_argument("--memory-dir", type=Path, default=DEFAULT_MEMORY_DIR,
                        help=f"Memory directory (default: {DEFAULT_MEMORY_DIR})")
    parser.add_argument("--json", action="store_true",
                        help="(dry-run) emit machine-readable JSON instead of markdown report")
    parser.add_argument("--dry-run", action="store_true",
                        help="(--emit-index) print unified diff to stdout; do not write")
    parser.add_argument("--today", type=str, default=None,
                        help="Override today's date (YYYY-MM-DD) for testing")
    args = parser.parse_args(argv)

    if not args.memory_dir.exists():
        print(f"Error: memory dir {args.memory_dir} does not exist", file=sys.stderr)
        return 2

    today = (datetime.strptime(args.today, "%Y-%m-%d").date()
             if args.today else date.today())

    if args.emit_index:
        if args.mode is not None:
            parser.error("--emit-index cannot be combined with a positional mode")
        return run_emit_index(args.memory_dir, today, args.dry_run)
    if args.mode is None:
        parser.error("mode required (one of dry-run|apply|decay-scan) or use --emit-index")
    if args.dry_run and args.mode != "dry-run":
        parser.error("--dry-run is only valid with --emit-index")
    if args.mode == "dry-run":
        return run_dry_run(args.memory_dir, today, args.json)
    if args.mode == "decay-scan":
        return run_decay_scan(args.memory_dir, today)
    if args.mode == "apply":
        return run_apply(args.memory_dir, today, sys.stdin)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
