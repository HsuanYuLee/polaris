#!/usr/bin/env bash
# Purpose: map a set of changed files to the selftest dependency closure that must
#          run, then either print that closure or run it (DP-360 T3 / AC7 / AC-NEG5).
#          Closure is computed STATICALLY from three EXISTING sources — no second
#          classifier (D8):
#            1. naming convention   : scripts/<name>.sh -> scripts/selftests/<name>-selftest.sh
#                                     (and the *-selftest.sh file itself is its own member).
#            2. mechanism-registry  : .claude/rules/mechanism-registry.md Runtime Annotation
#                                     table `path` + `fallback_script` columns map a changed
#                                     mechanism/hook/script to its governing selftest.
#            3. scripts/manifest.json: the per-script `selftest` field (explicit
#                                     script -> selftest mapping, 176 entries).
#          A changed file on a SHARED / high-fanout surface escalates to the FULL
#          corpus (NEG5): such a change can affect any selftest, so the affected
#          layer must NOT silent-pass a narrow subset — it emits the full-corpus
#          sentinel and the caller runs the backstop. The closure computation is
#          purely static and does NOT depend on the T1 wall-clock tier manifest cache
#          (that cache only informs speed/tier, never the affected closure).
# Inputs:  --changed <path>     a changed repo-relative file (repeatable). When no
#                               --changed is given, the newline-separated changed
#                               list is read from stdin.
#          --root <repo>        workspace root (default: repo containing this script).
#          --base-ref <ref>     comparison base for targeted red classification
#                               (default: upstream merge-base, then origin/main).
#          --emit               EMIT MODE (default): print the affected selftest set,
#                               one repo-relative path per line, deterministically
#                               sorted. When the change set escalates to full corpus,
#                               print the single sentinel line POLARIS_AFFECTED_FULL_CORPUS.
#          --run                RUN MODE: compute the closure and execute each member
#                               selftest; on full-corpus escalation, delegate to
#                               scripts/run-aggregate-selftests.sh (the canonical full
#                               backstop). Any red member -> exit 1.
# Outputs: --emit -> affected set (or full-corpus sentinel) on stdout; exit 0, exit 2
#                    on arg / missing-input contract error (fail-closed; POLARIS_*).
#          --run  -> runs the closure; exit 0 all-green, exit 1 any red, exit 2 on
#                    contract error.
set -euo pipefail

# --- Named constants ---------------------------------------------------------
# Sentinel printed (emit mode) / matched (run mode) when the change set escalates
# to the full corpus. A distinct, greppable token so callers never confuse "no
# affected selftests" (empty) with "must run everything" (this sentinel).
readonly FULL_CORPUS_SENTINEL="POLARIS_AFFECTED_FULL_CORPUS"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MODE="emit"
BASE_REF="${POLARIS_AFFECTED_BASE_REF:-}"
BASE_WORKTREE=""
CHANGED_FILES=()

die() {
  printf '%s\n' "$1" >&2
  exit 2
}

# require_tool — fail-stop with a POLARIS_TOOL_MISSING repair hint when a required
# Polaris-runtime binary is absent (no silent install).
# Args: $1 = tool name. Side effects: exit 2 if missing.
require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    printf 'POLARIS_TOOL_MISSING:%s — run `mise install` to restore the Polaris runtime toolchain\n' "$tool" >&2
    exit 2
  fi
}

# --- Arg parsing -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      [[ $# -ge 2 ]] || die "POLARIS_AFFECTED_ARG: --root requires a value"
      ROOT_DIR="$(cd "$2" && pwd)" || die "POLARIS_AFFECTED_ARG: --root path not found: $2"
      shift 2
      ;;
    --changed)
      [[ $# -ge 2 ]] || die "POLARIS_AFFECTED_ARG: --changed requires a value"
      CHANGED_FILES+=("$2")
      shift 2
      ;;
    --base-ref)
      [[ $# -ge 2 ]] || die "POLARIS_AFFECTED_ARG: --base-ref requires a value"
      BASE_REF="$2"
      shift 2
      ;;
    --emit)
      MODE="emit"
      shift
      ;;
    --run)
      MODE="run"
      shift
      ;;
    -h | --help)
      sed -n '2,40p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      die "POLARIS_AFFECTED_ARG: unknown argument: $1"
      ;;
  esac
done

