#!/usr/bin/env python3
"""Parse and validate the Polaris toolchain manifest.

The manifest intentionally uses a small YAML subset so the runner can work
before tool dependencies are installed.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


REQUIRED_COMMANDS = {
    "docs.viewer": {"install", "dev", "build", "doctor"},
    "fixtures.mockoon": {"install", "start", "stop", "status", "doctor"},
    "browser.playwright": {"install", "install-browser", "verify", "doctor"},
}


def _scalar(value: str):
    value = value.strip()
    if value in {"true", "false"}:
        return value == "true"
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1]
    try:
        return int(value)
    except ValueError:
        return value


def parse_manifest(path: Path) -> dict:
    root: dict = {}
    stack: list[tuple[int, dict]] = [(-1, root)]

    for lineno, raw_line in enumerate(path.read_text().splitlines(), start=1):
        if not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue
        if "\t" in raw_line:
            raise ValueError(f"line {lineno}: tabs are not allowed")
        indent = len(raw_line) - len(raw_line.lstrip(" "))
        if indent % 2 != 0:
            raise ValueError(f"line {lineno}: indentation must use two-space steps")
        line = raw_line.strip()
        if ":" not in line:
            raise ValueError(f"line {lineno}: expected key: value")
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            raise ValueError(f"line {lineno}: empty key")

        while stack and indent <= stack[-1][0]:
            stack.pop()
        parent = stack[-1][1]
        if value == "":
            child: dict = {}
            parent[key] = child
            stack.append((indent, child))
        else:
            parent[key] = _scalar(value)

    return root


def validate(data: dict) -> list[str]:
    errors: list[str] = []
    if data.get("version") != 1:
        errors.append("version must be 1")

    minimum = data.get("minimum_environment")
    if not isinstance(minimum, dict):
        errors.append("minimum_environment must be an object")
    else:
        for key in ("shell", "node", "package_manager", "python"):
            if not isinstance(minimum.get(key), str) or not minimum[key].strip():
                errors.append(f"minimum_environment.{key} must be a non-empty string")

    capabilities = data.get("capabilities")
    if not isinstance(capabilities, dict) or not capabilities:
        errors.append("capabilities must be a non-empty object")
        return errors

    command_id = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$")
    for capability_id, capability in capabilities.items():
        if not command_id.match(capability_id):
            errors.append(f"invalid capability id: {capability_id}")
            continue
        if not isinstance(capability, dict):
            errors.append(f"{capability_id} must be an object")
            continue
        if not isinstance(capability.get("required"), bool):
            errors.append(f"{capability_id}.required must be boolean")
        package_dir = capability.get("package_dir")
        if not isinstance(package_dir, str) or not package_dir.strip():
            errors.append(f"{capability_id}.package_dir must be a non-empty string")
        commands = capability.get("commands")
        if not isinstance(commands, dict) or not commands:
            errors.append(f"{capability_id}.commands must be a non-empty object")
            continue
        for command_name, command in commands.items():
            if not re.match(r"^[a-z][a-z0-9-]*$", command_name):
                errors.append(f"{capability_id}.commands.{command_name} has invalid command name")
            if not isinstance(command, str) or not command.strip():
                errors.append(f"{capability_id}.commands.{command_name} must be a non-empty string")

        required_commands = REQUIRED_COMMANDS.get(capability_id, set())
        missing = sorted(required_commands - set(commands))
        if missing:
            errors.append(f"{capability_id}.commands missing required commands: {', '.join(missing)}")

    for capability_id in REQUIRED_COMMANDS:
        if capability_id not in capabilities:
            errors.append(f"missing required capability: {capability_id}")

    return errors


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--required", action="store_true")
    parser.add_argument("--command")
    args = parser.parse_args(argv)

    path = Path(args.manifest)
    data = parse_manifest(path)
    errors = validate(data)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    if args.command:
        try:
            capability_id, command_name = args.command.rsplit(".", 1)
            capability = data["capabilities"][capability_id]
            command = capability["commands"][command_name]
        except KeyError:
            print(f"unknown toolchain command: {args.command}", file=sys.stderr)
            return 2
        print(command)
        return 0

    if args.required:
        capabilities = {
            key: value
            for key, value in data["capabilities"].items()
            if value.get("required") is True
        }
        data = {**data, "capabilities": capabilities}

    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
