#!/usr/bin/env bash
# Purpose: DP-417 T8 — shared VR/behavior verification trustworthiness helpers.
#   Single home for the two-layer trustworthiness gate consumed by BOTH
#   scripts/run-behavior-contract.sh (parity/hybrid) and
#   scripts/run-visual-snapshot.sh (vr). Layer 1 = real before/after render trust
#   (impersonation via placeholder artifact / hard-coded state_hash / no real
#   render is rejected). Layer 2 = test-subject isolation (a replaces_existing
#   fidelity task must not reach PASS while the replaced old source still exists —
#   that PASS is confounded, "先清乾淨再驗證"). These are pre-gates over the existing
#   evidence: no second comparator and no second PASS marker path is introduced.
# Inputs:  function arguments (see each function's header comment).
# Outputs: exit code (0 ok / non-zero fail-closed) + POLARIS_* reason on stderr.
# Side effects: none (read-only predicates).

# Description: True (exit 0) iff the task claims screen/behavior before-after
#   fidelity — applies=true AND mode is one of parity / vr / hybrid.
# Args: $1 = applies ("true"/other); $2 = mode.
vft_claims_before_after_fidelity() {
  local applies="$1"
  local mode="$2"
  [[ "$applies" == "true" ]] || return 1
  case "$mode" in
    parity | vr | hybrid) return 0 ;;
    *) return 1 ;;
  esac
}

# Description: True (exit 0) iff the file has real rendered image/video magic
#   bytes (PNG / JPEG / WEBM(EBML) / MP4). Placeholder text files (e.g. the string
#   "png:before") return non-zero. Method-agnostic: only checks that the artifact
#   is a genuine rendered binary, not how it is later compared.
# Args: $1 = file path.
vft_is_real_rendered_artifact() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  local hex
  hex="$(od -An -tx1 -N16 "$file" 2>/dev/null | tr -d ' \n')"
  case "$hex" in
    89504e470d0a1a0a*) return 0 ;;  # PNG signature
    ffd8ff*) return 0 ;;            # JPEG SOI
    1a45dfa3*) return 0 ;;          # WEBM / Matroska EBML header
  esac
  # MP4 / ISO-BMFF: 'ftyp' (hex 66747970) box type within the first 16 bytes.
  case "$hex" in
    *66747970*) return 0 ;;
  esac
  return 1
}

# Description: Resolve the behavior state file inside an artifact dir, if any.
#   Prints the path (or nothing). Same candidate order the evidence writer uses.
# Args: $1 = artifact dir.
vft_behavior_state_file() {
  local dir="$1"
  local candidate
  for candidate in "$dir/behavior-state.json" "$dir/state.json"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Description: True (exit 0) iff the JSON state file declares a literal top-level
#   "hash" string — a hard-coded state_hash that lets a flow assert its own
#   comparison result without any real render (AC-NEG3 impersonation).
# Args: $1 = state file path.
vft_state_declares_literal_hash() {
  local state_file="$1"
  [[ -f "$state_file" ]] || return 1
  STATE_FILE="$state_file" python3 - <<'PY'
import json
import os
import sys

try:
    data = json.load(open(os.environ["STATE_FILE"], encoding="utf-8"))
except Exception:
    sys.exit(1)
value = data.get("hash") if isinstance(data, dict) else None
sys.exit(0 if isinstance(value, str) and value.strip() else 1)
PY
}

# Description: True (exit 0) iff the artifact dir contains at least one real
#   rendered visual artifact (image/video with genuine magic bytes). A dir that
#   only holds placeholder text stand-ins returns non-zero.
# Args: $1 = artifact dir.
vft_dir_has_real_visual() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if vft_is_real_rendered_artifact "$f"; then
      return 0
    fi
  done < <(find "$dir" -type f \
    \( -name '*.png' -o -name '*.jpg' -o -name '*.jpeg' -o -name '*.webm' -o -name '*.mp4' \) 2>/dev/null)
  return 1
}

