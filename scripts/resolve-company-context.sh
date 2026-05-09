#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/workspace-config-root.sh
. "$SCRIPT_DIR/lib/workspace-config-root.sh"

PREFIX="[polaris company-context]"

WORKSPACE_ROOT=""
MODE=""
COMPANY_NAME=""
TICKET_KEY=""
PROJECT_KEY=""
CWD_PATH=""
FORMAT="text"
FIELD=""

usage() {
  cat >&2 <<'USAGE'
Usage:
  bash scripts/resolve-company-context.sh [mode] [options]

Modes:
  --company <name>   Explicitly resolve a company by name
  --ticket <KEY>     Diagnose routing from a JIRA ticket key (prefix before -)
  --project <KEY>    Diagnose routing from a JIRA project prefix
  --cwd <path>       Diagnose routing from a working directory path
  (none)             Resolve via default_company or single-company fallback

Options:
  --workspace-root <path>   Override workspace root containing workspace-config.yaml
  --format text|json|field  Output format (default: text)
  --field <name>            For --format field. Supported:
                            status, mode, company_name, base_dir, config_path,
                            resolved_via, github_org, error_code
  -h, --help                Show this help

Exit:
  0   Resolver completed (status may still be error in payload)
  64  Invalid usage / unsupported format
  65  Workspace root could not be resolved
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root) WORKSPACE_ROOT="${2:-}"; shift 2 ;;
    --company) MODE="set-explicit"; COMPANY_NAME="${2:-}"; shift 2 ;;
    --ticket) MODE="diagnose-ticket"; TICKET_KEY="${2:-}"; shift 2 ;;
    --project) MODE="diagnose-project"; PROJECT_KEY="${2:-}"; shift 2 ;;
    --cwd) MODE="diagnose-cwd"; CWD_PATH="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "$PREFIX unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

[[ "$FORMAT" == "text" || "$FORMAT" == "json" || "$FORMAT" == "field" ]] || {
  echo "$PREFIX --format must be text, json, or field" >&2
  exit 64
}

if [[ "$FORMAT" == "field" ]]; then
  [[ "$FIELD" == "status" || "$FIELD" == "mode" || "$FIELD" == "company_name" || \
     "$FIELD" == "base_dir" || "$FIELD" == "config_path" || "$FIELD" == "resolved_via" || \
     "$FIELD" == "github_org" || "$FIELD" == "error_code" ]] || {
    echo "$PREFIX unsupported --field: $FIELD" >&2
    exit 64
  }
fi

if [[ -z "$MODE" ]]; then
  MODE="set-default"
fi

root_dir=""
if [[ -n "$WORKSPACE_ROOT" ]]; then
  if [[ -d "$WORKSPACE_ROOT" && -f "$WORKSPACE_ROOT/workspace-config.yaml" ]]; then
    root_dir="$(cd "$WORKSPACE_ROOT" && pwd)"
  else
    echo "$PREFIX workspace root missing workspace-config.yaml: $WORKSPACE_ROOT" >&2
    exit 65
  fi
else
  root_dir="$(resolve_workspace_config_root "$PWD" 2>/dev/null || true)"
  [[ -n "$root_dir" && -f "$root_dir/workspace-config.yaml" ]] || {
    echo "$PREFIX failed to resolve workspace root" >&2
    exit 65
  }
fi

root_cfg="$root_dir/workspace-config.yaml"

python3 - "$root_cfg" "$MODE" "$COMPANY_NAME" "$TICKET_KEY" "$PROJECT_KEY" "$CWD_PATH" "$FORMAT" "$FIELD" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:
    print(f"missing dependency: {exc}", file=sys.stderr)
    sys.exit(65)


root_cfg = Path(sys.argv[1])
mode = sys.argv[2]
company_name = sys.argv[3]
ticket_key = sys.argv[4]
project_key = sys.argv[5]
cwd_path = sys.argv[6]
fmt = sys.argv[7]
field = sys.argv[8]


def expand_path(raw: str) -> str:
    return str(Path(os.path.expanduser(raw)).resolve()) if raw else ""


def payload_base() -> dict:
    return {
        "status": "error",
        "mode": mode,
        "company_name": None,
        "base_dir": None,
        "config_path": None,
        "resolved_via": None,
        "github_org": None,
        "jira_projects": [],
        "warnings": [],
        "errors": [],
    }


