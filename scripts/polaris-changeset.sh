#!/usr/bin/env bash
# scripts/polaris-changeset.sh — DP-032 Wave β D24
#
# Mechanically produces .changeset/{slug}.md from a task.md, applying the
# fallback chain documented in skills/references/changeset-convention-default.md:
#   L1 .changeset/config.json (machine config — package_scope SoT)
#   L2 repo handbook changeset-convention.md (semantic; out of scope here)
#   L3 Polaris default (this script's behavior)
#
# Contract:
#   polaris-changeset.sh new --task-md PATH [--repo PATH] [--bump patch|minor|major]
#   polaris-changeset.sh check --task-md PATH [--repo PATH] [--bump patch|minor|major]
#
# Behavior:
#   1. Resolve repo path from task.md `repo` field (walk ancestors)
#   2. .changeset/config.json absent → no-op exit 0 (repo doesn't use changesets)
#   3. Try task.md frontmatter `deliverables.changeset.*` (DP-033 — currently
#      not present; expected to fail and fall through to derivation)
#   4. Derivation fallback:
#        - package_scope: parse .changeset/config.json → if .packages /
#          workspace glob resolves to a single publishable or configured
#          private-tagged package match, use it; otherwise fail-loud
#          (multi-package needs DP-033 declaration or repo handbook override)
#        - bump_level_default: L3 = patch (overridable via --bump)
#        - filename_slug: kebab(ticket) + "-" + kebab(strip(title))
#   5. Description: task.md title with `[TICKET]` / `TICKET:` prefix stripped
#      (L3 default = strip mode); single line, no markdown
#   6. Write .changeset/{slug}.md with frontmatter `"{scope}": {bump}` + body
#   7. Idempotent: existing slug file → silent skip + exit 0 (rebase-friendly)
#   8. Description is mechanically derived; --description flag is intentionally
#      NOT supported (per DP-032 BS-D24-1 — LLM doesn't rewrite semantics)
#
# Exit codes:
#   0  Success (file written or idempotent skip or no-op when no changesets/)
#   1  Fail-loud (parse error, multi-package without declaration, missing on check, etc.)
#   2  Usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSE_TASK_MD="$SCRIPT_DIR/parse-task-md.sh"

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") new --task-md PATH [--repo PATH] [--bump patch|minor|major]
  $(basename "$0") check --task-md PATH [--repo PATH] [--bump patch|minor|major]

Mechanically writes .changeset/{slug}.md from a task.md per
references/changeset-convention-default.md (L3 default).

The check subcommand derives the same expected file and verifies it exists
without writing anything.

Exit:  0 = success / no-op / idempotent skip, 1 = fail-loud, 2 = usage error.
EOF
}

# --- Args -------------------------------------------------------------------
SUB=""
TASK_MD=""
BUMP_OVERRIDE=""
REPO_OVERRIDE=""

if [[ $# -lt 1 ]]; then
  usage; exit 2
fi
SUB="$1"; shift

case "$SUB" in
  new|check) ;;
  -h|--help) usage; exit 0 ;;
  *) echo "polaris-changeset: unknown subcommand: $SUB" >&2; usage; exit 2 ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task-md) TASK_MD="${2:-}"; shift 2 ;;
    --repo)    REPO_OVERRIDE="${2:-}"; shift 2 ;;
    --bump)    BUMP_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "polaris-changeset: unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TASK_MD" ]]; then
  echo "polaris-changeset: --task-md is required" >&2
  usage; exit 2
fi
# Validate --bump first (cheap check, useful for usage tests)
if [[ -n "$BUMP_OVERRIDE" ]]; then
  case "$BUMP_OVERRIDE" in
    patch|minor|major) ;;
    *) echo "polaris-changeset: --bump must be one of: patch, minor, major (got '$BUMP_OVERRIDE')" >&2; exit 2 ;;
  esac
fi
if [[ ! -f "$TASK_MD" ]]; then
  echo "polaris-changeset: --task-md path not found: $TASK_MD" >&2
  exit 1
fi
if [[ ! -x "$PARSE_TASK_MD" ]]; then
  echo "polaris-changeset: parse-task-md.sh not executable at $PARSE_TASK_MD" >&2
  exit 1
fi

# --- Parse task.md fields ---------------------------------------------------
parse_field() {
  local field="$1"
  "$PARSE_TASK_MD" --field "$field" "$TASK_MD" 2>/dev/null || true
}

REPO_NAME="$(parse_field repo)"
TICKET="$(parse_field task_jira_key)"
SUMMARY="$(parse_field summary)"
ALLOWED_FILES_RAW="$(parse_field allowed_files)"

