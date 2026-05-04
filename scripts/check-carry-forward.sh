#!/usr/bin/env bash
# scripts/check-carry-forward.sh
#
# Purpose: When a new checkpoint-style project memory is being written,
#          compare its "next steps / pending" section against the previous
#          checkpoint memory on the same topic. If the new checkpoint
#          silently drops items from the previous pending list without an
#          explicit disposition (done / carry-forward / dropped), fail.
#
# Canary: cross-session-carry-forward (L2 primary in checkpoint skill;
#         L1 PreToolUse on Write/Edit to memory paths as fallback).
#
# Exit codes:
#   0 — PASS (no drop detected, or no prior checkpoint to diff against)
#   1 — RECOVERABLE_FAIL (usage error, missing args — caller can fix)
#   2 — HARD_STOP (silent drop detected; LLM retry would only encourage
#       faking pending items rather than producing real dispositions)
#
# Why exit 2 (not 1): D4 of DP-030 plan — for this canary the only
# "retry path" is to forge a pending list that passes the diff. That is
# exactly what we want to prevent. The correct response is to STOP and
# surface the diff to the user so they decide which items are done /
# carry-forward / dropped.
#
# Usage:
#   check-carry-forward.sh --new-checkpoint <path> --memory-dir <dir>
#
# Invoked by:
#   - .claude/skills/checkpoint/SKILL.md Step 2.5 (L2 primary)

set -u

# --- Arg parsing ---
new_checkpoint=""
memory_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --new-checkpoint)
      new_checkpoint="${2:-}"
      shift 2
      ;;
    --new-checkpoint=*)
      new_checkpoint="${1#--new-checkpoint=}"
      shift
      ;;
    --memory-dir)
      memory_dir="${2:-}"
      shift 2
      ;;
    --memory-dir=*)
      memory_dir="${1#--memory-dir=}"
      shift
      ;;
    -h|--help)
      sed -n '2,40p' "$0" >&2
      exit 0
      ;;
    *)
      echo "check-carry-forward.sh: unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

# --- Input validation (exit 1 = recoverable) ---
if [[ -z "$new_checkpoint" || -z "$memory_dir" ]]; then
  cat >&2 <<EOF
Usage: check-carry-forward.sh --new-checkpoint <path> --memory-dir <dir>

Required flags:
  --new-checkpoint  Path to the new/proposed checkpoint memory file
  --memory-dir      Root memory directory (contains prior project memories)
EOF
  exit 1
fi

if [[ ! -f "$new_checkpoint" ]]; then
  echo "check-carry-forward.sh: --new-checkpoint not found: $new_checkpoint" >&2
  exit 1
fi

if [[ ! -d "$memory_dir" ]]; then
  echo "check-carry-forward.sh: --memory-dir not found: $memory_dir" >&2
  exit 1
fi

# --- Core logic ---
# We delegate the heuristic to python3 (available everywhere in this
# project) to avoid unreadable sed/awk. The script below:
#   1. Extracts topic identifier from new checkpoint frontmatter (`topic:`
#      or `name:` field — prefer `topic`, fall back to a prefix match on
#      `name` like "DP-030", "EPIC-478", etc.)
#   2. Scans memory_dir (top level + one level deep for topic folders)
#      for `type: project` files whose frontmatter `topic:` matches, or
#      whose `name:` contains the same topic identifier. Picks the most
#      recent one BEFORE the new checkpoint (by mtime, excluding the new
#      file itself).
#   3. From that previous checkpoint extracts pending items (bullet lines
#      under sections titled "下一步 / next / pending / 待實施 / still
#      pending / 未完成 / carry-forward / next steps").
#   4. Checks new checkpoint for (a) disposition markers per item or
#      (b) keyword coverage in its own next-steps section.
#   5. Missing items → stderr list + exit 2. Otherwise exit 0.

python3 - "$new_checkpoint" "$memory_dir" <<'PY_EOF'
import os
import re
import sys
from pathlib import Path

new_cp = Path(sys.argv[1])
mem_dir = Path(sys.argv[2])

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "of", "for", "to", "in", "on",
    "at", "by", "is", "are", "was", "were", "be", "been", "being", "has",
    "have", "had", "do", "does", "did", "will", "would", "should", "could",
    "may", "might", "can", "must", "shall", "this", "that", "these",
    "those", "it", "its", "with", "as", "from", "not", "no", "yes",
    "still", "pending",
    # Chinese fillers
    "的", "是", "和", "或", "在", "有", "了", "但", "就",
    "還", "要", "去", "做", "再", "先", "後", "已", "已經", "還沒",
}

