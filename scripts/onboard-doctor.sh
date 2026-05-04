#!/usr/bin/env bash
# onboard-doctor.sh — deterministic Polaris onboarding readiness checker.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/onboard-doctor.sh [--workspace PATH] [--company NAME] [--json] [--strict-mcp]

Checks onboarding readiness and reports one of:
  ready    - required local setup is complete
  partial  - local setup works but optional/manual follow-up remains
  blocked  - required config is missing or unreadable
EOF
}

WORKSPACE=""
COMPANY=""
JSON=0
STRICT_MCP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --workspace=*) WORKSPACE="${1#--workspace=}"; shift ;;
    --company) COMPANY="${2:-}"; shift 2 ;;
    --company=*) COMPANY="${1#--company=}"; shift ;;
    --json) JSON=1; shift ;;
    --strict-mcp) STRICT_MCP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "onboard-doctor: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

find_workspace() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/workspace-config.yaml" && -d "$dir/scripts" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  local script_root
  script_root="$(cd "$(dirname "$0")/.." && pwd)"
  if [[ -d "$script_root/scripts" ]]; then
    printf '%s\n' "$script_root"
    return 0
  fi
  return 1
}

if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="$(find_workspace || true)"
fi
if [[ -z "$WORKSPACE" || ! -d "$WORKSPACE" ]]; then
  echo "onboard-doctor: workspace not found" >&2
  exit 1
fi
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

python3 - "$WORKSPACE" "$COMPANY" "$JSON" "$STRICT_MCP" <<'PY'
import json
import os
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"onboard-doctor: PyYAML is required: {exc}", file=sys.stderr)
    raise SystemExit(1)

workspace = Path(sys.argv[1])
company_filter = sys.argv[2].strip()
json_mode = sys.argv[3] == "1"
strict_mcp = sys.argv[4] == "1"

checks = []

def add(name, state, message, severity="info", action_class="none", repair=""):
    checks.append({
        "name": name,
        "state": state,
        "severity": severity,
        "message": message,
        "action_class": action_class,
        "repair": repair,
    })

def load_yaml(path):
    try:
        with path.open(encoding="utf-8") as handle:
            return yaml.safe_load(handle) or {}
    except Exception as exc:
        add(str(path), "blocked", f"failed to read YAML: {exc}", "blocked", "local config")
        return None

def expand_path(value):
    if not value:
        return ""
    return os.path.abspath(os.path.expanduser(str(value)))

def has_text(value):
    return bool(str(value or "").strip())

root_config_path = workspace / "workspace-config.yaml"
root = load_yaml(root_config_path)
companies = []

if root is None:
    pass
elif not root_config_path.exists():
    add("root config", "blocked", "workspace-config.yaml is missing", "blocked", "local config", "run onboard")
else:
    add("root config", "ready", "workspace-config.yaml exists", "info", "local config")
    if has_text(root.get("language")):
        add("root language", "ready", f"language={root.get('language')}", "info", "local config")
    else:
        add("root language", "partial", "root language is missing", "partial", "local config", "onboard repair can write root language")
    companies = root.get("companies") or []
    if not companies:
        add("company routing", "blocked", "root companies[] is empty", "blocked", "local config", "run onboard to register a company")
    else:
        add("company routing", "ready", f"{len(companies)} company route(s) registered", "info", "local config")

selected = []
for item in companies:
    name = str((item or {}).get("name") or "").strip()
    if company_filter and name != company_filter:
        continue
    selected.append(item or {})

if company_filter and not selected:
    add("company selection", "blocked", f"company not found in root config: {company_filter}", "blocked", "local config")

