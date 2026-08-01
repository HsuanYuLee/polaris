#!/usr/bin/env bash
# Hardened oracle runner: execute a measurement command so the tools cannot lie.
#
# The plain path (`bash -c "$cmd"` with the inherited PATH) is faithful to the
# environment, which is exactly the problem: whatever sits earliest on PATH gets
# executed, and its exit 0 is read as PASS. Three shapes, all taken from real
# incidents, defeat an unhardened runner:
#
#   (a) `rg` replaced by a BSD-grep-shaped shim that ignores `--pcre2`, so a
#       negative assertion (`! rg …`) inverts into exit 0.
#   (b) a test runner that silently skips everything, reports coverage 0, and
#       still exits 0.
#   (c) a curl error swallowed into a generic timeout, which downstream logic
#       treats as flaky rather than failed.
#
# Three counters, in the same order:
#
#   1. Capability probe, not location trust. Each required tool must answer a
#      declared probe (`rg:--pcre2 --version`). A shim that cannot do the thing
#      the command depends on fails the probe and the run stops. The probed
#      binary is then pinned by absolute path into a private bin directory that
#      leads PATH, so nothing can be swapped underneath the command mid-run.
#   2. Positive evidence, not merely exit 0. The command must emit something
#      that proves it measured (`--expect-evidence`). Silence is not success.
#   3. stderr and exit code are preserved verbatim. Nothing is remapped,
#      nothing is discarded, and both are recorded in the evidence record.
#
# Fail-closed everywhere: a tool that cannot be resolved, or cannot answer its
# probe, stops the run and names the tool. There is no fallback to the inherited
# PATH — a silent fallback would reinstate the exact hole being closed.
#
# Usage:
#   run-hardened-oracle.sh --command <cmd>
#       [--require-tool <name>[:<probe args>]]...
#       [--expect-evidence <regex>]... [--forbid-evidence <regex>]...
#       [--min-evidence-bytes <n>] [--evidence-out <path>]
#       [--cwd <dir>] [--system-path <dir:dir:...>]
#
# Exit codes:
#   0  command exited 0, every probe answered, positive evidence present
#   1  command exited non-zero (its own code is reported in the evidence record)
#   2  hardening refused the run or the verdict (marker on stderr)

set -uo pipefail

DEFAULT_SYSTEM_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

COMMAND=""
HAVE_COMMAND="no"
CWD=""
SYSTEM_PATH="$DEFAULT_SYSTEM_PATH"
EVIDENCE_OUT=""
MIN_EVIDENCE_BYTES=0
REQUIRE_TOOLS=()
EXPECT_PATTERNS=()
FORBID_PATTERNS=()

usage() {
  cat >&2 <<'EOF'
Usage:
  run-hardened-oracle.sh --command <cmd>
      [--require-tool <name>[:<probe args>]]...
      [--expect-evidence <regex>]... [--forbid-evidence <regex>]...
      [--min-evidence-bytes <n>] [--evidence-out <path>]
      [--cwd <dir>] [--system-path <dir:dir:...>]
EOF
}

die() {
  # Description: emit a POLARIS marker plus human message, then fail closed.
  # Args: $1 = marker, $2.. = message
  local marker="$1"
  shift
  echo "$marker" >&2
  echo "$*" >&2
  exit 2
}

require_python3() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) COMMAND="${2:-}"; HAVE_COMMAND="yes"; shift 2 ;;
    --require-tool) REQUIRE_TOOLS+=("${2:-}"); shift 2 ;;
    --expect-evidence) EXPECT_PATTERNS+=("${2:-}"); shift 2 ;;
    --forbid-evidence) FORBID_PATTERNS+=("${2:-}"); shift 2 ;;
    --min-evidence-bytes) MIN_EVIDENCE_BYTES="${2:-0}"; shift 2 ;;
    --evidence-out) EVIDENCE_OUT="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    --system-path) SYSTEM_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$HAVE_COMMAND" == "yes" && -n "$COMMAND" ]] || { usage; exit 2; }

require_python3

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PINNED_BIN="$WORK/pinned-bin"
mkdir -p "$PINNED_BIN"

STDOUT_FILE="$WORK/stdout.log"
STDERR_FILE="$WORK/stderr.log"

resolve_tool() {
  # Description: print the absolute path of a tool, searching the inherited
  #              PATH first and the declared system path second.
  # Args: $1 = tool name
  # Side effects: none; prints nothing when the tool cannot be resolved.
  local name="$1" candidate
  candidate="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  local dir
  IFS=':' read -r -a _dirs <<< "$SYSTEM_PATH"
  for dir in "${_dirs[@]}"; do
    if [[ -x "$dir/$name" ]]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
  done
  return 1
}

TOOL_RECORDS=()