if [[ -z "$REPO_NAME" ]]; then
  echo "polaris-changeset: failed to parse 'repo' from $TASK_MD" >&2
  exit 1
fi
if [[ -z "$SUMMARY" ]]; then
  echo "polaris-changeset: failed to parse 'summary' (task title) from $TASK_MD" >&2
  exit 1
fi

# Ticket may be empty for non-ticket Admin tasks; we'll synthesize from title later.

# --- Resolve repo path (walk ancestors of task.md) -------------------------
resolve_repo_path() {
  local repo_name="$1"
  local td
  td="$(cd "$(dirname "$TASK_MD")" && pwd)"
  local probe
  while [[ "$td" != "/" ]]; do
    probe="$td/$repo_name"
    if [[ -d "$probe" ]]; then
      printf '%s\n' "$probe"
      return 0
    fi
    td="$(dirname "$td")"
  done
  return 1
}

if [[ -n "$REPO_OVERRIDE" ]]; then
  if [[ ! -d "$REPO_OVERRIDE" ]]; then
    echo "polaris-changeset: --repo path not found: $REPO_OVERRIDE" >&2
    exit 1
  fi
  REPO_PATH="$(cd "$REPO_OVERRIDE" && pwd)"
else
  REPO_PATH="$(resolve_repo_path "$REPO_NAME" || true)"
fi
if [[ -z "$REPO_PATH" ]]; then
  echo "polaris-changeset: could not locate repo '$REPO_NAME' as ancestor of $TASK_MD" >&2
  exit 1
fi

CHANGESET_DIR="$REPO_PATH/.changeset"
CHANGESET_CONFIG="$CHANGESET_DIR/config.json"

# --- No-op when repo doesn't use changesets --------------------------------
if [[ ! -d "$CHANGESET_DIR" ]] || [[ ! -f "$CHANGESET_CONFIG" ]]; then
  echo "polaris-changeset: .changeset/ not configured for $REPO_NAME, skipping" >&2
  exit 0
fi

# --- Try DP-033 frontmatter declaration (expected absent in Wave β) --------
DECLARED_PACKAGE_SCOPE="$(parse_field deliverables_changeset_package_scope)"
DECLARED_BUMP_DEFAULT="$(parse_field deliverables_changeset_bump_level_default)"
DECLARED_FILENAME_SLUG="$(parse_field deliverables_changeset_filename_slug)"

# --- Resolve package_scope (declared > derived) ----------------------------
PACKAGE_SCOPE=""
if [[ -n "$DECLARED_PACKAGE_SCOPE" ]]; then
  PACKAGE_SCOPE="$DECLARED_PACKAGE_SCOPE"
else
  # Derive from .changeset/config.json + repo workspace.
  # Strategy: parse config.json's `packages` (if present); resolve glob against
  # repo's package.json files. If multiple packages match, narrow by task
  # Allowed Files path prefixes. If still multiple → fail-loud.
  PACKAGE_SCOPE="$(python3 - "$REPO_PATH" "$CHANGESET_CONFIG" "$ALLOWED_FILES_RAW" <<'PY' || true
import json, os, sys, glob, re

repo_path = sys.argv[1]
cfg_path = sys.argv[2]
allowed_raw = sys.argv[3] if len(sys.argv) > 3 else ""

try:
    with open(cfg_path) as f:
        cfg = json.load(f)
except Exception:
    sys.exit(0)

# Two layouts:
# 1. cfg["packages"] — explicit glob list (newer @changesets schema)
# 2. fallback to root package.json name (single-package repo)
candidates = []
include_private = bool((cfg.get("privatePackages") or {}).get("tag"))

def add_candidate(name, directory):
    rel = os.path.relpath(directory, repo_path).replace(os.sep, "/")
    candidates.append((name, rel))

def allowed_paths(raw):
    paths = []
    for line in raw.splitlines():
        s = line.strip()
        tick = chr(96)
        if s.startswith(tick) and tick in s[1:]:
            s = s[1:s.find(tick, 1)]
        s = s.split("（", 1)[0].strip()
        if s and ("/" in s or "." in s):
            paths.append(s.rstrip("/"))
    return paths

cfg_packages = cfg.get("packages")
if isinstance(cfg_packages, list) and cfg_packages:
    for pat in cfg_packages:
        for d in glob.glob(os.path.join(repo_path, pat)):
            pkg_json = os.path.join(d, "package.json")
            if not os.path.isfile(pkg_json):
                continue
            try:
                with open(pkg_json) as f:
                    pkg = json.load(f)
                name = pkg.get("name")
                if name and (include_private or not pkg.get("private", False)):
                    add_candidate(name, d)
            except Exception:
                continue
