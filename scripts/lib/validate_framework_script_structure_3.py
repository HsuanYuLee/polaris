"""Structured validator authority extracted from scripts/validate-framework-script-structure.sh."""

from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
is_cli = (
    'if __name__ == "__main__"' in text
    or "if __name__ == '__main__'" in text
    or "sys.argv" in text
)
if not is_cli:
    raise SystemExit(0)
if "argparse.ArgumentParser" not in text:
    print("missing argparse.ArgumentParser")
    raise SystemExit(1)
if "allow_abbrev=False" not in text:
    print("missing allow_abbrev=False")
    raise SystemExit(1)
