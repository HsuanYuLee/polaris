#!/usr/bin/env python3
"""
Token-level bigram overlap scanner for rules/ and skills/references/.
Finds file pairs with high content overlap to guide dedup decisions.

Usage: python3 scripts/dedup-scan.py [--threshold 0.3] [--top 20]
"""

import argparse
import re
from itertools import combinations
from pathlib import Path

CLAUDE_DIR = Path(__file__).resolve().parent.parent / ".claude"

SCAN_DIRS = [
    CLAUDE_DIR / "rules",
    CLAUDE_DIR / "skills" / "references",
]

# Skip non-content files
SKIP_FILES = {"INDEX.md"}


def tokenize(text: str) -> list[str]:
    """Lowercase, strip markdown formatting, split into words."""
    # Remove markdown tables' pipe structure but keep cell content
    text = re.sub(r"^\|[-:| ]+\|$", "", text, flags=re.MULTILINE)
    # Remove markdown syntax
    text = re.sub(r"```[\s\S]*?```", "", text)  # code blocks
    text = re.sub(r"`[^`]+`", "", text)  # inline code
    text = re.sub(r"^#+\s+", "", text, flags=re.MULTILINE)  # headers
    text = re.sub(r"\*\*|__", "", text)  # bold
    text = re.sub(r"\*|_", "", text)  # italic
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)  # links → text
    text = re.sub(r"^>\s+", "", text, flags=re.MULTILINE)  # blockquotes
    text = re.sub(r"^[-*]\s+", "", text, flags=re.MULTILINE)  # list markers
    text = re.sub(r"^\d+\.\s+", "", text, flags=re.MULTILINE)  # ordered list
    # Remove frontmatter-like lines
    text = re.sub(r"^---\s*$", "", text, flags=re.MULTILINE)
    # Normalize whitespace
    words = re.findall(r"[a-z0-9\u4e00-\u9fff\u3400-\u4dbf]+", text.lower())
    return words


def bigrams(words: list[str]) -> list[tuple[str, str]]:
    """Generate bigrams from word list."""
    return [(words[i], words[i + 1]) for i in range(len(words) - 1)]


def jaccard(set_a: set, set_b: set) -> float:
    """Jaccard similarity between two sets."""
    if not set_a or not set_b:
        return 0.0
    intersection = set_a & set_b
    union = set_a | set_b
    return len(intersection) / len(union)


def containment(set_a: set, set_b: set) -> float:
    """How much of set_a is contained in set_b (asymmetric)."""
    if not set_a:
        return 0.0
    return len(set_a & set_b) / len(set_a)


def collect_files() -> list[Path]:
    """Collect all .md files from scan directories."""
    files = []
    for scan_dir in SCAN_DIRS:
        if not scan_dir.exists():
            continue
        for f in sorted(scan_dir.rglob("*.md")):
            if f.name in SKIP_FILES:
                continue
            files.append(f)
    return files


def relative_label(path: Path) -> str:
    """Short label relative to .claude/"""
    return str(path.relative_to(CLAUDE_DIR))


def main():
    parser = argparse.ArgumentParser(description="Bigram overlap dedup scanner")
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.15,
        help="Minimum Jaccard similarity to report (default: 0.15)",
    )
    parser.add_argument(
        "--top", type=int, default=30, help="Max pairs to show (default: 30)"
    )
    parser.add_argument(
        "--containment-threshold",
        type=float,
        default=0.35,
        help="Minimum containment ratio to report (default: 0.35)",
    )
    args = parser.parse_args()

    files = collect_files()
    print(f"Scanning {len(files)} files...\n")

    # Build bigram sets
    file_data: dict[Path, dict] = {}
    for f in files:
        text = f.read_text(encoding="utf-8")
        words = tokenize(text)
        bg = set(bigrams(words))
        file_data[f] = {
            "words": len(words),
            "bigrams": bg,
            "bigram_count": len(bg),
        }

    # Compare all pairs
    results = []
    for fa, fb in combinations(files, 2):
        da, db = file_data[fa], file_data[fb]
        if not da["bigrams"] or not db["bigrams"]:
            continue
        j = jaccard(da["bigrams"], db["bigrams"])
        # Containment: how much of the smaller file is in the larger
        if da["bigram_count"] <= db["bigram_count"]:
            smaller, larger = fa, fb
            c = containment(da["bigrams"], db["bigrams"])
        else:
            smaller, larger = fb, fa
            c = containment(db["bigrams"], da["bigrams"])

        if j >= args.threshold or c >= args.containment_threshold:
            shared = da["bigrams"] & db["bigrams"]
            results.append(
                {
                    "file_a": fa,
                    "file_b": fb,
                    "jaccard": j,
                    "containment": c,
                    "smaller": smaller,
                    "larger": larger,
                    "shared_count": len(shared),
                    "shared_sample": sorted(shared)[:10],
                }
            )

    # Sort by Jaccard desc
    results.sort(key=lambda r: r["jaccard"], reverse=True)

    if not results:
        print("No file pairs exceed the overlap threshold.")
        return

    # Print results
    print(f"{'Pair':<85} {'Jaccard':>8} {'Contain':>8} {'Shared':>7}")
    print("-" * 115)

    for r in results[: args.top]:
        la = relative_label(r["file_a"])
        lb = relative_label(r["file_b"])
        pair = f"{la}  ↔  {lb}"
        if len(pair) > 84:
            pair = pair[:81] + "..."
        print(
            f"{pair:<85} {r['jaccard']:>7.1%} {r['containment']:>7.1%} {r['shared_count']:>6}bg"
        )

    # Detailed report for top pairs
    print(f"\n{'=' * 115}")
    print("DETAILED ANALYSIS (top pairs)")
    print(f"{'=' * 115}")

    for i, r in enumerate(results[: min(10, args.top)]):
        la = relative_label(r["file_a"])
        lb = relative_label(r["file_b"])
        da = file_data[r["file_a"]]
        db = file_data[r["file_b"]]
        print(f"\n--- Pair {i+1} ---")
        print(f"  A: {la} ({da['words']} words, {da['bigram_count']} unique bigrams)")
        print(f"  B: {lb} ({db['words']} words, {db['bigram_count']} unique bigrams)")
        print(f"  Jaccard: {r['jaccard']:.1%}  |  Containment({relative_label(r['smaller'])} ⊂ {relative_label(r['larger'])}): {r['containment']:.1%}")
        print(f"  Shared bigrams ({r['shared_count']}), sample: {r['shared_sample']}")

        # Classify
        if r["jaccard"] >= 0.30:
            verdict = "HIGH OVERLAP — likely true duplication, merge candidate"
        elif r["containment"] >= 0.50:
            verdict = "HIGH CONTAINMENT — smaller file may be subset of larger"
        elif r["jaccard"] >= 0.20:
            verdict = "MODERATE OVERLAP — same topic, check if different angle"
        else:
            verdict = "LOW-MODERATE — related topic, probably intentional"
        print(f"  Verdict: {verdict}")

    print(f"\nTotal pairs above threshold: {len(results)}")


if __name__ == "__main__":
    main()