for item in selected:
    name = str(item.get("name") or "").strip() or "<unnamed>"
    base_dir = expand_path(item.get("base_dir"))
    if not base_dir:
        add(f"{name}: base_dir", "blocked", "base_dir is missing", "blocked", "local config")
        continue
    company_config_path = Path(base_dir) / "workspace-config.yaml"
    if not company_config_path.exists():
        add(f"{name}: company config", "blocked", f"missing {company_config_path}", "blocked", "local config", "onboard repair can create company config from template")
        continue

    company = load_yaml(company_config_path)
    if company is None:
        continue

    add(f"{name}: company config", "ready", f"found {company_config_path}", "info", "local config")

    projects = company.get("projects") or []
    if not projects:
        add(f"{name}: projects", "partial", "projects[] is empty", "partial", "local config", "onboard repair can add project routing")
    else:
        add(f"{name}: projects", "ready", f"{len(projects)} project(s) configured", "info", "local config")

    runtime_projects = 0
    incomplete_runtime = []
    required_runtime_fields = ["start_command", "ready_signal", "base_url", "health_check", "requires", "env"]
    for project in projects:
        project_name = str((project or {}).get("name") or "<unnamed>")
        dev_env = (project or {}).get("dev_environment")
        if not dev_env:
            incomplete_runtime.append(f"{project_name}: missing dev_environment")
            continue
        runtime_projects += 1
        missing = [field for field in required_runtime_fields if field not in dev_env]
        if missing:
            incomplete_runtime.append(f"{project_name}: missing {', '.join(missing)}")

    if incomplete_runtime:
        add(f"{name}: dev_environment", "partial", "; ".join(incomplete_runtime), "partial", "local config", "onboard repair can fill projects[].dev_environment")
    elif runtime_projects:
        add(f"{name}: dev_environment", "ready", f"{runtime_projects} runtime project(s) have required fields", "info", "local config")
    else:
        add(f"{name}: dev_environment", "partial", "no runtime project dev_environment configured", "partial", "local config")

    vr_domains = (((company.get("visual_regression") or {}).get("domains")) or [])
    if vr_domains:
        add(f"{name}: visual_regression", "ready", f"{len(vr_domains)} domain(s) configured", "info", "local config")
    else:
        add(f"{name}: visual_regression", "partial", "visual_regression.domains[] is empty", "partial", "local config", "onboard repair can add VR domains or record an explicit skip")

    if company.get("daily_learning_scan"):
        add(f"{name}: daily_learning", "ready", "daily_learning_scan configured", "info", "local config")
    else:
        add(f"{name}: daily_learning", "partial", "daily_learning_scan is missing", "partial", "local config", "onboard repair can enable or record disabled state")

    required_mcp = []
    if company.get("jira"):
        required_mcp.append("JIRA")
    if company.get("confluence"):
        required_mcp.append("Confluence")
    if company.get("slack"):
        required_mcp.append("Slack")
    if required_mcp:
        state = "partial" if strict_mcp else "manual_required"
        severity = "partial" if strict_mcp else "info"
        add(
            f"{name}: MCP health",
            state,
            "requires runtime connector check: " + ", ".join(required_mcp),
            severity,
            "external read",
            "verify connector login in the active agent runtime",
        )
    else:
        add(f"{name}: MCP health", "ready", "no required MCP connector declared", "info", "external read")

toolchain_manifest = workspace / "polaris-toolchain.yaml"
toolchain_script = workspace / "scripts" / "polaris-toolchain.sh"
if toolchain_manifest.exists() and toolchain_script.exists():
    add("toolchain", "ready", "polaris-toolchain manifest and runner exist", "info", "global CLI")
else:
    add("toolchain", "partial", "polaris-toolchain manifest or runner missing", "partial", "global CLI", "run scripts/polaris-toolchain.sh doctor --required")

agents_skills = workspace / ".agents" / "skills"
codex_agents = workspace / ".codex" / "AGENTS.md"
codex_generated = workspace / ".codex" / ".generated"
if agents_skills.is_symlink() and os.readlink(agents_skills) == "../.claude/skills" and codex_agents.exists() and codex_generated.exists():
    add("Codex parity", "ready", "skills mirror and Codex runtime targets exist", "info", "generated parity")
else:
    add("Codex parity", "partial", "Codex parity targets are incomplete", "partial", "generated parity", "run Codex bootstrap or onboard repair")

blocked = any(item["severity"] == "blocked" for item in checks)
partial = any(item["severity"] == "partial" for item in checks)
status = "blocked" if blocked else "partial" if partial else "ready"

report = {
    "status": status,
    "workspace": str(workspace),
    "company": company_filter or None,
    "checks": checks,
}

if json_mode:
    print(json.dumps(report, ensure_ascii=False, indent=2))
else:
    print(f"onboard doctor status: {status}")
    for item in checks:
        print(f"- [{item['state']}] {item['name']}: {item['message']}")
        if item.get("repair"):
            print(f"  repair: {item['repair']}")

raise SystemExit(2 if status == "blocked" else 0)
PY
