#!/usr/bin/env python3
"""Hold every PR-blocking gate to one of two states: covered, or disclosed.

Inputs:
    --repo <owner/name>     GitHub repo whose rulesets declare required checks.
    --codecov <path>        codecov.yml to read flag statuses from.
    --declaration <path>    ci-coverage.yaml listing covered / disclosed gates.
    --base <branch>         Base branch to filter rulesets by (default: the
                            repo's default branch condition).

Outputs:
    exit 0 when every discovered gate is accounted for; exit 1 when any gate is
    in neither list. Unreadable declaration sources never fail the run, but they
    are always reported as gaps — skipping one silently is the failure this is
    guarding against, so silence is not an option the code has.

The point is not to re-implement CI locally. It is to make the set of things
that can block a PR knowable before the PR exists, so that the ones without a
local equivalent are a written decision rather than a surprise.
"""

import argparse
import json
import subprocess
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - environment contract, not logic
    print("POLARIS_TOOL_MISSING:pyyaml", file=sys.stderr)
    print("Repair: run mise install, then mise run doctor -- --profile runtime",
          file=sys.stderr)
    raise SystemExit(2)


class Gap(Exception):
    """A declaration source could not be read. Reported, never swallowed."""


def discover_ruleset_gates(repo, base):
    """Collect required status check contexts from a repo's active rulesets.

    Args:
        repo: "owner/name".
        base: Base branch name, or None to accept every active branch ruleset.

    Returns:
        A set of check context strings.

    Raises:
        Gap: when the GitHub CLI is absent or the API call does not succeed.
    """
    try:
        listing = subprocess.run(
            ["gh", "api", f"repos/{repo}/rulesets"],
            capture_output=True, text=True, check=False,
        )
    except FileNotFoundError:
        raise Gap("gh is not on PATH; ruleset-declared gates were not discovered")

    if listing.returncode != 0:
        detail = listing.stderr.strip().splitlines()
        raise Gap(f"gh api repos/{repo}/rulesets failed: "
                  f"{detail[0] if detail else 'no stderr'}")

    gates = set()
    for summary in json.loads(listing.stdout or "[]"):
        if summary.get("enforcement") != "active":
            continue
        detail = subprocess.run(
            ["gh", "api", f"repos/{repo}/rulesets/{summary['id']}"],
            capture_output=True, text=True, check=False,
        )
        if detail.returncode != 0:
            raise Gap(f"ruleset {summary['id']} ({summary.get('name')}) "
                      f"could not be read")
        ruleset = json.loads(detail.stdout)

        if base is not None:
            include = (ruleset.get("conditions", {})
                       .get("ref_name", {})
                       .get("include", []))
            refs = {"~DEFAULT_BRANCH", "~ALL", f"refs/heads/{base}"}
            if not refs.intersection(include):
                continue

        for rule in ruleset.get("rules", []):
            if rule.get("type") != "required_status_checks":
                continue
            for check in rule.get("parameters", {}).get(
                    "required_status_checks", []):
                context = check.get("context")
                if context:
                    gates.add(context)
    return gates


def discover_codecov_gates(path):
    """Collect gate names from codecov flag statuses.

    The global `coverage.status` block is deliberately not read: a repo may
    disable it there and set the real thresholds per flag, in which case the
    global block says the opposite of the truth.

    Args:
        path: Path to codecov.yml.

    Returns:
        A set of "codecov/{type}/{flag}" strings.

    Raises:
        Gap: when the file cannot be read or parsed.
    """
    try:
        with open(path, encoding="utf-8") as handle:
            config = yaml.safe_load(handle) or {}
    except OSError as exc:
        raise Gap(f"{path} could not be read: {exc.strerror}")
    except yaml.YAMLError as exc:
        raise Gap(f"{path} is not valid YAML: {exc}")

    gates = set()
    flags = (config.get("flag_management", {})
             .get("individual_flags", []) or [])
    for flag in flags:
        name = flag.get("name")
        for status in flag.get("statuses", []) or []:
            kind = status.get("type")
            if name and kind:
                gates.add(f"codecov/{kind}/{name}")
    return gates


def load_declaration(path):
    """Read the covered / disclosed lists.

    Args:
        path: Path to ci-coverage.yaml.

    Returns:
        (covered, disclosed) as sets of gate names.
    """
    with open(path, encoding="utf-8") as handle:
        declaration = yaml.safe_load(handle) or {}
    covered = {entry["gate"] for entry in declaration.get("covered", []) or []}
    disclosed = {entry["gate"] for entry in declaration.get("disclosed", []) or []}
    overlap = covered & disclosed
    if overlap:
        print("POLARIS_GATE_DECLARED_TWICE", file=sys.stderr)
        print(f"a gate cannot be both covered and disclosed: {sorted(overlap)}",
              file=sys.stderr)
        raise SystemExit(1)
    return covered, disclosed


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--codecov", required=True)
    parser.add_argument("--declaration", required=True)
    parser.add_argument("--base", default=None)
    args = parser.parse_args()

    covered, disclosed = load_declaration(args.declaration)
    accounted = covered | disclosed

    discovered = set()
    gaps = []
    for label, discover in (
        ("github-rulesets", lambda: discover_ruleset_gates(args.repo, args.base)),
        ("codecov", lambda: discover_codecov_gates(args.codecov)),
    ):
        try:
            discovered |= discover()
        except Gap as gap:
            gaps.append(f"{label}: {gap}")

    for gap in gaps:
        print(f"GAP: {gap}", file=sys.stderr)

    unaccounted = sorted(discovered - accounted)
    if unaccounted:
        print("POLARIS_GATE_SILENT_THIRD_STATE", file=sys.stderr)
        print("these gates can block a PR but are neither covered by local "
              "measurement nor disclosed:", file=sys.stderr)
        for gate in unaccounted:
            print(f"  {gate}", file=sys.stderr)
        print("", file=sys.stderr)
        print(f"Add each to covered or disclosed in {args.declaration}.",
              file=sys.stderr)
        return 1

    stale = sorted(accounted - discovered)
    summary = (f"{len(discovered)} gate(s) discovered, "
               f"{len(covered & discovered)} covered, "
               f"{len(disclosed & discovered)} disclosed")
    if gaps:
        print(f"PASS WITH GAPS: {summary}; {len(gaps)} source(s) unreadable "
              f"(see GAP lines above)")
    else:
        print(f"PASS: {summary}")
    if stale:
        print(f"note: declared but not discovered this run: {stale}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
