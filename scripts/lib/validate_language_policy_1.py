"""Structured validator authority extracted from scripts/validate-language-policy.sh."""

import re
import sys
from pathlib import Path

enforcement = sys.argv[1]
mode = sys.argv[2]
language = sys.argv[3]
files = sys.argv[4:]

if mode not in {
    "artifact",
    "json-fields",
    "bilingual",
    "bilingual-source",
    "bilingual-translation",
}:
    print(
        f"error: unsupported mode '{mode}' (expected artifact|json-fields|bilingual|bilingual-source|bilingual-translation)",
        file=sys.stderr,
    )
    sys.exit(2)

if enforcement not in {"blocking", "advisory"}:
    print(f"error: unsupported enforcement '{enforcement}'", file=sys.stderr)
    sys.exit(2)

if not files:
    print("error: no artifact files supplied", file=sys.stderr)
    sys.exit(2)

if not language:
    missing = [f for f in files if not Path(f).is_file()]
    if missing:
        for f in missing:
            print(f"error: file not found: {f}", file=sys.stderr)
        sys.exit(2)
    print(
        "language_unset: no non-empty language found in workspace-config.yaml ancestry",
        file=sys.stderr,
    )
    sys.exit(1 if enforcement == "blocking" else 0)

if mode in {
    "bilingual",
    "bilingual-source",
    "bilingual-translation",
} or language not in {"zh-TW", "zh-Hant", "zh"}:
    missing = [f for f in files if not Path(f).is_file()]
    if missing:
        for f in missing:
            print(f"error: file not found: {f}", file=sys.stderr)
        sys.exit(2)
    sys.exit(0)

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
URL_RE = re.compile(r"https?://\S+|www\.\S+")
INLINE_CODE_RE = re.compile(r"`[^`]*`")
HTML_TAG_RE = re.compile(r"<[^>]+>")
TICKET_RE = re.compile(r"\b[A-Z][A-Z0-9]+-\d+(?:-T\d+[a-z]*)?\b")
BRANCH_RE = re.compile(
    r"\b(?:task|feat|feature|bugfix|hotfix|release|wip|origin|main|develop|master|rc)/[A-Za-z0-9._/-]+\b"
)
PATH_RE = re.compile(r"(?:^|\s)(?:[./~]?[A-Za-z0-9._-]+/)+(?:[A-Za-z0-9._-]+)?")
FLAG_RE = re.compile(r"(?<!\w)--?[A-Za-z][A-Za-z0-9_-]*(?:[= ][A-Za-z0-9._/:@-]+)?")
ENV_RE = re.compile(r"\b[A-Z][A-Z0-9_]{2,}\b")
KEY_VALUE_RE = re.compile(
    r"^\s*[-*]?\s*[A-Za-z0-9_.-]+\s*[:=]\s*(?:[`'\"]?[A-Za-z0-9_.:/-]+[`'\"]?)?\s*$"
)
MARKDOWN_LINK_RE = re.compile(r"\[[^\]]+\]\([^)]+\)")
WORD_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?")

FUNCTION_WORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "because",
    "by",
    "can",
    "could",
    "do",
    "does",
    "for",
    "from",
    "has",
    "have",
    "if",
    "in",
    "into",
    "is",
    "it",
    "its",
    "must",
    "not",
    "of",
    "on",
    "or",
    "should",
    "that",
    "the",
    "their",
    "there",
    "these",
    "this",
    "to",
    "was",
    "were",
    "when",
    "where",
    "which",
    "will",
    "with",
    "without",
    "would",
    "you",
    "your",
}


def strip_markdown_prefix(line: str) -> str:
    line = re.sub(r"^\s{0,3}>\s?", "", line)
    line = re.sub(r"^\s*[-*+]\s+", "", line)
    line = re.sub(r"^\s*\d+[.)]\s+", "", line)
    return line.strip()


def is_structural_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    if stripped.startswith("|"):
        return True
    if re.match(r"^\s{0,3}#{1,6}\s+", stripped):
        return True
    if re.match(r"^\s*-{3,}\s*$", stripped):
        return True
    if stripped.startswith("```") or stripped.startswith("~~~"):
        return True
    if KEY_VALUE_RE.match(stripped):
        return True
    return False


def paragraphs(path: Path):
    in_fence = False
    fence_marker = ""
    current = []

    def flush():
        nonlocal current
        if current:
            yield " ".join(current).strip()
            current = []

    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = raw.strip()
        if stripped.startswith(("```", "~~~")):
            yield from flush()
            if not in_fence:
                in_fence = True
                fence_marker = stripped[:3]
            elif stripped.startswith(fence_marker):
                in_fence = False
            continue
        if in_fence:
            continue
        if is_structural_line(raw):
            yield from flush()
            continue
        is_list_item = bool(re.match(r"^\s*(?:[-*+]|\d+[.)])\s+", raw))
        if is_list_item:
            yield from flush()
        line = strip_markdown_prefix(raw)
        if not line:
            yield from flush()
            continue
        if is_list_item:
            yield line
        else:
            current.append(line)
    yield from flush()


