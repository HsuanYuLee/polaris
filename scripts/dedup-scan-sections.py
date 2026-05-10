#!/usr/bin/env python3
"""
Section-level overlap scanner.
Splits files by ## headers, then compares sections across files.
Targets: mechanism-registry embedding rule summaries, Common Rationalizations duplication.

Usage: python3 scripts/dedup-scan-sections.py
"""

import re
from pathlib import Path

CLAUDE_DIR = Path(__file__).resolve().parent.parent / ".claude"
SCAN_DIRS = [CLAUDE_DIR / "rules", CLAUDE_DIR / "skills" / "references"]
SKIP_FILES = {"INDEX.md"}


def tokenize(text: str) -> list[str]:
    text = re.sub(r"```[\s\S]*?```", "", text)
    text = re.sub(r"`[^`]+`", "", text)
    text = re.sub(r"^#+\s+", "", text, flags=re.MULTILINE)
    text = re.sub(r"\*\*|__", "", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"^>\s+", "", text, flags=re.MULTILINE)
    return re.findall(r"[a-z0-9\u4e00-\u9fff\u3400-\u4dbf]+", text.lower())


def bigrams(words):
    return set((words[i], words[i + 1]) for i in range(len(words) - 1))


def split_sections(text: str) -> list[dict]:
    """Split by ## or ### headers into sections."""
    sections = []
    pattern = re.compile(r"^(#{2,4})\s+(.+)$", re.MULTILINE)
    matches = list(pattern.finditer(text))

    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end].strip()
        if len(body) < 50:  # skip tiny sections
            continue
        words = tokenize(body)
        if len(words) < 15:
            continue
        sections.append(
            {
                "header": m.group(2).strip(),
                "level": len(m.group(1)),
                "words": words,
                "bigrams": bigrams(words),
                "word_count": len(words),
            }
        )
    return sections


def containment(small: set, large: set) -> float:
    if not small:
        return 0.0
    return len(small & large) / len(small)


def relative_label(path: Path) -> str:
    return str(path.relative_to(CLAUDE_DIR))


def main():
    files = []
    for d in SCAN_DIRS:
        if d.exists():
            for f in sorted(d.rglob("*.md")):
                if f.name not in SKIP_FILES:
                    files.append(f)

    print(f"Scanning {len(files)} files for section-level overlap...\n")

    # Build per-file sections
    file_sections: dict[Path, list[dict]] = {}
    total_sections = 0
    for f in files:
        text = f.read_text(encoding="utf-8")
        secs = split_sections(text)
        if secs:
            file_sections[f] = secs
            total_sections += len(secs)

    print(f"Extracted {total_sections} sections across {len(file_sections)} files\n")

    # Compare sections across different files
    results = []
    file_list = list(file_sections.keys())

    for i, fa in enumerate(file_list):
        for fb in file_list[i + 1 :]:
            for sa in file_sections[fa]:
                for sb in file_sections[fb]:
                    if not sa["bigrams"] or not sb["bigrams"]:
                        continue

                    # Containment: smaller ⊂ larger
                    if sa["word_count"] <= sb["word_count"]:
                        small_sec, small_file = sa, fa
                        large_sec, large_file = sb, fb
                    else:
                        small_sec, small_file = sb, fb
                        large_sec, large_file = sa, fa

                    c = containment(small_sec["bigrams"], large_sec["bigrams"])

                    if c >= 0.40:
                        shared = small_sec["bigrams"] & large_sec["bigrams"]
                        results.append(
                            {
                                "small_file": small_file,
                                "small_header": small_sec["header"],
                                "small_words": small_sec["word_count"],
                                "large_file": large_file,
                                "large_header": large_sec["header"],
                                "large_words": large_sec["word_count"],
                                "containment": c,
                                "shared_count": len(shared),
                            }
                        )

    results.sort(key=lambda r: r["containment"], reverse=True)

    if not results:
        print("No section pairs exceed the containment threshold (40%).")
        return

    # Group by relationship type
    print(f"Found {len(results)} section pairs with ≥40% containment\n")

    # Classify
    registry_pairs = []
    rationalization_pairs = []
    other_pairs = []

    for r in results:
        sf = relative_label(r["small_file"])
        lf = relative_label(r["large_file"])
        is_registry = "mechanism-registry" in sf or "mechanism-registry" in lf
        is_rational = "rationalization" in r["small_header"].lower() or "rationalization" in r["large_header"].lower()

        if is_registry:
            registry_pairs.append(r)
        elif is_rational:
            rationalization_pairs.append(r)
        else:
            other_pairs.append(r)

    def print_group(title, pairs):
        if not pairs:
            return
        print(f"\n{'=' * 100}")
        print(f"  {title} ({len(pairs)} pairs)")
        print(f"{'=' * 100}")
        for r in pairs[:15]:
            sf = relative_label(r["small_file"])
            lf = relative_label(r["large_file"])
            print(
                f"\n  {r['containment']:.0%} containment | {r['shared_count']} shared bigrams"
            )
            print(f"  SMALLER: {sf} § {r['small_header']} ({r['small_words']}w)")
            print(f"  LARGER:  {lf} § {r['large_header']} ({r['large_words']}w)")

    print_group("MECHANISM REGISTRY ↔ SOURCE RULES (expected embedding)", registry_pairs)
    print_group("COMMON RATIONALIZATIONS (cross-file duplication)", rationalization_pairs)
    print_group("OTHER OVERLAP", other_pairs)

    # Summary recommendations
    print(f"\n{'=' * 100}")
    print("  RECOMMENDATIONS")
    print(f"{'=' * 100}")

    if registry_pairs:
        high_registry = [r for r in registry_pairs if r["containment"] >= 0.60]
        print(
            f"\n  Mechanism Registry: {len(registry_pairs)} overlaps with source rules "
            f"({len(high_registry)} at ≥60% containment)"
        )
        print(
            "  → Expected: registry summarizes rules. But if containment ≥80%, "
            "the registry may be copying verbatim instead of summarizing."
        )

    if rationalization_pairs:
        print(
            f"\n  Common Rationalizations: {len(rationalization_pairs)} cross-file duplications"
        )
        print(
            "  → Consider: extract shared rationalizations into a single reference "
            "and import from multiple files."
        )

    if other_pairs:
        high_other = [r for r in other_pairs if r["containment"] >= 0.60]
        print(f"\n  Other: {len(other_pairs)} pairs ({len(high_other)} at ≥60%)")
        print("  → Review high-containment pairs for merge opportunities.")

    print()


if __name__ == "__main__":
    main()