def add_error(payload: dict, code: str, detail: str) -> dict:
    payload["status"] = "error"
    payload["errors"].append({"code": code, "detail": detail})
    return payload


def finalize_ok(payload: dict) -> dict:
    payload["status"] = "ok"
    return payload


def summarize_warning(payload: dict, message: str) -> None:
    payload["warnings"].append(message)


def load_yaml(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def match_company(companies: list[dict], raw: str):
    needle = raw.strip().lower()
    exact = [c for c in companies if str(c.get("name", "")).strip().lower() == needle]
    if len(exact) == 1:
        return exact[0], None
    if len(exact) > 1:
        return None, "company_name_ambiguous"
    partial = [c for c in companies if needle and needle in str(c.get("name", "")).strip().lower()]
    if len(partial) == 1:
        return partial[0], None
    if len(partial) > 1:
        return None, "company_name_ambiguous"
    return None, "company_name_no_match"


def extract_project_prefix(raw_ticket: str):
    match = re.match(r"^([A-Za-z][A-Za-z0-9]+)-\d+$", raw_ticket.strip())
    if not match:
        return None
    return match.group(1).upper()


def collect_project_matches(companies: list[dict], prefix: str) -> list[dict]:
    matches = []
    for company in companies:
        base_dir = expand_path(str(company.get("base_dir", "")))
        company_cfg = Path(base_dir) / "workspace-config.yaml" if base_dir else None
        if not company_cfg or not company_cfg.is_file():
            continue
        try:
            data = load_yaml(company_cfg)
        except Exception:
            continue
        projects = (((data.get("jira") or {}).get("projects")) or [])
        project_keys = []
        for item in projects:
            key = ""
            if isinstance(item, dict):
                key = str(item.get("key", "")).strip()
            if key:
                project_keys.append(key.upper())
        if prefix.upper() in project_keys:
            matches.append(
                {
                    "company": company,
                    "config_path": str(company_cfg),
                    "config": data,
                    "project_keys": project_keys,
                }
            )
    return matches


def validate_company_config(payload: dict, company: dict, config_path: Path):
    if not config_path.is_file():
        return add_error(
            payload,
            "company_config_missing",
            f"resolved company config not found: {config_path}",
        )
    try:
        config = load_yaml(config_path)
    except Exception as exc:
        return add_error(
            payload,
            "company_config_invalid",
            f"failed to parse company config {config_path}: {exc}",
        )

    github_org = str(((config.get("github") or {}).get("org")) or "").strip()
    jira_projects = ((config.get("jira") or {}).get("projects")) or []
    jira_keys = []
    for item in jira_projects:
        if isinstance(item, dict):
            key = str(item.get("key", "")).strip()
            if key:
                jira_keys.append(key)

    if not github_org:
        return add_error(
            payload,
            "company_config_invalid",
            f"company config missing github.org: {config_path}",
        )
    if not jira_keys:
        return add_error(
            payload,
            "company_config_invalid",
            f"company config missing jira.projects[].key: {config_path}",
        )

    payload["company_name"] = company.get("name")
    payload["base_dir"] = expand_path(str(company.get("base_dir", "")))
    payload["config_path"] = str(config_path.resolve())
    payload["github_org"] = github_org
    payload["jira_projects"] = jira_keys

    slack_channels = (((config.get("slack") or {}).get("channels")) or {})
    if not isinstance(slack_channels, dict) or not any(str(v).strip() for v in slack_channels.values()):
        summarize_warning(payload, "slack channels not configured")

    return finalize_ok(payload)


payload = payload_base()

if not root_cfg.is_file():
    add_error(payload, "root_config_missing", f"root workspace config not found: {root_cfg}")
else:
    try:
        root_data = load_yaml(root_cfg)
    except Exception as exc:
        add_error(payload, "root_config_missing", f"failed to parse root workspace config: {exc}")
        root_data = {}

    companies = root_data.get("companies") or []
    if payload["errors"]:
        pass
    elif not isinstance(companies, list) or not companies:
        add_error(payload, "no_registered_companies", "root workspace config has no companies[] entries")
    else:
        resolved_company = None

        if mode == "set-explicit":
            resolved_company, reason = match_company(companies, company_name)
            if reason == "company_name_no_match":
                add_error(payload, reason, f"no company matched: {company_name}")
            elif reason == "company_name_ambiguous":
                add_error(payload, reason, f"company name matched multiple entries: {company_name}")
            else:
                payload["resolved_via"] = "company_name_match"

        elif mode == "set-default":
            default_company = str(root_data.get("default_company") or "").strip()
            if default_company:
                resolved_company, reason = match_company(companies, default_company)
                if reason:
                    add_error(payload, "company_name_no_match", f"default_company not registered: {default_company}")
                else:
                    payload["resolved_via"] = "default_company"
            elif len(companies) == 1:
                resolved_company = companies[0]
                payload["resolved_via"] = "single_company"
            else:
                add_error(
                    payload,
                    "default_company_unset",
                    "multiple registered companies and no default_company configured",
                )

        elif mode == "diagnose-ticket":
            prefix = extract_project_prefix(ticket_key)
            if not prefix:
                add_error(payload, "project_prefix_no_match", f"ticket key format invalid: {ticket_key}")
            else:
                matches = collect_project_matches(companies, prefix)
                if len(matches) == 1:
                    resolved_company = matches[0]["company"]
                    payload["resolved_via"] = "jira_project_prefix"
                elif len(matches) > 1:
                    add_error(payload, "project_prefix_ambiguous", f"multiple companies claim JIRA project prefix: {prefix}")
                else:
                    add_error(payload, "project_prefix_no_match", f"no company claimed JIRA project prefix: {prefix}")

        elif mode == "diagnose-project":
            prefix = project_key.strip().upper()
            if not prefix:
                add_error(payload, "project_prefix_no_match", "empty project prefix")
            else:
                matches = collect_project_matches(companies, prefix)
                if len(matches) == 1:
                    resolved_company = matches[0]["company"]
                    payload["resolved_via"] = "jira_project_prefix"
                elif len(matches) > 1:
                    add_error(payload, "project_prefix_ambiguous", f"multiple companies claim JIRA project prefix: {prefix}")
                else:
                    add_error(payload, "project_prefix_no_match", f"no company claimed JIRA project prefix: {prefix}")

        elif mode == "diagnose-cwd":
            target = expand_path(cwd_path or os.getcwd())
            matched = []
            for company in companies:
                base = expand_path(str(company.get("base_dir", "")))
                if not base:
                    continue
                if target == base or target.startswith(base + os.sep):
                    matched.append(company)
            if len(matched) == 1:
                resolved_company = matched[0]
                payload["resolved_via"] = "cwd_base_dir"
            elif len(matched) > 1:
                add_error(payload, "company_name_ambiguous", f"cwd matched multiple company base_dir values: {target}")
            else:
                add_error(payload, "project_prefix_no_match", f"cwd did not match any company base_dir: {target}")
        else:
            add_error(payload, "unsupported_mode", f"unsupported mode: {mode}")

        if resolved_company and not payload["errors"]:
            base_dir = expand_path(str(resolved_company.get("base_dir", "")))
            config_path = Path(base_dir) / "workspace-config.yaml" if base_dir else Path("")
            payload = validate_company_config(payload, resolved_company, config_path)


if fmt == "json":
    print(json.dumps(payload, ensure_ascii=False, indent=2))
elif fmt == "field":
    if field == "error_code":
        errors = payload.get("errors") or []
        print(errors[0]["code"] if errors else "")
    else:
        value = payload.get(field)
        if value is None:
            print("")
        elif isinstance(value, bool):
            print("true" if value else "false")
        else:
            print(value)
else:
    if payload["status"] == "ok":
        print(
            "COMPANY status=ok mode={mode} company={company} resolved_via={via} base_dir={base}".format(
                mode=payload["mode"],
                company=payload["company_name"],
                via=payload["resolved_via"],
                base=payload["base_dir"],
            )
        )
    else:
        code = ""
        if payload["errors"]:
            code = payload["errors"][0]["code"]
        print(
            "COMPANY status=error mode={mode} reason={reason}".format(
                mode=payload["mode"],
                reason=code or "unknown_error",
            )
        )
PY
