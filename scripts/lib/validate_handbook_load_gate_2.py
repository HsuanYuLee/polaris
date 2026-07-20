"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

from pathlib import Path
import sys

root = Path(sys.argv[1]) / "polaris-config"
configs = sorted(root.glob("*/handbook/config.yaml")) if root.is_dir() else []
if len(configs) == 1:
    print(configs[0].parents[1].name)
elif len(configs) > 1:
    print("POLARIS_AMBIGUOUS", file=sys.stderr)
    raise SystemExit(2)
