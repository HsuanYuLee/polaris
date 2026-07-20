"""Structured validator authority extracted from scripts/validate-polaris-command-catalog.sh."""

import json
import os
import re
import sys

root, catalog_path, package_path, mise_path = sys.argv[1:5]
errors = []
required_categories = {"viewer", "toolchain", "runtime", "scripts", "maintainer"}
required_ids = {
    "viewer.dev",
    "viewer.preview",
    "viewer.status",
    "viewer.stop",
    "viewer.verify",
    "toolchain.install",
    "toolchain.doctor",
    "toolchain.manifest",
    "scripts.check",
    "commands.check",
    "runtime.bootstrap",
    "runtime.doctor",
    "runtime.doctor-mise",
    "runtime.onboard-doctor",
    "runtime.release-preflight",
    "runtime.pr-create",
    "runtime.spec-close-parent",
    "runtime.script-audit",
    "runtime.docs-health",
    "runtime.verify",
    "runtime.cross-runtime-sync",
    "maintainer.framework-release",
    "maintainer.framework-docs-health",
}
allowed_direct_human_prefixes = ("bash scripts/polaris-toolchain.sh",)


def fail(message):
    errors.append(message)


def is_allowed_direct_human_surface(value):
    if not isinstance(value, str):
        return False
    return value.startswith(allowed_direct_human_prefixes)


try:
    with open(catalog_path, encoding="utf-8") as fh:
        catalog = json.load(fh)
except Exception as exc:
    print(f"command catalog is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    with open(package_path, encoding="utf-8") as fh:
        package = json.load(fh)
except Exception as exc:
    print(f"package.json is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    mise_text = open(mise_path, encoding="utf-8").read()
except Exception as exc:
    print(f"mise.toml is not readable: {exc}", file=sys.stderr)
    sys.exit(1)

if catalog.get("version") != 1:
    fail("version must be 1")

categories = catalog.get("categories")
if not isinstance(categories, list):
    fail("categories must be an array")
else:
    missing = sorted(required_categories - set(categories))
    if missing:
        fail(f"missing required categories: {', '.join(missing)}")

commands = catalog.get("commands")
if not isinstance(commands, list) or not commands:
    fail("commands must be a non-empty array")
    commands = []

scripts = package.get("scripts") if isinstance(package, dict) else {}
if not isinstance(scripts, dict):
    fail("package.json scripts must be an object")
    scripts = {}

mise_tasks = {}
current_task = None
for raw in mise_text.splitlines():
    task_match = re.match(r"\[tasks\.([A-Za-z0-9_-]+)\]\s*$", raw.strip())
    if task_match:
        current_task = task_match.group(1)
        mise_tasks.setdefault(current_task, {})
        continue
    run_match = re.match(r'run\s*=\s*"([^"]+)"\s*$', raw.strip())
    if current_task and run_match:
        mise_tasks[current_task]["run"] = run_match.group(1)

seen = set()
valid_id = re.compile(r"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$")
for idx, row in enumerate(commands):
    label = f"commands[{idx}]"
    if not isinstance(row, dict):
        fail(f"{label}: row must be an object")
        continue
    cid = row.get("id")
    if not isinstance(cid, str) or not valid_id.match(cid):
        fail(f"{label}: invalid id {cid!r}")
        continue
    if cid in seen:
        fail(f"{cid}: duplicate command id")
    seen.add(cid)

    category = row.get("category")
    if category not in required_categories:
        fail(f"{cid}: invalid category {category!r}")
    surface = row.get("surface")
    if surface not in {"human", "skill", "maintainer-only"}:
        fail(f"{cid}: invalid surface {surface!r}")
    canonical = row.get("canonical")
    implementation = row.get("implementation")
    owner = row.get("owner")
    lifecycle = row.get("lifecycle")
    for key, value in (
        ("canonical", canonical),
        ("implementation", implementation),
        ("owner", owner),
        ("lifecycle", lifecycle),
    ):
        if not isinstance(value, str) or not value.strip():
            fail(f"{cid}: {key} must be a non-empty string")

    if surface == "human":
        if isinstance(canonical, str) and canonical.startswith("pnpm "):
            script_name = canonical.split()[1]
            package_script = scripts.get(script_name)
            if package_script is None:
                fail(f"{cid}: package.json is missing script {script_name!r}")
            elif package_script != implementation:
                fail(
                    f"{cid}: package script {script_name!r} does not match implementation"
                )
        elif isinstance(canonical, str) and canonical.startswith("mise run "):
            parts = canonical.split()
            if len(parts) < 3:
                fail(f"{cid}: invalid mise canonical surface")
            else:
                task_name = parts[2]
                task = mise_tasks.get(task_name)
                if task is None:
                    fail(f"{cid}: mise.toml is missing task {task_name!r}")
                elif task.get("run") != implementation:
                    fail(
                        f"{cid}: mise task {task_name!r} does not match implementation"
                    )
        elif is_allowed_direct_human_surface(canonical):
            if canonical != implementation:
                fail(f"{cid}: direct human command canonical must match implementation")
        else:
            fail(
                f"{cid}: human canonical surface must be a pnpm thin alias, "
                "a mise public task, or an allowed Polaris toolchain wrapper"
            )
        if isinstance(owner, str) and owner.startswith("scripts/"):
            owner_path = os.path.join(root, owner)
            if not os.path.isfile(owner_path):
                fail(f"{cid}: owner script does not exist: {owner}")

    if (
        surface == "maintainer-only"
        and isinstance(canonical, str)
        and canonical.startswith("pnpm ")
    ):
        fail(
            f"{cid}: maintainer-only commands must not be exposed as root pnpm scripts"
        )

missing_ids = sorted(required_ids - seen)
if missing_ids:
    fail(f"missing required command ids: {', '.join(missing_ids)}")

if errors:
    print("validate-polaris-command-catalog FAIL", file=sys.stderr)
    for error in errors:
        print(f"  - {error}", file=sys.stderr)
    sys.exit(1)

print(f"PASS: Polaris command catalog ({len(commands)} commands)")