for spec in "${REQUIRE_TOOLS[@]:-}"; do
  [[ -n "$spec" ]] || continue
  tool_name="${spec%%:*}"
  probe_args=""
  [[ "$spec" == *:* ]] && probe_args="${spec#*:}"

  resolved="$(resolve_tool "$tool_name" || true)"
  if [[ -z "$resolved" ]]; then
    die "POLARIS_ORACLE_TOOL_UNRESOLVED:$tool_name" \
      "required tool '$tool_name' could not be resolved; refusing to run with the inherited PATH as a fallback"
  fi

  probe_status=0
  if [[ -n "$probe_args" ]]; then
    # The probe is the trust test: a shim wearing the right name but lacking the
    # capability the command depends on fails here, wherever it sits on PATH.
    # shellcheck disable=SC2086
    "$resolved" $probe_args >/dev/null 2>&1 || probe_status=$?
    if [[ "$probe_status" -ne 0 ]]; then
      die "POLARIS_ORACLE_TOOL_CAPABILITY_FAILED:$tool_name" \
        "'$resolved' did not answer its capability probe ($tool_name $probe_args, exit $probe_status); the tool on PATH cannot do what this measurement depends on"
    fi
  fi

  ln -sf "$resolved" "$PINNED_BIN/$tool_name"
  TOOL_RECORDS+=("$tool_name|$resolved|$probe_args|$probe_status")
done

# The command runs against pinned binaries first, then a declared system path.
# The inherited PATH does not survive into the command.
export PATH="$PINNED_BIN:$SYSTEM_PATH"

run_dir="${CWD:-$PWD}"
[[ -d "$run_dir" ]] || die "POLARIS_ORACLE_CWD_MISSING" "working directory not found: $run_dir"

COMMAND_EXIT=0
(
  cd "$run_dir" || exit 127
  bash -c "$COMMAND"
) > "$STDOUT_FILE" 2> "$STDERR_FILE" || COMMAND_EXIT=$?

# Replay both streams verbatim on the runner's own descriptors. Nothing is
# merged, reordered, or dropped: a caller reading stderr sees what the command
# actually said.
cat "$STDOUT_FILE"
cat "$STDERR_FILE" >&2

combined="$WORK/combined.log"
cat "$STDOUT_FILE" "$STDERR_FILE" > "$combined"

VERDICT="PASS"
MARKER=""
DETAIL=""

if [[ "$COMMAND_EXIT" -ne 0 ]]; then
  VERDICT="FAIL"
  MARKER="POLARIS_ORACLE_COMMAND_FAILED"
  DETAIL="command exited $COMMAND_EXIT"
fi

if [[ "$VERDICT" == "PASS" ]]; then
  evidence_bytes="$(wc -c < "$combined" | tr -d ' ')"
  if [[ "$evidence_bytes" -lt "$MIN_EVIDENCE_BYTES" ]]; then
    VERDICT="NOT_PASS"
    MARKER="POLARIS_ORACLE_NO_POSITIVE_EVIDENCE"
    DETAIL="command produced ${evidence_bytes} bytes of output, below the required ${MIN_EVIDENCE_BYTES}; exit 0 without output is not a measurement"
  fi
fi

if [[ "$VERDICT" == "PASS" ]]; then
  for pattern in "${EXPECT_PATTERNS[@]:-}"; do
    [[ -n "$pattern" ]] || continue
    if ! grep -Eq "$pattern" "$combined"; then
      VERDICT="NOT_PASS"
      MARKER="POLARIS_ORACLE_NO_POSITIVE_EVIDENCE"
      DETAIL="command exited 0 but never emitted the positive evidence it was required to produce: /$pattern/"
      break
    fi
  done
fi

if [[ "$VERDICT" == "PASS" ]]; then
  for pattern in "${FORBID_PATTERNS[@]:-}"; do
    [[ -n "$pattern" ]] || continue
    if grep -Eq "$pattern" "$combined"; then
      VERDICT="NOT_PASS"
      MARKER="POLARIS_ORACLE_FORBIDDEN_EVIDENCE"
      DETAIL="command output matched a pattern that marks a non-measurement: /$pattern/"
      break
    fi
  done
fi

if [[ -n "$EVIDENCE_OUT" ]]; then
  python3 - "$EVIDENCE_OUT" "$COMMAND" "$COMMAND_EXIT" "$VERDICT" "$MARKER" "$DETAIL" \
    "$STDOUT_FILE" "$STDERR_FILE" "${TOOL_RECORDS[@]:-}" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(out, command, exit_code, verdict, marker, detail, stdout_path, stderr_path) = sys.argv[1:9]
tools = []
for record in sys.argv[9:]:
    if not record:
        continue
    name, resolved, probe, status = record.split("|", 3)
    tools.append({
        "name": name,
        "resolved_path": resolved,
        "capability_probe": probe or None,
        "capability_probe_exit": int(status),
    })

payload = {
    "schema_version": 1,
    "producer": "run-hardened-oracle.sh",
    "command": command,
    "command_exit_code": int(exit_code),
    "verdict": verdict,
    "marker": marker or None,
    "detail": detail or None,
    "tools": tools,
    "stdout": open(stdout_path, encoding="utf-8", errors="replace").read(),
    "stderr": open(stderr_path, encoding="utf-8", errors="replace").read(),
    "recorded_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
with open(out, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
fi

if [[ "$VERDICT" == "PASS" ]]; then
  echo "PASS: hardened oracle verdict PASS (command exit 0, positive evidence present)"
  exit 0
fi

echo "$MARKER" >&2
echo "$DETAIL" >&2
# The command's own exit code is preserved in the evidence record; the runner
# reports 1 for a genuine command failure and 2 for a hardening refusal.
[[ "$VERDICT" == "FAIL" ]] && exit 1
exit 2
