#!/usr/bin/env bash
# Polaris Cross-Session Learnings — JSONL store with confidence decay + key+type dedup.
# Schema: skills/references/cross-session-learnings.md
# Storage: skills/references/polaris-project-dir.md
set -euo pipefail

: "${POLARIS_WORKSPACE_ROOT:?POLARIS_WORKSPACE_ROOT must be set}"
SLUG="${POLARIS_PROJECT_SLUG:-$(basename "$POLARIS_WORKSPACE_ROOT")}"
PROJECT_DIR="$HOME/.polaris/projects/$SLUG"
LEARNINGS_FILE="$PROJECT_DIR/learnings.jsonl"
EMBEDDINGS_FILE="$PROJECT_DIR/embeddings.json"
VENV_DIR="${POLARIS_VENV:-$HOME/.polaris/venv}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMBED_PY="$SCRIPT_DIR/polaris-embed.py"
EMBED_MODEL="${POLARIS_EMBED_MODEL:-sentence-transformers/all-MiniLM-L6-v2}"
EMBED_VERSION="${POLARIS_EMBED_VERSION:-1}"
mkdir -p "$PROJECT_DIR"
touch "$LEARNINGS_FILE"

usage() {
  cat <<'EOF'
Usage: polaris-learnings.sh <command> [options]

Commands:
  add       Add or merge a learning (dedup by key+type)
  query     Query entries sorted by effective confidence (decay applied);
            add --semantic "text" for vector similarity search
  confirm   Reset last_confirmed to today; optional --boost adjusts confidence
  list      Emit every entry with effective_confidence attached
  reindex   Build/refresh the semantic embeddings index (requires polaris venv)
  help      Show this help

Env:
  POLARIS_WORKSPACE_ROOT   Workspace root (required)
  POLARIS_PROJECT_SLUG     Override slug (default: basename of root)
  POLARIS_COMPANY          Active company; query applies hard-skip filter
  POLARIS_VENV             Python venv path (default: ~/.polaris/venv)
  POLARIS_EMBED_MODEL      Embedding model (default: sentence-transformers/all-MiniLM-L6-v2)

Run '<command> --help' for command-specific flags.
EOF
}

die() { echo "polaris-learnings: $*" >&2; exit 2; }

cmd_add() {
  local key="" type="" content="" confidence="" source=""
  local company="" tag="" metadata_json=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key) key="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      --content) content="$2"; shift 2 ;;
      --confidence) confidence="$2"; shift 2 ;;
      --source) source="$2"; shift 2 ;;
      --company) company="$2"; shift 2 ;;
      --tag) tag="$2"; shift 2 ;;
      --metadata) metadata_json="$2"; shift 2 ;;
      --help)
        echo "add --key K --type T --content C --confidence N --source S [--company C] [--tag T] [--metadata JSON]"
        return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -z "$key" || -z "$type" || -z "$content" || -z "$confidence" || -z "$source" ]] \
    && die "required: --key --type --content --confidence --source"
  [[ "$confidence" =~ ^[0-9]+$ ]] || die "--confidence must be integer"

  local today
  today=$(date +%Y-%m-%d)

  # Validate metadata JSON if present
  if [[ -n "$metadata_json" ]]; then
    echo "$metadata_json" | jq -e . >/dev/null 2>&1 || die "--metadata must be valid JSON"
  fi

  # Look for existing entry with same key+type
  local existing
  existing=$(jq -c --arg k "$key" --arg t "$type" \
    'select(.key == $k and .type == $t)' "$LEARNINGS_FILE" 2>/dev/null | head -n 1 || true)

  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN

  if [[ -n "$existing" ]]; then
    # Merge: max confidence, update content/source, bump last_confirmed.
    local existing_conf new_conf
    existing_conf=$(echo "$existing" | jq '.confidence')
    new_conf=$existing_conf
    (( confidence > existing_conf )) && new_conf=$confidence

    local meta_arg=()
    if [[ -n "$metadata_json" ]]; then
      meta_arg=(--argjson meta "$metadata_json")
    else
      meta_arg=(--argjson meta null)
    fi

    jq -c --arg k "$key" --arg t "$type" --arg content "$content" \
         --argjson conf "$new_conf" --arg src "$source" --arg today "$today" \
         --arg company "$company" --arg tag "$tag" "${meta_arg[@]}" '
      if .key == $k and .type == $t then
        .content = $content
        | .confidence = $conf
        | .source = $src
        | .last_confirmed = $today
        | (if $company != "" then .company = $company else . end)
        | (if $tag != "" then .tag = $tag else . end)
        | (if $meta != null then .metadata = $meta else . end)
      else . end
    ' "$LEARNINGS_FILE" > "$tmp"
    mv "$tmp" "$LEARNINGS_FILE"
    echo "merged: key=$key type=$type confidence=$new_conf"
  else
    local meta_arg=()
    if [[ -n "$metadata_json" ]]; then
      meta_arg=(--argjson meta "$metadata_json")
    else
      meta_arg=(--argjson meta null)
    fi
    local obj
    obj=$(jq -cn --arg k "$key" --arg t "$type" --arg content "$content" \
         --argjson conf "$confidence" --arg src "$source" --arg today "$today" \
         --arg company "$company" --arg tag "$tag" "${meta_arg[@]}" '
      {key: $k, type: $t, content: $content, confidence: $conf, source: $src,
       created: $today, last_confirmed: $today}
      | (if $company != "" then . + {company: $company} else . end)
      | (if $tag != "" then . + {tag: $tag} else . end)
      | (if $meta != null then . + {metadata: $meta} else . end)
    ')
    echo "$obj" >> "$LEARNINGS_FILE"
    echo "added: key=$key type=$type confidence=$confidence"
  fi
}