# Disposition markers (case-insensitive for English tokens)
DISPOSITION_RE = re.compile(
    r"\((?:a|b|c)\)\s*(done|carry[-\s]?forward|dropped|完成|繼續|已做|已經完成|保留|放棄|不做)",
    re.IGNORECASE,
)

# Headings that likely indicate pending-work sections.
PENDING_HEADING_RE = re.compile(
    r"(?i)(下一步|下步|next\s*steps?|pending|待實施|still\s+pending|未完成|carry[-\s]?forward|TODO|還沒做|尚未|接下來)"
)


def parse_frontmatter(text):
    """Parse YAML-ish frontmatter at the top; return dict or {}."""
    if not text.startswith("---"):
        return {}
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}
    fm_raw = parts[1]
    out = {}
    for line in fm_raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def frontmatter_type(text):
    fm = parse_frontmatter(text)
    return fm.get("type", "")


def extract_topic_identifier(text):
    """Return a topic slug to match against other memories.

    Priority:
      1. frontmatter `topic:` field
      2. a pattern like DP-NNN / GT-NNN / KB2CW-NNN / [A-Z]+-\\d+ from
         frontmatter `name:` or first H1 heading
    """
    fm = parse_frontmatter(text)
    if fm.get("topic"):
        return fm["topic"].lower()
    name = fm.get("name", "")
    haystacks = [name]
    # Also consider first H1
    m = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if m:
        haystacks.append(m.group(1))
    for hs in haystacks:
        m2 = re.search(r"\b([A-Z]{2,}-\d+|DP-\d+)\b", hs)
        if m2:
            return m2.group(1).lower()
    return ""


def find_prior_checkpoint(new_path, mem_dir, topic):
    """Find the most recent project memory matching topic, older than
    new_path (by mtime). Searches mem_dir and one level of subdirs."""
    if not topic:
        return None
    candidates = []
    pat = re.compile(re.escape(topic), re.IGNORECASE)
    search_roots = [mem_dir]
    for child in mem_dir.iterdir():
        if child.is_dir() and not child.name.startswith("."):
            search_roots.append(child)
    for root in search_roots:
        for f in root.glob("*.md"):
            if f.resolve() == new_path.resolve():
                continue
            try:
                text = f.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue
            if frontmatter_type(text) != "project":
                continue
            # Match topic: frontmatter topic OR name OR filename OR content
            other_topic = extract_topic_identifier(text)
            if other_topic == topic:
                pass  # match
            elif pat.search(f.name) or pat.search(text[:2000]):
                pass
            else:
                continue
            try:
                mtime = f.stat().st_mtime
            except OSError:
                continue
            candidates.append((mtime, f))
    if not candidates:
        return None
    # Pick most recent; if new checkpoint already exists on disk with a
    # newer mtime we exclude it explicitly above.
    candidates.sort(reverse=True)
    return candidates[0][1]


def extract_pending_items(text):
    """Return list of dict {line, keywords} for bullet items found under
    pending-style sections."""
    lines = text.splitlines()
    items = []
    in_pending = False
    current_heading_level = None

    for raw in lines:
        # Detect markdown heading
        h = re.match(r"^(#{1,6})\s+(.+)$", raw)
        if h:
            lvl = len(h.group(1))
            heading_text = h.group(2).strip()
            if PENDING_HEADING_RE.search(heading_text):
                in_pending = True
                current_heading_level = lvl
            elif in_pending and current_heading_level is not None and lvl <= current_heading_level:
                # New heading at same or higher level ends pending section
                in_pending = False
                current_heading_level = None
            continue
        if not in_pending:
            continue
        # Bullet line (- or * or numeric) with non-empty content
        b = re.match(r"^\s*(?:[-*+]|\d+\.)\s+(.*\S.*)$", raw)
        if b:
            content = b.group(1).strip()
            if not content:
                continue
            items.append(content)
    return items


def tokenize(text):
    """Lowercase alnum tokens (includes CJK characters) minus stopwords."""
    # Preserve CJK characters as individual tokens too
    # Split on non-alnum (unicode), keep meaningful words
    tokens = re.findall(r"[A-Za-z0-9_-]+|[一-鿿]+", text.lower())
    out = []
    for t in tokens:
        if t in STOPWORDS:
            continue
        if len(t) == 1 and not re.match(r"[一-鿿]", t):
            continue  # skip single ASCII char
        out.append(t)
    return out


