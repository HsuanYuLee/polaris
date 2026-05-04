#!/usr/bin/env bash
# polaris-external-write-gate.sh — preflight gate for external write bodies.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: polaris-external-write-gate.sh --surface <surface> --body-file <path> [options]

Options:
  --surface NAME       jira-comment|jira-description|slack|confluence|github-review|github-comment|pr-body|release|artifact
  --body-file PATH     Materialized markdown/plain-text body to validate
  --mode MODE          Language policy mode. Default: artifact
  --blocking           Blocking language gate. Default
  --advisory           Advisory language gate
  --language LANG      Override workspace language
  --workspace-root DIR Root used by validate-language-policy.sh
  --starlight          Also run validate-starlight-authoring.sh check
EOF
  exit 2
}

surface=""
body_file=""
mode="artifact"
enforcement="--blocking"
language=""
workspace_root=""
starlight=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surface)
      surface="${2:-}"
      shift 2
      ;;
    --body-file)
      body_file="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --blocking)
      enforcement="--blocking"
      shift
      ;;
    --advisory)
      enforcement="--advisory"
      shift
      ;;
    --language)
      language="${2:-}"
      shift 2
      ;;
    --workspace-root)
      workspace_root="${2:-}"
      shift 2
      ;;
    --starlight)
      starlight=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$surface" || -z "$body_file" ]]; then
  usage
fi

case "$surface" in
  jira-comment|jira-description|jira-summary|slack|confluence|github-review|github-comment|pr-body|release|artifact)
    ;;
  *)
    echo "error: unsupported surface: $surface" >&2
    echo "supported: jira-comment jira-description jira-summary slack confluence github-review github-comment pr-body release artifact" >&2
    exit 2
    ;;
esac

if [[ ! -f "$body_file" ]]; then
  echo "error: body file not found: $body_file" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace="${workspace_root:-$(cd "$script_dir/.." && pwd)}"
language_gate="$workspace/scripts/validate-language-policy.sh"
starlight_gate="$workspace/scripts/validate-starlight-authoring.sh"

if [[ ! -x "$language_gate" ]]; then
  echo "error: language validator not executable: $language_gate" >&2
  exit 2
fi

cmd=(bash "$language_gate" "$enforcement" --mode "$mode")
if [[ -n "$language" ]]; then
  cmd+=(--language "$language")
fi
if [[ -n "$workspace_root" ]]; then
  cmd+=(--workspace-root "$workspace_root")
fi
cmd+=("$body_file")
"${cmd[@]}"

case "$body_file" in
  */docs-manager/src/content/docs/specs/*.md|docs-manager/src/content/docs/specs/*.md)
    starlight=1
    ;;
esac

if [[ "$starlight" -eq 1 ]]; then
  if [[ ! -x "$starlight_gate" ]]; then
    echo "error: Starlight authoring validator not executable: $starlight_gate" >&2
    exit 2
  fi
  bash "$starlight_gate" check "$body_file"
fi

echo "PASS external write gate: $surface -> $body_file"
