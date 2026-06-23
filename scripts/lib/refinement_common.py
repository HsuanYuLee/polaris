#!/usr/bin/env python3
from pathlib import Path
import json
import re


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def container_from(path):
    p = Path(path)
    if p.is_dir():
        return p
    return p.parent


def _strip_frontmatter(text):
    """Drop the leading ``---``...``---`` YAML frontmatter block.

    DP-345 D3: refinement.md may carry a frontmatter ``description`` that
    literally contains a ``## heading`` (DP-344-T1 collision shape). Stripping
    the frontmatter before section parsing prevents that literal from being
    mistaken for a real body section.

    Args:
        text: Full refinement.md (or task.md) text.

    Returns:
        The body text with any leading frontmatter block removed.
    """
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "".join(lines[i + 1 :])
    return text


def section(text, heading):
    """Return the body of a ``## {heading}`` section, frontmatter-aware.

    Short-term DP-345 fix (long-term: read refinement.json, DP-346). Strips the
    frontmatter block, then line-anchors on ``^## `` so only a real body heading
    matches — the same idiom as parse-task-md.sh.

    Args:
        text: Full refinement.md text.
        heading: Heading label without the leading ``## ``.

    Returns:
        The section body (lines between this heading and the next ``## ``),
        or an empty string when the heading is absent.
    """
    body = _strip_frontmatter(text)
    marker = f"## {heading}"
    lines = body.splitlines()
    start = None
    for idx, line in enumerate(lines):
        if line.rstrip() == marker or line.startswith(marker + " "):
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


def refinement_paths(input_path):
    container = container_from(input_path)
    return container, container / "refinement.md", container / "refinement.json"


def ac_blob(data):
    chunks = []
    for item in data.get("acceptance_criteria") or []:
        ver = item.get("verification") or {}
        chunks.extend([str(item.get("id") or ""), str(item.get("text") or ""), str(ver.get("detail") or "")])
    return "\n".join(chunks)


def md_table_rows(block):
    rows = []
    for raw in block.splitlines():
        if not raw.strip().startswith("|"):
            continue
        cells = [c.strip().strip("`") for c in raw.strip().strip("|").split("|")]
        if len(cells) >= 2 and not set(cells[0]) <= {"-", ":"}:
            rows.append(cells)
    return rows[1:] if rows and rows[0][0] in {"Path", "檔案"} else rows


def path_tokens(text):
    return re.findall(r"`([^`]+)`", text)
