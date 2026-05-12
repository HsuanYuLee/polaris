#!/usr/bin/env bash
# Shared PR review-label config and helpers.

polaris_pr_review_label_config() {
  local repo_root="$1"

  python3 - "$repo_root" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    yaml = None

repo = Path(sys.argv[1]).resolve()

def normalize_repo(value):
    value = (value or "").strip()
    value = re.sub(r"^git@github\.com:", "", value)
    value = re.sub(r"^https://github\.com/", "", value)
    value = re.sub(r"\.git$", "", value)
    return value.strip("/")

def read_yaml(path):
    if yaml is None:
        return {}
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except Exception:
        return {}

def normalize_config(raw, default_policy=None):
    if not isinstance(raw, dict):
        return None
    policy = str(raw.get("policy") or default_policy or "optional").strip() or "optional"
    labels = raw.get("labels")
    if labels is None and raw.get("label"):
        labels = [raw.get("label")]
    if isinstance(labels, str):
        labels = [labels]
    labels = [str(item).strip() for item in (labels or []) if str(item).strip()]
    return {"policy": policy, "labels": labels}

def config_from_scrum(data):
    scrum = data.get("scrum") if isinstance(data, dict) else {}
    if not isinstance(scrum, dict):
        return None
    label = str(scrum.get("need_review_label") or "").strip()
    if not label:
        return None
    return {"policy": "optional", "labels": [label]}

remote = ""
try:
    remote = subprocess.check_output(
        ["git", "-C", str(repo), "config", "--get", "remote.origin.url"],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
except Exception:
    pass
remote_norm = normalize_repo(remote)
repo_basename = os.path.basename(remote_norm) if remote_norm else repo.name

configs = []
for root in [repo, *repo.parents]:
    cfg = root / "workspace-config.yaml"
    if cfg.exists():
        configs.append(cfg)

fallback = None
for cfg in configs:
    data = read_yaml(cfg)
    if not isinstance(data, dict):
        continue

    for project in data.get("projects") or []:
        if not isinstance(project, dict):
            continue
        project_repo = normalize_repo(project.get("repo"))
        project_name = str(project.get("name") or "").strip()
        matches = (
            (project_repo and project_repo == remote_norm)
            or (project_repo and os.path.basename(project_repo) == repo_basename)
            or (project_name and project_name == repo.name)
            or (project_name and project_name == repo_basename)
        )
        if not matches:
            continue
        delivery = project.get("delivery") or {}
        if isinstance(delivery, dict):
            cfg_value = normalize_config(delivery.get("pr_review_label"))
            if cfg_value:
                print(json.dumps(cfg_value, separators=(",", ":")))
                raise SystemExit(0)

    defaults = data.get("defaults") or {}
    if isinstance(defaults, dict):
        delivery = defaults.get("delivery") or {}
        if isinstance(delivery, dict):
            cfg_value = normalize_config(delivery.get("pr_review_label"))
            if cfg_value:
                fallback = fallback or cfg_value

    fallback = fallback or config_from_scrum(data)

print(json.dumps(fallback or {"policy": "off", "labels": []}, separators=(",", ":")))
PY
}

polaris_pr_review_label_add() {
  local repo_root="$1"
  local pr_ref="$2"
  local prefix="${3:-[polaris pr-review-label]}"
  local cfg policy labels_json label added=0

  cfg="$(polaris_pr_review_label_config "$repo_root")"
  policy="$(printf '%s' "$cfg" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("policy") or "off").strip())')"
  labels_json="$(printf '%s' "$cfg" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin).get("labels") or []))')"

  case "$policy" in
    off)
      echo "$prefix PR review label policy=off — skipping label."
      return 0
      ;;
    optional|required|"")
      [[ -n "$policy" ]] || policy="optional"
      ;;
    *)
      echo "$prefix invalid pr_review_label policy '$policy'; treating as required."
      policy="required"
      ;;
  esac

  if [[ -z "$labels_json" ]]; then
    if [[ "$policy" == "required" ]]; then
      echo "$prefix ✗ BLOCKED: pr_review_label policy is required but no labels are configured."
      return 2
    fi
    echo "$prefix WARN: no review labels configured; continuing because policy=${policy}."
    return 0
  fi

  while IFS= read -r label; do
    [[ -n "$label" ]] || continue
    if [[ -n "$pr_ref" ]]; then
      label_added=false
      if gh pr edit "$pr_ref" --add-label "$label" >/dev/null 2>&1; then
        label_added=true
      fi
    else
      label_added=false
      if gh pr edit --add-label "$label" >/dev/null 2>&1; then
        label_added=true
      fi
    fi
    if [[ "$label_added" == true ]]; then
      echo "$prefix ✓ PR labeled '$label'"
      added=1
      break
    fi
  done <<<"$labels_json"

  if [[ "$added" -eq 1 ]]; then
    return 0
  fi
  if [[ "$policy" == "required" ]]; then
    echo "$prefix ✗ BLOCKED: unable to add any configured PR review label."
    return 2
  fi
  echo "$prefix WARN: unable to add configured PR review label; continuing because policy=${policy}."
  return 0
}