else:
    # No packages glob in config — try pnpm-workspace.yaml or root package.json
    pnpm_ws = os.path.join(repo_path, "pnpm-workspace.yaml")
    if os.path.isfile(pnpm_ws):
        # Parse pnpm-workspace.yaml packages globs without yaml dep
        with open(pnpm_ws) as f:
            text = f.read()
        # Very simple: package glob lines under the packages block.
        in_pkg = False
        globs = []
        for ln in text.splitlines():
            s = ln.rstrip()
            if re.match(r"^packages\s*:", s):
                in_pkg = True
                continue
            if in_pkg:
                m = re.match(r"^\s*-\s+['\"]?([^'\"#\s]+)['\"]?", s)
                if m:
                    globs.append(m.group(1))
                elif re.match(r"^[a-zA-Z]", s):
                    in_pkg = False
        for pat in globs:
            for d in glob.glob(os.path.join(repo_path, pat)):
                pkg_json = os.path.join(d, "package.json")
                if not os.path.isfile(pkg_json):
                    continue
                try:
                    with open(pkg_json) as f:
                        pkg = json.load(f)
                    name = pkg.get("name")
                    if name and (include_private or not pkg.get("private", False)):
                        add_candidate(name, d)
                except Exception:
                    continue

    # Fall back to root package.json
    if not candidates:
        root_pkg = os.path.join(repo_path, "package.json")
        if os.path.isfile(root_pkg):
            try:
                with open(root_pkg) as f:
                    pkg = json.load(f)
                name = pkg.get("name")
                if name:
                    add_candidate(name, repo_path)
            except Exception:
                pass

unique = sorted(set(name for name, _ in candidates))
if len(unique) == 1:
    print(unique[0])
elif len(unique) == 0:
    print("__NONE__")
else:
    allowed = allowed_paths(allowed_raw)
    narrowed = []
    for name, rel in candidates:
        prefix = "" if rel == "." else rel.rstrip("/") + "/"
        if prefix and any(p == rel or p.startswith(prefix) for p in allowed):
            narrowed.append(name)
    narrowed_unique = sorted(set(narrowed))
    if len(narrowed_unique) == 1:
        print(narrowed_unique[0])
    elif narrowed_unique:
        print("__MULTI__:" + ",".join(narrowed_unique))
    else:
        print("__MULTI__:" + ",".join(unique))
PY
)"

  multi_changeset_covers_candidates() {
    local candidate_list="$1"
    python3 - "$CHANGESET_DIR" "$TICKET" "$candidate_list" <<'PY'
import re
import sys
from pathlib import Path

changeset_dir = Path(sys.argv[1])
ticket = sys.argv[2].strip()
candidates = {p.strip() for p in sys.argv[3].split(",") if p.strip()}

if not ticket or not candidates:
    sys.exit(1)

ticket_lower = ticket.lower()
pkg_re = re.compile(r"""^\s*['"]?([^'":]+?)['"]?\s*:\s*(patch|minor|major)\s*$""")

for path in sorted(changeset_dir.glob("*.md")):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        continue

    # Avoid accepting inherited or unrelated changesets in stacked branches.
    if ticket_lower not in path.name.lower() and ticket not in text:
        continue

    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        continue

    packages = set()
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = pkg_re.match(line)
        if match:
            packages.add(match.group(1).strip())

    if candidates.issubset(packages):
        print(path)
        sys.exit(0)

sys.exit(1)
PY
  }

  case "$PACKAGE_SCOPE" in
    __NONE__)
      echo "polaris-changeset: could not derive package_scope from $CHANGESET_CONFIG (no public packages found)" >&2
      echo "  Add deliverables.changeset.package_scope to task.md (DP-033) or override via repo handbook." >&2
      exit 1
      ;;
    __MULTI__:*)
      multi_list="${PACKAGE_SCOPE#__MULTI__:}"
      if [[ "$SUB" == "check" ]] && matched_changeset="$(multi_changeset_covers_candidates "$multi_list" 2>/dev/null)"; then
        echo "polaris-changeset: check passed — multi-package changeset covers $multi_list ($matched_changeset)" >&2
        exit 0
      fi
      echo "polaris-changeset: multi-package changeset requires task.md 'deliverables.changeset.package_scope' declaration (DP-033 scope) or repo handbook override" >&2
      echo "  Candidates discovered: $multi_list" >&2
      exit 1
      ;;
    "")
      echo "polaris-changeset: package_scope derivation produced no output (parser error)" >&2
      exit 1
      ;;
  esac
