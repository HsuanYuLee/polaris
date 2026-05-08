#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib/workspace-config-root.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/workspace-config-root.sh"

usage() {
  cat >&2 <<'EOF'
usage: resolve-workspace-overlay.sh --kind KIND [name] [--workspace PATH]

Kinds:
  specs-root              Canonical ignored specs authoring root
  workspace-config-root   Canonical root workspace-config.yaml path
  codex-rules             Workspace .codex runtime context
  evidence-root           Durable local evidence mirror root
  local-skill NAME        Maintainer-local skill directory
  generated-output        docs-manager generated output directory
EOF
}

KIND=""
NAME=""
WORKSPACE="${POLARIS_WORKSPACE_ROOT:-$(pwd)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind)
      KIND="${2:-}"
      shift 2
      ;;
    --kind=*)
      KIND="${1#--kind=}"
      shift
      ;;
    --workspace)
      WORKSPACE="${2:-}"
      shift 2
      ;;
    --workspace=*)
      WORKSPACE="${1#--workspace=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$NAME" ]]; then
        NAME="$1"
      fi
      shift
      ;;
  esac
done

if [[ -z "$KIND" ]]; then
  usage
  exit 2
fi

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

emit() {
  local kind="$1" path="$2" authoring_allowed="$3" generated="$4" exists="false"
  [[ -e "$path" ]] && exists="true"
  printf '{"kind":"%s","path":"%s","exists":%s,"authoring_allowed":%s,"generated":%s}\n' \
    "$(json_escape "$kind")" \
    "$(json_escape "$path")" \
    "$exists" \
    "$authoring_allowed" \
    "$generated"
}

require_exists() {
  local path="$1" label="$2"
  if [[ ! -e "$path" ]]; then
    echo "resolve-workspace-overlay: missing $label: $path" >&2
    exit 2
  fi
}

case "$KIND" in
  specs-root)
    path="$WORKSPACE/docs-manager/src/content/docs/specs"
    require_exists "$path" "specs root"
    emit "$KIND" "$path" true false
    ;;
  workspace-config-root)
    path="$(resolve_workspace_config_path "$WORKSPACE" 2>/dev/null || true)"
    require_exists "$path" "workspace config root"
    emit "$KIND" "$path" false false
    ;;
  codex-rules)
    path="$WORKSPACE/.codex"
    require_exists "$path" ".codex overlay"
    emit "$KIND" "$path" false false
    ;;
  evidence-root)
    path="${POLARIS_EVIDENCE_ROOT:-$WORKSPACE/.polaris/evidence}"
    mkdir -p "$path"
    emit "$KIND" "$path" false false
    ;;
  local-skill)
    if [[ -z "$NAME" ]]; then
      echo "resolve-workspace-overlay: local-skill requires a skill name" >&2
      exit 2
    fi
    path="${POLARIS_LOCAL_SKILLS_ROOT:-$HOME/.agents/skills}/$NAME"
    require_exists "$path" "local skill"
    emit "$KIND" "$path" false false
    ;;
  generated-output)
    path="$WORKSPACE/docs-manager/dist"
    emit "$KIND" "$path" false true
    ;;
  *)
    echo "resolve-workspace-overlay: unknown kind: $KIND" >&2
    usage
    exit 2
    ;;
esac