def cleaned_for_language(text: str) -> str:
    text = INLINE_CODE_RE.sub(" ", text)
    text = MARKDOWN_LINK_RE.sub(" ", text)
    text = URL_RE.sub(" ", text)
    text = HTML_TAG_RE.sub(" ", text)
    text = TICKET_RE.sub(" ", text)
    text = BRANCH_RE.sub(" ", text)
    text = PATH_RE.sub(" ", text)
    text = FLAG_RE.sub(" ", text)
    text = ENV_RE.sub(" ", text)
    text = re.sub(
        r"\b[A-Za-z0-9_.-]+\.(?:sh|py|js|ts|tsx|vue|json|ya?ml|md|txt)\b", " ", text
    )
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\(\)", " ", text)
    text = re.sub(r"\b[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.-]+\b", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def is_full_english_natural_language(text: str) -> bool:
    if CJK_RE.search(text):
        return False
    cleaned = cleaned_for_language(text)
    if CJK_RE.search(cleaned):
        return False
    alpha_chars = sum(ch.isalpha() and ch.isascii() for ch in cleaned)
    if alpha_chars < 45:
        return False
    words = [w.lower() for w in WORD_RE.findall(cleaned)]
    if len(words) < 8:
        return False
    function_count = sum(1 for w in words if w in FUNCTION_WORDS)
    if function_count < 3:
        return False
    identifierish = sum(1 for w in words if "_" in w or any(ch.isdigit() for ch in w))
    if identifierish / max(len(words), 1) > 0.35:
        return False
    return True


def is_english_prose_field(text: str) -> bool:
    """Per-field English detector for json-fields mode.

    Unlike is_full_english_natural_language (tuned for long document
    paragraphs), this targets short human-facing prose fields that are known
    to be natural language (a refinement.json task title / scope / AC text).
    It reuses the same inline-code / code-token strip heuristic so a zh-TW
    field that merely wraps a technical identifier in backticks is never
    flagged (AC-NEG2). After stripping code, the residue must contain ≥2
    English words and ≥1 English function word for the field to be classed as
    English prose — short enough to catch an English title, strict enough to
    let an all-code residue through.
    """
    if not text or not text.strip():
        return False
    if CJK_RE.search(text):
        return False
    cleaned = cleaned_for_language(text)
    if CJK_RE.search(cleaned):
        return False
    words = [w.lower() for w in WORD_RE.findall(cleaned)]
    if len(words) < 2:
        return False
    function_count = sum(1 for w in words if w in FUNCTION_WORDS)
    if function_count < 1:
        return False
    identifierish = sum(1 for w in words if "_" in w or any(ch.isdigit() for ch in w))
    if identifierish / max(len(words), 1) > 0.5:
        return False
    return True


def json_prose_fields(data):
    """Yield (field_path, text) for each human-facing prose field in a
    refinement.json document: tasks[].title, tasks[].scope,
    acceptance_criteria[].text. Missing / non-string fields are skipped."""
    tasks = data.get("tasks") if isinstance(data, dict) else None
    if isinstance(tasks, list):
        for i, task in enumerate(tasks):
            if not isinstance(task, dict):
                continue
            for field in ("title", "scope"):
                value = task.get(field)
                if isinstance(value, str):
                    yield f"tasks[{i}].{field}", value
    acs = data.get("acceptance_criteria") if isinstance(data, dict) else None
    if isinstance(acs, list):
        for i, ac in enumerate(acs):
            if not isinstance(ac, dict):
                continue
            value = ac.get("text")
            if isinstance(value, str):
                yield f"acceptance_criteria[{i}].text", value


violations = []
for file_name in files:
    path = Path(file_name)
    if not path.is_file():
        print(f"error: file not found: {file_name}", file=sys.stderr)
        sys.exit(2)
    if mode == "json-fields":
        import json

        try:
            data = json.loads(path.read_text(encoding="utf-8", errors="replace"))
        except json.JSONDecodeError as exc:
            print(f"error: invalid JSON in {path}: {exc}", file=sys.stderr)
            sys.exit(2)
        for field_path, text in json_prose_fields(data):
            if is_english_prose_field(text):
                snippet = re.sub(r"\s+", " ", text).strip()
                if len(snippet) > 140:
                    snippet = snippet[:137] + "..."
                violations.append((str(path), field_path, snippet))
    else:
        for idx, para in enumerate(paragraphs(path), start=1):
            if is_full_english_natural_language(para):
                snippet = re.sub(r"\s+", " ", para).strip()
                if len(snippet) > 140:
                    snippet = snippet[:137] + "..."
                violations.append((str(path), idx, snippet))

if violations:
    label = (
        "language policy violations"
        if enforcement == "blocking"
        else "language policy advisory findings"
    )
    print(f"✗ {label}:", file=sys.stderr)
    for path, locator, snippet in violations:
        if mode == "json-fields":
            print(
                f"  - {path}: field {locator}: full English prose under zh-TW policy",
                file=sys.stderr,
            )
        else:
            print(
                f"  - {path}: paragraph {locator}: full English natural-language paragraph under zh-TW policy",
                file=sys.stderr,
            )
        print(f"    {snippet}", file=sys.stderr)
    sys.exit(1 if enforcement == "blocking" else 0)

sys.exit(0)