cmd_query() {
  local top=10 min_conf=0 company="${POLARIS_COMPANY:-}" type_filter="" tag_filter=""
  local semantic="" min_sim=0.0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --top) top="$2"; shift 2 ;;
      --min-confidence) min_conf="$2"; shift 2 ;;
      --company) company="$2"; shift 2 ;;
      --type) type_filter="$2"; shift 2 ;;
      --tag) tag_filter="$2"; shift 2 ;;
      --semantic) semantic="$2"; shift 2 ;;
      --min-similarity) min_sim="$2"; shift 2 ;;
      --help)
        echo "query [--top N] [--min-confidence M] [--company C] [--type T] [--tag T]"
        echo "      [--semantic \"text\" [--min-similarity F]]"
        return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ ! -s "$LEARNINGS_FILE" ]] && return 0

  if [[ -n "$semantic" ]]; then
    [[ -x "$VENV_DIR/bin/python" ]] \
      || die "venv missing at $VENV_DIR. Run scripts/polaris-embed-setup.sh."
    [[ -s "$EMBEDDINGS_FILE" ]] \
      || die "no embeddings index at $EMBEDDINGS_FILE. Run 'polaris-learnings.sh reindex'."
    "$VENV_DIR/bin/python" "$EMBED_PY" query \
      --learnings "$LEARNINGS_FILE" \
      --embeddings "$EMBEDDINGS_FILE" \
      --query "$semantic" \
      --top "$top" \
      --min-confidence "$min_conf" \
      --min-similarity "$min_sim" \
      --company "$company" \
      --model "$EMBED_MODEL"
    return $?
  fi

  jq -c --arg today "$(date +%Y-%m-%d)" --argjson min "$min_conf" \
       --arg company "$company" --arg type_filter "$type_filter" --arg tag_filter "$tag_filter" '
    . as $e
    | (($today + "T00:00:00Z") | fromdateiso8601) as $today_ts
    | (($e.last_confirmed + "T00:00:00Z") | fromdateiso8601) as $lc_ts
    | (($today_ts - $lc_ts) / 86400 / 30 | floor) as $decay
    | ($e.confidence - $decay) as $eff
    | select(($e.promoted // false) == false)
    | select($eff >= $min)
    | select($company == "" or (.company // "") == "" or .company == $company)
    | select($type_filter == "" or .type == $type_filter)
    | select($tag_filter == "" or (.tag // "") == $tag_filter)
    | . + {effective_confidence: $eff}
  ' "$LEARNINGS_FILE" \
    | jq -s --argjson top "$top" '
        sort_by([.effective_confidence, .last_confirmed])
        | reverse
        | .[0:$top]
        | .[]
      ' \
    | jq -c .
}

cmd_confirm() {
  local key="" type_filter="" boost=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key) key="$2"; shift 2 ;;
      --type) type_filter="$2"; shift 2 ;;
      --boost) boost="$2"; shift 2 ;;
      --help) echo "confirm --key K [--type T] [--boost N]"; return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -z "$key" ]] && die "required: --key"
  [[ "$boost" =~ ^-?[0-9]+$ ]] || die "--boost must be integer"

  local today tmp
  today=$(date +%Y-%m-%d)
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN

  local found
  found=$(jq -c --arg k "$key" --arg t "$type_filter" \
    'select(.key == $k and ($t == "" or .type == $t))' "$LEARNINGS_FILE" 2>/dev/null | head -n 1 || true)
  [[ -z "$found" ]] && { echo "not found: key=$key type=$type_filter" >&2; return 1; }

  jq -c --arg k "$key" --arg t "$type_filter" --arg today "$today" --argjson boost "$boost" '
    if .key == $k and ($t == "" or .type == $t) then
      .last_confirmed = $today | .confidence = (.confidence + $boost)
    else . end
  ' "$LEARNINGS_FILE" > "$tmp"
  mv "$tmp" "$LEARNINGS_FILE"
  echo "confirmed: key=$key boost=$boost"
}

cmd_list() {
  [[ ! -s "$LEARNINGS_FILE" ]] && return 0
  jq -c --arg today "$(date +%Y-%m-%d)" '
    (($today + "T00:00:00Z") | fromdateiso8601) as $today_ts
    | ((.last_confirmed + "T00:00:00Z") | fromdateiso8601) as $lc_ts
    | (($today_ts - $lc_ts) / 86400 / 30 | floor) as $decay
    | . + {effective_confidence: (.confidence - $decay)}
  ' "$LEARNINGS_FILE"
}

cmd_reindex() {
  local force="" model="$EMBED_MODEL" version="$EMBED_VERSION"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force="--force"; shift ;;
      --model) model="$2"; shift 2 ;;
      --version) version="$2"; shift 2 ;;
      --help) echo "reindex [--force] [--model M] [--version V]"; return 0 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [[ -x "$VENV_DIR/bin/python" ]] \
    || die "venv missing at $VENV_DIR. Run scripts/polaris-embed-setup.sh."
  [[ -s "$LEARNINGS_FILE" ]] || { echo "no learnings to index"; return 0; }
  "$VENV_DIR/bin/python" "$EMBED_PY" build-index \
    --learnings "$LEARNINGS_FILE" \
    --output "$EMBEDDINGS_FILE" \
    --model "$model" \
    --version "$version" \
    $force
}

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
  add)      cmd_add "$@" ;;
  query)    cmd_query "$@" ;;
  confirm)  cmd_confirm "$@" ;;
  list)     cmd_list "$@" ;;
  reindex)  cmd_reindex "$@" ;;
  help|--help|-h) usage ;;
  *) echo "unknown command: $cmd" >&2; usage; exit 2 ;;
esac