def item_covered(item, new_cp_text, new_cp_next_block):
    """Check if a prior pending item is covered in the new checkpoint.

    Covered if:
      (a) The item line contains a disposition marker like (a) done / (b)
          carry-forward / (c) dropped — indicating the user explicitly
          addressed it, OR
      (b) Keywords from the item appear in the new checkpoint's next-steps
          section (strict), OR in full new checkpoint text (lenient,
          any explicit mention with a done / 完成 / dropped / 放棄 marker)
    """
    if DISPOSITION_RE.search(item):
        return True
    tokens = tokenize(item)
    # Very short items — low signal, treat as covered to avoid noise
    if len(tokens) < 2:
        return True
    # Strong tokens: tickets/identifiers like DP-030, EPIC-478, TASK-3900
    id_tokens = [t for t in tokens if re.match(r"^[a-z]+-\d+$", t) or re.match(r"^dp-\d+$", t)]
    # If item has identifiers, require at least one ID match
    if id_tokens:
        for it in id_tokens:
            if it in new_cp_text.lower():
                return True
        return False
    # Otherwise require ≥ 2 keyword matches in the new checkpoint
    matches = 0
    haystack = (new_cp_next_block + "\n" + new_cp_text).lower()
    for t in tokens:
        if t in haystack:
            matches += 1
            if matches >= 2:
                return True
    return False


def extract_next_section(text):
    """Return only the 'next steps' section text of the new checkpoint
    (used for stricter coverage checks)."""
    lines = text.splitlines()
    out = []
    in_section = False
    current_level = None
    for raw in lines:
        h = re.match(r"^(#{1,6})\s+(.+)$", raw)
        if h:
            lvl = len(h.group(1))
            heading = h.group(2).strip()
            if PENDING_HEADING_RE.search(heading):
                in_section = True
                current_level = lvl
                continue
            elif in_section and current_level is not None and lvl <= current_level:
                in_section = False
                current_level = None
                continue
        if in_section:
            out.append(raw)
    return "\n".join(out)


def main():
    try:
        new_text = new_cp.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        print(f"check-carry-forward: cannot read {new_cp}: {e}", file=sys.stderr)
        return 1

    # Ensure new checkpoint is a project memory; if not, skip (L1 hook
    # fallback fires on any memory path — non-project memories are fine
    # to let through silently).
    new_type = frontmatter_type(new_text)
    if new_type != "project":
        return 0

    topic = extract_topic_identifier(new_text)
    if not topic:
        # No identifiable topic → cannot reliably find a prior checkpoint.
        # First-in-series case. Allow through.
        return 0

    prior = find_prior_checkpoint(new_cp, mem_dir, topic)
    if prior is None:
        # No prior checkpoint on the same topic — nothing to diff.
        return 0

    try:
        prior_text = prior.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return 0

    prior_pending = extract_pending_items(prior_text)
    if not prior_pending:
        return 0

    new_next_block = extract_next_section(new_text)

    missing = []
    for item in prior_pending:
        if not item_covered(item, new_text, new_next_block):
            missing.append(item)

    if not missing:
        return 0

    print("", file=sys.stderr)
    print(
        "[cross-session-carry-forward] HARD_STOP: new checkpoint appears to drop "
        "previous pending items without explicit disposition.",
        file=sys.stderr,
    )
    print(f"  New checkpoint: {new_cp}", file=sys.stderr)
    print(f"  Prior checkpoint: {prior}", file=sys.stderr)
    print(f"  Topic: {topic}", file=sys.stderr)
    print("", file=sys.stderr)
    print("Missing items from prior pending list (no disposition detected):", file=sys.stderr)
    for m in missing[:20]:
        display = m if len(m) <= 140 else m[:137] + "..."
        print(f"  - {display}", file=sys.stderr)
    if len(missing) > 20:
        print(f"  ... and {len(missing) - 20} more", file=sys.stderr)
    print("", file=sys.stderr)
    print(
        "Resolve by marking each item one of:\n"
        "  (a) done            — completed in this session\n"
        "  (b) carry-forward   — still pending, preserved in next steps\n"
        "  (c) dropped         — no longer relevant (include reason)\n"
        "Then rewrite the checkpoint memory and re-invoke the skill/Write.\n"
        "This is a hard-stop: retry without genuine disposition will only "
        "forge pass signals — the check is doing its job.",
        file=sys.stderr,
    )
    return 2


sys.exit(main())
PY_EOF

# Propagate python's exit code explicitly (already does).
