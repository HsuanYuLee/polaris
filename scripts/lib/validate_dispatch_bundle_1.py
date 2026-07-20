"""Structured validator authority extracted from scripts/validate-dispatch-bundle.sh."""

import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
patterns = [
    r"(讀取|讀|Read|read|load|Load).{0,80}review-pr/SKILL\.md",
    r"(讀取|讀|Read|read|load|Load).{0,80}review-pr-[A-Za-z0-9_-]+-flow\.md",
    r"(讀取|讀|Read|read|load|Load).{0,80}repo-handbook\.md",
]
for pattern in patterns:
    if re.search(pattern, text, re.IGNORECASE | re.DOTALL):
        sys.exit(0)
sys.exit(1)
