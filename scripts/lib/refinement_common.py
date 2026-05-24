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


def section(text, heading):
    marker = f"## {heading}"
    start = text.find(marker)
    if start == -1:
        return ""
    start = text.find("\n", start)
    if start == -1:
        return ""
    end = text.find("\n## ", start + 1)
    return text[start + 1 :] if end == -1 else text[start + 1 : end]


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