cleanup_base_worktree() {
  if [[ -n "${BASE_WORKTREE:-}" && -d "$BASE_WORKTREE" ]]; then
    git -C "$ROOT_DIR" worktree remove --force "$BASE_WORKTREE" >/dev/null 2>&1 || true
  fi
}
trap cleanup_base_worktree EXIT

resolve_base_ref() {
  if [[ -n "$BASE_REF" ]]; then
    printf '%s\n' "$BASE_REF"
    return 0
  fi

  local upstream=""
  upstream="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -n "$upstream" ]]; then
    git -C "$ROOT_DIR" merge-base HEAD "$upstream" 2>/dev/null && return 0
  fi
  git -C "$ROOT_DIR" merge-base HEAD origin/main 2>/dev/null && return 0
  return 1
}

ensure_base_worktree() {
  if [[ -n "${BASE_WORKTREE:-}" && -d "$BASE_WORKTREE" ]]; then
    return 0
  fi
  local base="" candidate=""
  base="$(resolve_base_ref || true)"
  [[ -n "$base" ]] || return 1
  candidate="$(mktemp -d -t affected-base.XXXXXX)"
  rmdir "$candidate" || return 1
  git -C "$ROOT_DIR" worktree add -q --detach "$candidate" "$base" >/dev/null 2>&1 || return 1
  BASE_WORKTREE="$candidate"
}

is_tracked_base_debt() {
  local member="$1" current_rc="$2" current_log="$3"
  local base_log="" base_rc=0
  ensure_base_worktree || return 1
  [[ -f "$BASE_WORKTREE/$member" ]] || return 1
  base_log="$(mktemp -t affected-base-output.XXXXXX)"
  set +e
  bash "$BASE_WORKTREE/$member" >"$base_log" 2>&1
  base_rc=$?
  set -e
  if [[ "$base_rc" -eq 0 || "$base_rc" -ne "$current_rc" ]]; then
    rm -f "$base_log"
    return 1
  fi
  require_tool python3
  if python3 - "$current_log" "$base_log" "$ROOT_DIR" "$BASE_WORKTREE" <<'PY'
import hashlib
import sys
from pathlib import Path

current_path, base_path, current_root, base_root = sys.argv[1:]


def signature(path, own_root, other_root):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    text = text.replace(own_root, "<ROOT>").replace(other_root, "<ROOT>")
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


raise SystemExit(
    0
    if signature(current_path, current_root, base_root)
    == signature(base_path, base_root, current_root)
    else 1
)
PY
  then
    rm -f "$base_log"
    return 0
  fi
  rm -f "$base_log"
  return 1
}

# When no --changed flags were given, read the changed list from stdin (one path
# per line). Empty / whitespace lines are dropped.
if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  while IFS= read -r _line; do
    [[ -n "$_line" ]] && CHANGED_FILES+=("$_line")
  done
fi

