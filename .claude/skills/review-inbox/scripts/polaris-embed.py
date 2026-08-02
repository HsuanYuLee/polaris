#!/usr/bin/env python3
"""Polaris learnings semantic index — build + query via local fastembed."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import date, datetime
from pathlib import Path

DEFAULT_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
DEFAULT_VERSION = "1"
INDEX_SCHEMA_VERSION = 1


def die(msg: str, code: int = 2) -> None:
    print(f"polaris-embed: {msg}", file=sys.stderr)
    sys.exit(code)


def content_hash(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def load_learnings(path: Path) -> list[dict]:
    if not path.exists() or path.stat().st_size == 0:
        return []
    entries = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        entries.append(json.loads(line))
    return entries


def load_index(path: Path) -> dict:
    if not path.exists() or path.stat().st_size == 0:
        return {"version": INDEX_SCHEMA_VERSION, "entries": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    data.setdefault("entries", {})
    return data


def save_index(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def entry_id(entry: dict) -> str:
    return f"{entry['key']}::{entry['type']}"


def embed_texts(texts: list[str], model_name: str):
    from fastembed import TextEmbedding  # lazy import — venv may not exist otherwise

    model = TextEmbedding(model_name=model_name)
    return [list(map(float, v)) for v in model.embed(texts)]


def cosine(a: list[float], b: list[float]) -> float:
    # Vectors are not guaranteed normalized; normalize here for safety.
    dot = 0.0
    na = 0.0
    nb = 0.0
    for x, y in zip(a, b):
        dot += x * y
        na += x * x
        nb += y * y
    if na == 0 or nb == 0:
        return 0.0
    return dot / ((na**0.5) * (nb**0.5))


def effective_confidence(entry: dict, today: date) -> int:
    try:
        lc = datetime.strptime(entry.get("last_confirmed", ""), "%Y-%m-%d").date()
    except ValueError:
        return int(entry.get("confidence", 0))
    decay = (today - lc).days // 30
    return int(entry.get("confidence", 0)) - decay


def cmd_embed(args) -> None:
    vec = embed_texts([args.text], args.model)[0]
    print(json.dumps({"model": args.model, "version": args.version, "vector": vec}))


def cmd_build_index(args) -> None:
    learnings_path = Path(args.learnings)
    index_path = Path(args.output)
    learnings = load_learnings(learnings_path)
    index = load_index(index_path)
    entries_map = index["entries"]

    to_embed: list[tuple[str, str]] = []  # (entry_id, text)
    for entry in learnings:
        eid = entry_id(entry)
        text = entry.get("content", "")
        ch = content_hash(text)
        existing = entries_map.get(eid)
        needs = (
            args.force
            or existing is None
            or existing.get("text_hash") != ch
            or existing.get("embedding_model") != args.model
            or existing.get("embedding_version") != args.version
        )
        if needs:
            to_embed.append((eid, text))

    # Remove index entries whose learning entry no longer exists.
    valid_ids = {entry_id(e) for e in learnings}
    stale = [eid for eid in entries_map if eid not in valid_ids]
    for eid in stale:
        del entries_map[eid]

    if not to_embed:
        save_index(index_path, index)
        print(json.dumps({"added": 0, "removed": len(stale), "total": len(entries_map), "model": args.model}))
        return

    vectors = embed_texts([t for _, t in to_embed], args.model)
    for (eid, text), vec in zip(to_embed, vectors):
        entries_map[eid] = {
            "embedding_model": args.model,
            "embedding_version": args.version,
            "text_hash": content_hash(text),
            "vector": vec,
        }
    save_index(index_path, index)
    print(json.dumps({"added": len(to_embed), "removed": len(stale), "total": len(entries_map), "model": args.model}))


def cmd_query(args) -> None:
    learnings_path = Path(args.learnings)
    index_path = Path(args.embeddings)
    learnings = load_learnings(learnings_path)
    index = load_index(index_path)
    entries_map = index["entries"]

    if not entries_map:
        return  # silent: no index yet

    # Detect index model drift — refuse if query model != stored model.
    any_record = next(iter(entries_map.values()))
    stored_model = any_record.get("embedding_model", DEFAULT_MODEL)
    if args.model != stored_model:
        die(
            f"model mismatch: index was built with '{stored_model}' but query requested '{args.model}'. "
            f"Run reindex to rebuild.",
            code=3,
        )

    # Embed the query with the same model.
    qvec = embed_texts([args.query], args.model)[0]

    learnings_by_id = {entry_id(e): e for e in learnings}
    today = date.today()
    min_conf = args.min_confidence
    company = args.company

    scored = []
    for eid, record in entries_map.items():
        entry = learnings_by_id.get(eid)
        if entry is None:
            continue
        if entry.get("promoted") is True:
            continue
        if company:
            entry_company = entry.get("company", "")
            if entry_company and entry_company != company:
                continue
        eff = effective_confidence(entry, today)
        if eff < min_conf:
            continue
        sim = cosine(qvec, record["vector"])
        if sim < args.min_similarity:
            continue
        scored.append((sim, eff, entry))

    scored.sort(key=lambda x: (x[0], x[1]), reverse=True)
    for sim, eff, entry in scored[: args.top]:
        enriched = dict(entry)
        enriched["effective_confidence"] = eff
        enriched["similarity"] = round(sim, 4)
        print(json.dumps(enriched, ensure_ascii=False))


def main() -> None:
    parser = argparse.ArgumentParser(prog="polaris-embed")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_embed = sub.add_parser("embed", help="Embed a single text, print vector as JSON")
    p_embed.add_argument("--text", required=True)
    p_embed.add_argument("--model", default=DEFAULT_MODEL)
    p_embed.add_argument("--version", default=DEFAULT_VERSION)
    p_embed.set_defaults(func=cmd_embed)

    p_build = sub.add_parser("build-index", help="Build or refresh the embeddings index")
    p_build.add_argument("--learnings", required=True)
    p_build.add_argument("--output", required=True)
    p_build.add_argument("--model", default=DEFAULT_MODEL)
    p_build.add_argument("--version", default=DEFAULT_VERSION)
    p_build.add_argument("--force", action="store_true")
    p_build.set_defaults(func=cmd_build_index)

    p_query = sub.add_parser("query", help="Semantic query; prints top-N entries as JSONL")
    p_query.add_argument("--learnings", required=True)
    p_query.add_argument("--embeddings", required=True)
    p_query.add_argument("--query", required=True)
    p_query.add_argument("--top", type=int, default=5)
    p_query.add_argument("--min-confidence", type=int, default=0)
    p_query.add_argument("--min-similarity", type=float, default=0.0)
    p_query.add_argument("--company", default="")
    p_query.add_argument("--model", default=DEFAULT_MODEL)
    p_query.set_defaults(func=cmd_query)

    args = parser.parse_args()
    try:
        args.func(args)
    except ModuleNotFoundError as e:
        die(f"missing Python dependency: {e}. Run scripts/polaris-embed-setup.sh first.", code=4)


if __name__ == "__main__":
    main()