# Description: Layer 1 — behavior parity/hybrid real-render trust. Prints a
#   fail-closed reason (and returns non-zero) when the compare evidence for a
#   fidelity claim is an impersonation; prints nothing (returns 0) when the render
#   is trustworthy. A real behavior state file OR a real rendered visual artifact
#   counts as a real render; a declared literal state hash is always rejected.
# Args: $1 = compare artifact dir.
vft_behavior_render_block_reason() {
  local artifact_dir="$1"
  local state_file
  state_file="$(vft_behavior_state_file "$artifact_dir" || true)"

  if [[ -n "$state_file" ]] && vft_state_declares_literal_hash "$state_file"; then
    printf 'hardcoded_state_hash: state file declares a literal "hash"; a before-after fidelity claim must be backed by a real render, not a self-asserted hash.\n'
    return 1
  fi

  if [[ -n "$state_file" ]]; then
    return 0
  fi

  if vft_dir_has_real_visual "$artifact_dir"; then
    return 0
  fi

  printf 'no_rendered_artifact: no behavior state file and no real rendered screenshot/video; a placeholder / unit+grep stand-in cannot back a before-after fidelity claim.\n'
  return 1
}

# Description: Layer 2 — test-subject isolation. Fail-closed (non-zero +
#   POLARIS_VERIFICATION_CONFOUNDED) when replaces_existing is true and either no
#   replaced_paths were declared, or any declared replaced path still exists in the
#   test environment at verify time (the PASS would be confounded by the old
#   source). No-op (exit 0) when replaces_existing is not true.
# Args: $1 = run repo root; $2 = replaces_existing ("true"/other);
#       $3 = replaced_paths (newline-separated, repo-relative).
vft_assert_isolated() {
  local run_repo="$1"
  local replaces="$2"
  local paths="$3"
  [[ "$replaces" == "true" ]] || return 0

  if [[ -z "${paths//[[:space:]]/}" ]]; then
    echo "POLARIS_VERIFICATION_CONFOUNDED: replaces_existing=true but replaced_paths is empty; test-subject isolation cannot be verified." >&2
    return 1
  fi

  local p
  local present=()
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    if [[ -e "$run_repo/$p" ]]; then
      present+=("$p")
    fi
  done <<< "$paths"

  if (( ${#present[@]} > 0 )); then
    echo "POLARIS_VERIFICATION_CONFOUNDED: replaced source still present at verify time (先清乾淨再驗證): ${present[*]}" >&2
    return 1
  fi
  return 0
}

# Description: Extract the isolation contract from a task.md's verification block
#   for consumers (run-visual-snapshot.sh) that do not already parse the fidelity
#   contract. Reads replaces_existing / replaced_paths anywhere inside the
#   verification: block, regardless of which sub-block (behavior_contract or
#   visual_regression) declares them. Prints "replaces_existing=<true|false>" on the
#   first line, then one "path=<repo-relative>" line per replaced path.
# Args: $1 = task.md path.
vft_extract_isolation() {
  local task_md="$1"
  [[ -f "$task_md" ]] || return 0
  TASK_MD="$task_md" python3 - <<'PY'
import os
import sys

path = os.environ["TASK_MD"]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except Exception:
    sys.exit(0)

# Locate the frontmatter block.
if not lines or lines[0].strip() != "---":
    sys.exit(0)
fm = []
for ln in lines[1:]:
    if ln.strip() == "---":
        break
    fm.append(ln)


def indent(s):
    return len(s) - len(s.lstrip(" "))


in_verification = False
replaced_indent = None  # indent of the "replaced_paths:" key while collecting items
replaces = "false"
paths = []
for raw in fm:
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    ind = indent(raw)
    stripped = raw.strip()
    if ind == 0:
        in_verification = stripped.rstrip() == "verification:"
        replaced_indent = None
        continue
    if not in_verification:
        continue
    # A dedent to or past the replaced_paths key closes the item list.
    if replaced_indent is not None and ind <= replaced_indent and not stripped.startswith("- "):
        replaced_indent = None
    if replaced_indent is not None and ind > replaced_indent and stripped.startswith("- "):
        item = stripped[2:].strip()
        if (item.startswith('"') and item.endswith('"')) or (item.startswith("'") and item.endswith("'")):
            item = item[1:-1]
        if item:
            paths.append(item)
        continue
    if stripped.startswith("replaces_existing:"):
        val = stripped.split(":", 1)[1].strip().lower()
        replaces = "true" if val == "true" else "false"
    elif stripped.rstrip() == "replaced_paths:":
        replaced_indent = ind

print(f"replaces_existing={replaces}")
for p in paths:
    print(f"path={p}")
PY
}