# Fail-closed on a missing changed set: an empty change set is a contract error,
# not "nothing to run" (a no-op push should never reach this runner). This keeps
# the gate fail-closed (NEG4) — silence is never synthesized from missing input.
if [[ ${#CHANGED_FILES[@]} -eq 0 ]]; then
  die "POLARIS_AFFECTED_NO_CHANGED_FILES: no changed files supplied (--changed or stdin); refusing to fail-open"
fi

MECHANISM_REGISTRY="$ROOT_DIR/.claude/rules/mechanism-registry.md"
SCRIPT_MANIFEST="$ROOT_DIR/scripts/manifest.json"

# is_shared_surface — return 0 if a changed repo-relative path is on a shared /
# high-fanout surface that escalates to the full corpus (NEG5). Same shared-surface
# tokens as scripts/selftest-tier-manifest.sh classify_scope (top-level scripts/*.sh
# helpers, .claude rules/skills/hooks/instructions) PLUS the runtime-instruction
# manifest / scripts manifest / mechanism-registry themselves (changing the closure
# sources can affect any selftest). Single-quoted patterns (shell-quoting discipline):
# the backslash/dot are literal regex, not shell metacharacters.
# Args: $1 = repo-relative changed path. Side effects: none (read-only).
is_shared_surface() {
  local rel="$1"
  case "$rel" in
    # The closure sources themselves: a change here can re-map any closure.
    .claude/rules/mechanism-registry.md | scripts/manifest.json) return 0 ;;
    # Shared rules / skills / hooks / instructions surfaces.
    .claude/rules/*.md | .claude/skills/* | .claude/hooks/* | .claude/instructions/*) return 0 ;;
    # Runtime-instruction generated targets / config surfaces.
    CLAUDE.md | AGENTS.md | .codex/AGENTS.md | .github/copilot-instructions.md) return 0 ;;
    workspace-config.yaml | mise.toml) return 0 ;;
  esac
  # Shared library helpers under scripts/lib/ are consumed by many gates -> full.
  case "$rel" in
    scripts/lib/*) return 0 ;;
  esac
  return 1
}

full_corpus_state_is_stale() {
  local evaluator="$ROOT_DIR/.claude/hooks/selftest-staleness-eval.sh"
  local report=""
  [[ -f "$evaluator" ]] || return 0
  report="$(CLAUDE_PROJECT_DIR="$ROOT_DIR" bash "$evaluator" --report </dev/null 2>/dev/null || true)"
  if [[ "$report" == *"decision=FRESH"* ]]; then
    return 1
  fi
  return 0
}

# closure_from_naming — print the naming-convention selftest member(s) for a changed
# path, if the file exists on disk. Two directions:
#   scripts/<name>.sh           -> scripts/selftests/<name>-selftest.sh (when present)
#                                  and scripts/<name>-selftest.sh (sibling form).
#   scripts/selftests/<x>.sh    -> itself (a changed selftest must run itself).
# Args: $1 = repo-relative changed path. Side effects: none (read-only).
closure_from_naming() {
  local rel="$1" base candidate
  case "$rel" in
    scripts/selftests/*-selftest.sh | scripts/*-selftest.sh)
      # A changed selftest is its own closure member.
      printf '%s\n' "$rel"
      return 0
      ;;
    scripts/*.sh)
      base="$(basename "$rel" .sh)"
      candidate="scripts/selftests/${base}-selftest.sh"
      [[ -f "$ROOT_DIR/$candidate" ]] && printf '%s\n' "$candidate"
      candidate="scripts/${base}-selftest.sh"
      [[ -f "$ROOT_DIR/$candidate" ]] && printf '%s\n' "$candidate"
      ;;
    .claude/hooks/*.sh)
      # A hook foo.sh maps to scripts/selftests/foo-selftest.sh by naming when present.
      base="$(basename "$rel" .sh)"
      candidate="scripts/selftests/${base}-selftest.sh"
      [[ -f "$ROOT_DIR/$candidate" ]] && printf '%s\n' "$candidate"
      ;;
  esac
  return 0
}

# closure_from_mechanism_registry — print the selftest member(s) the mechanism
# registry Runtime Annotation table associates with a changed path. The table rows
# are `| mechanism | path | kind | runtime | fallback_script | governance_role |`;
# when a row's `path` column equals the changed file, any `fallback_script` that is
# a selftest is a closure member. Reuses the registry as the single source of the
# mechanism->script mapping (no second table). Args: $1 = changed path.
# Side effects: none (read-only).
closure_from_mechanism_registry() {
  local rel="$1"
  [[ -f "$MECHANISM_REGISTRY" ]] || return 0
  require_tool python3
  python3 - "$MECHANISM_REGISTRY" "$rel" <<'PY'
import sys

registry, changed = sys.argv[1], sys.argv[2]
members = []
with open(registry, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        # Runtime Annotation table has 6 columns:
        # mechanism | path | kind | runtime | fallback_script | governance_role
        if len(cells) != 6:
            continue
        path, fallback = cells[1], cells[4]
        if path != changed:
            continue
        if fallback and fallback != "N/A" and fallback.endswith("-selftest.sh"):
            members.append(fallback)
        # When the row's `path` IS itself a selftest, that selftest is the member.
        if path.endswith("-selftest.sh"):
            members.append(path)
for m in sorted(set(members)):
    print(m)
PY
}

# closure_from_manifest — print the selftest member the scripts manifest maps a
# changed script to, via the per-entry `selftest` field. Reuses manifest.json as the
# single source of the explicit script->selftest mapping (no second mapping table).
# Args: $1 = changed path. Side effects: none (read-only).
closure_from_manifest() {
  local rel="$1"
  [[ -f "$SCRIPT_MANIFEST" ]] || return 0
  require_tool python3
  python3 - "$SCRIPT_MANIFEST" "$rel" <<'PY'
import json
import sys

manifest, changed = sys.argv[1], sys.argv[2]
try:
    with open(manifest, encoding="utf-8") as fh:
        doc = json.load(fh)
    entries = doc["scripts"]
except Exception as exc:  # noqa: BLE001 - malformed manifest is a contract failure
    print(f"POLARIS_AFFECTED_MANIFEST_MALFORMED:{exc}", file=sys.stderr)
    sys.exit(2)

for e in entries:
    if e.get("path") != changed:
        continue
    st = e.get("selftest", "N/A")
    if st and st != "N/A" and st.endswith("-selftest.sh"):
        print(st)
PY
}

# --- Compute closure ---------------------------------------------------------
# A stale, missing, malformed, or unavailable canonical full-run state widens
# every change set to the full backstop. The pre-push adapter consumes the emit
# sentinel and defers execution to the PR/promotion lane; direct --run callers
# execute the backstop now. A fresh state permits normal affected selection.
if full_corpus_state_is_stale; then
  if [[ "$MODE" == "emit" ]]; then
    printf '%s\n' "$FULL_CORPUS_SENTINEL"
    exit 0
  fi
  backstop="$ROOT_DIR/scripts/run-aggregate-selftests.sh"
  [[ -f "$backstop" ]] || die "POLARIS_AFFECTED_BACKSTOP_MISSING: $backstop (stale full-corpus state cannot run)"
  exec bash "$backstop" --root "$ROOT_DIR"
fi

# First pass: any shared-surface changed path escalates the whole run to full corpus.
escalate_full=0
for rel in "${CHANGED_FILES[@]}"; do
  if is_shared_surface "$rel"; then
    escalate_full=1
    break
  fi
done

if [[ "$escalate_full" -eq 1 ]]; then
  if [[ "$MODE" == "emit" ]]; then
    printf '%s\n' "$FULL_CORPUS_SENTINEL"
    exit 0
  fi
  # RUN mode: delegate to the canonical full backstop runner (no second corpus
  # enumeration). Fail-closed on a missing backstop runner.
  backstop="$ROOT_DIR/scripts/run-aggregate-selftests.sh"
  [[ -f "$backstop" ]] || die "POLARIS_AFFECTED_BACKSTOP_MISSING: $backstop (full-corpus escalation cannot run)"
  exec bash "$backstop" --root "$ROOT_DIR"
fi

# Narrow closure: union the three static sources.
closure=""
for rel in "${CHANGED_FILES[@]}"; do
  closure+="$(closure_from_naming "$rel")"$'\n'
  closure+="$(closure_from_mechanism_registry "$rel")"$'\n'
  closure+="$(closure_from_manifest "$rel")"$'\n'
done

# Keep only members that exist on disk (a stale mapping must not phantom-run), sorted
# and de-duplicated for byte-stable output.
affected=""
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  [[ -f "$ROOT_DIR/$member" ]] || continue
  affected+="${member}"$'\n'
done <<<"$closure"
affected="$(printf '%s' "$affected" | grep -v '^$' | LC_ALL=C sort -u || true)"

if [[ "$MODE" == "emit" ]]; then
  [[ -n "$affected" ]] && printf '%s\n' "$affected"
  exit 0
fi

# --- RUN mode (narrow closure) ----------------------------------------------
if [[ -z "$affected" ]]; then
  # No mapped selftest for the change set. This is NOT a silent pass: a code change
  # with no closure member is suspicious, so fail-closed and tell the caller to widen
  # the mapping or run the full backstop (NEG5 — affected must not pretend to be full).
  printf 'POLARIS_AFFECTED_NO_CLOSURE: no selftest closure for changed set; run the full backstop or extend the mapping\n' >&2
  exit 2
fi

rc=0
while IFS= read -r member; do
  [[ -n "$member" ]] || continue
  member_log="$(mktemp -t affected-current-output.XXXXXX)"
  set +e
  bash "$ROOT_DIR/$member" 2>&1 | tee "$member_log"
  member_rc=${PIPESTATUS[0]}
  set -e
  if [[ "$member_rc" -eq 0 ]]; then
    rm -f "$member_log"
    continue
  fi
  if is_tracked_base_debt "$member" "$member_rc" "$member_log"; then
    printf 'TRACKED_DEBT %s — also red on comparison base\n' "$member"
    rm -f "$member_log"
    continue
  fi
  printf 'POLARIS_AFFECTED_SELFTEST_RED:%s\n' "$member" >&2
  rm -f "$member_log"
  rc=1
done <<<"$affected"
exit "$rc"
