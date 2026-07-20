"""Structured validator authority extracted from scripts/validate-verify-evidence-layout.sh."""

import json
import sys
from pathlib import Path

ALLOWED_ASSET_DIRS = {"raw", "images", "screenshots", "videos", "files"}


def fail(path: Path, msg: str) -> str:
    return f"{path}: {msg}"


def validate_dir(raw: str) -> list[str]:
    root = Path(raw)
    errors: list[str] = []
    if not root.is_dir():
        return [fail(root, "evidence dir not found")]
    for required in ("verify-report.md", "links.json", "publication-manifest.json"):
        if not (root / required).is_file():
            errors.append(fail(root, f"missing {required}"))
    assets = root / "assets"
    if not assets.is_dir():
        errors.append(fail(root, "missing assets/"))
    else:
        for name in ALLOWED_ASSET_DIRS:
            if not (assets / name).is_dir():
                errors.append(fail(root, f"missing assets/{name}/"))
        for child in assets.iterdir():
            if child.is_dir() and child.name not in ALLOWED_ASSET_DIRS:
                errors.append(
                    fail(root, f"unknown assets subdir: assets/{child.name}/")
                )
    for md in root.glob("*.md"):
        if md.name != "verify-report.md":
            errors.append(fail(root, f"unexpected markdown file: {md.name}"))
    links_path = root / "links.json"
    if links_path.is_file():
        try:
            links = json.loads(links_path.read_text(encoding="utf-8"))
            if not isinstance(links, list):
                errors.append(fail(root, "links.json must be an array"))
        except Exception as exc:
            errors.append(fail(root, f"links.json invalid JSON: {exc}"))
    manifest_path = root / "publication-manifest.json"
    if manifest_path.is_file():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if not isinstance(manifest, dict):
                errors.append(fail(root, "publication-manifest.json must be an object"))
            else:
                if manifest.get("schema_version") != 1:
                    errors.append(
                        fail(root, "publication-manifest.json schema_version must be 1")
                    )
                if not isinstance(manifest.get("artifacts"), list):
                    errors.append(
                        fail(
                            root, "publication-manifest.json artifacts must be an array"
                        )
                    )
        except Exception as exc:
            errors.append(fail(root, f"publication-manifest.json invalid JSON: {exc}"))
    return errors


all_errors: list[str] = []
for arg in sys.argv[1:]:
    all_errors.extend(validate_dir(arg))
if all_errors:
    print("FAIL: verify evidence layout", file=sys.stderr)
    for error in all_errors:
        print(f"  - {error}", file=sys.stderr)
    raise SystemExit(1)
print(f"PASS: verify evidence layout ({len(sys.argv) - 1} dir(s))")