fi

# --- Bump level (override > declared > L3 default = patch) -----------------
BUMP_LEVEL="patch"
if [[ -n "$DECLARED_BUMP_DEFAULT" ]]; then
  BUMP_LEVEL="$DECLARED_BUMP_DEFAULT"
fi
if [[ -n "$BUMP_OVERRIDE" ]]; then
  BUMP_LEVEL="$BUMP_OVERRIDE"
fi

# --- Slug derivation (declared > derived) ----------------------------------
derive_slug() {
  local ticket="$1"
  local title="$2"
  python3 - "$ticket" "$title" <<'PY'
import sys, re, unicodedata

ticket = sys.argv[1].strip()
title = sys.argv[2].strip()

# Strip ticket prefix from title:
#   [TICKET] foo  → foo
#   TICKET: foo   → foo
title = re.sub(r"^\s*\[[A-Za-z][A-Za-z0-9]*-\d+\]\s*", "", title)
title = re.sub(r"^\s*[A-Za-z][A-Za-z0-9]*-\d+\s*:\s*", "", title)
title = title.strip()

def kebab(s, max_len=60):
    # Normalize unicode (NFKD: separate accents); keep CJK/unicode word chars.
    s = unicodedata.normalize("NFKD", s)
    # Replace non-word chars with hyphens (keep unicode letters/digits).
    out = []
    prev_hyphen = False
    for ch in s:
        if ch.isalnum():
            out.append(ch.lower())
            prev_hyphen = False
        elif ch in "-_ \t":
            if not prev_hyphen and out:
                out.append("-")
                prev_hyphen = True
        # Drop punctuation / emoji silently.
    result = "".join(out).strip("-")
    # Truncate to max_len at word boundary.
    if len(result) > max_len:
        cut = result[:max_len]
        # Backtrack to last hyphen to preserve whole words.
        last_h = cut.rfind("-")
        if last_h > max_len * 0.5:
            cut = cut[:last_h]
        result = cut.rstrip("-")
    return result

ticket_kebab = ""
if ticket:
    ticket_kebab = ticket.lower()

short = kebab(title)
if not short:
    short = "change"

if ticket_kebab:
    print(f"{ticket_kebab}-{short}")
else:
    print(short)
PY
}

if [[ -n "$DECLARED_FILENAME_SLUG" ]]; then
  FILENAME_SLUG="$DECLARED_FILENAME_SLUG"
else
  FILENAME_SLUG="$(derive_slug "$TICKET" "$SUMMARY" || true)"
fi

if [[ -z "$FILENAME_SLUG" ]]; then
  echo "polaris-changeset: failed to derive filename_slug from ticket='$TICKET' title='$SUMMARY'" >&2
  exit 1
fi

OUTPUT_FILE="$CHANGESET_DIR/${FILENAME_SLUG}.md"

# --- Idempotent skip if file exists ----------------------------------------
if [[ -f "$OUTPUT_FILE" ]]; then
  if [[ "$SUB" == "check" ]]; then
    echo "polaris-changeset: check passed — $OUTPUT_FILE exists" >&2
  else
    echo "polaris-changeset: idempotent skip — $OUTPUT_FILE already exists" >&2
  fi
  exit 0
fi

if [[ "$SUB" == "check" ]]; then
  echo "polaris-changeset: check failed — expected changeset is missing: $OUTPUT_FILE" >&2
  echo "  Run: scripts/polaris-changeset.sh new --task-md \"$TASK_MD\"" >&2
  exit 1
fi

# --- Description: task.md title with strip mode (L3 default) ---------------
DESCRIPTION="$(python3 - "$SUMMARY" <<'PY'
import re, sys
title = sys.argv[1].strip()
title = re.sub(r"^\s*\[[A-Za-z][A-Za-z0-9]*-\d+\]\s*", "", title)
title = re.sub(r"^\s*[A-Za-z][A-Za-z0-9]*-\d+\s*:\s*", "", title)
print(title.strip())
PY
)"
if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="$SUMMARY"
fi

# --- Write changeset file ---------------------------------------------------
{
  printf -- "---\n"
  printf -- "\"%s\": %s\n" "$PACKAGE_SCOPE" "$BUMP_LEVEL"
  printf -- "---\n\n"
  printf -- "%s\n" "$DESCRIPTION"
} > "$OUTPUT_FILE"

if [[ ! -f "$OUTPUT_FILE" ]]; then
  echo "polaris-changeset: failed to write $OUTPUT_FILE" >&2
  exit 1
fi

echo "polaris-changeset: wrote $OUTPUT_FILE"
exit 0
