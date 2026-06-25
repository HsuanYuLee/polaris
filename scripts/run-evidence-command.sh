#!/usr/bin/env bash
# Purpose: DP-356 T1 — execute an evidence-bearing command on a proxy-immune
#          path so its stdout + exit code come from the REAL binary, not from a
#          transparent command-rewrite proxy's token-optimized summary. Defends
#          the verification evidence path (Verify Command, negative `! rg`,
#          patch-producing `git diff`, comparison `git apply`, `cksum`/`sha`
#          checks) against false-PASS / false-identical results.
# Inputs:  CLI: run-evidence-command.sh [--] <binary> [args...]
#            <binary>  evidence binary to run (rg, git, cksum, sha256sum, ...).
#            args      passed through verbatim to the resolved real binary.
#          Env (read): PATH (used only to resolve the binary's REAL absolute path).
# Outputs: stdout/stderr = the real binary's faithful output.
#          exit code     = the real binary's exit code (1 = usage / resolve error).
# Side effects: none (read-only execution wrapper; mutates nothing on disk).
#
# Immunity model (DP-356 Decisions D4, three layers):
#   (a) proxy-agnostic: the command runs inside THIS script's subprocess. A
#       PreToolUse rewrite proxy (e.g. rtk) only rewrites the outermost Bash
#       tool-call string `bash scripts/run-evidence-command.sh ...`; it cannot
#       see or rewrite the binary we exec from inside the script.
#   (c) proxy-agnostic: the binary is resolved to an ABSOLUTE path against a
#       fixed allowlist of trusted SYSTEM bin directories — NOT against the
#       caller's inherited PATH ordering. This bypasses both shell function
#       wrappers AND PATH-front shims a proxy may inject (proxies hook the
#       command; they do not relocate the system's real /usr/bin, /opt/homebrew
#       binaries). The resolution does not depend on where a proxy injects,
#       only on where real binaries live, so it is proxy-rule agnostic.
#   (b) proxy-specific (extensible, defense-in-depth): a kill-switch env
#       allowlist is exported before exec. rtk's `RTK_DISABLED=1` is the FIRST
#       entry; new proxies add their kill-switch env to PROXY_KILL_SWITCH_ENV
#       without touching the mechanism skeleton.

set -euo pipefail

# --- Proxy kill-switch env allowlist (extensible; D4 layer b) ----------------
# Each entry is a `NAME=VALUE` pair exported into the subprocess to disable a
# known command-rewrite proxy. rtk is the first entry (DP-356). Adding a new
# proxy = append one pair here; the rest of the mechanism is proxy-agnostic.
PROXY_KILL_SWITCH_ENV=(
  "RTK_DISABLED=1"
)

# --- Trusted system bin directories (D4 layer c) -----------------------------
# Real evidence binaries are resolved against THIS fixed allowlist, not against
# the caller's inherited PATH ordering. Command-rewrite proxies hook commands
# (function wrapper / front-injected shim dir); they do not relocate the OS's
# real binaries in /usr/bin, /bin, /opt/homebrew/bin, etc. Resolving against the
# trusted set is therefore immune to a proxy injecting a shim ahead on PATH.
# Override (e.g. for selftest fixtures or non-standard installs) via the
# POLARIS_EVIDENCE_TRUSTED_BIN_DIRS env (colon-separated, prepended).
TRUSTED_BIN_DIRS=(
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /usr/local/bin
  /usr/local/sbin
  /usr/bin
  /bin
  /usr/sbin
  /sbin
)

usage() {
  cat <<EOF >&2
Usage:
  $(basename "$0") [--] <binary> [args...]

Runs an evidence-bearing command on a proxy-immune path: the binary is resolved
to its real absolute path (bypassing function wrappers / PATH shims) and run in
this script's subprocess (immune to PreToolUse command-rewrite proxies), with
the kill-switch env allowlist exported. stdout and exit code are the real
binary's faithful output.

Exit:  <binary exit code> on execution, 1 = usage / binary-not-resolvable.
EOF
}

# --- Parse args --------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 1
fi
if [[ "${1:-}" == "--" ]]; then
  shift
fi
if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

binary="$1"
shift

# --- Resolve the REAL absolute binary path -----------------------------------
# Resolution rules (bypass function wrappers AND proxy PATH-front shims):
#   1. An absolute binary path is used as-is (caller-pinned).
#   2. Otherwise scan TRUSTED_BIN_DIRS (plus any POLARIS_EVIDENCE_TRUSTED_BIN_DIRS
#      override prefix) for the first executable match. We do NOT trust the
#      inherited PATH ordering, so a shim injected ahead on PATH cannot win.
resolve_real_binary() {
  local name="$1"
  if [[ "$name" == /* ]]; then
    [[ -x "$name" ]] && { printf '%s\n' "$name"; return 0; }
    return 1
  fi
  local -a search_dirs=()
  if [[ -n "${POLARIS_EVIDENCE_TRUSTED_BIN_DIRS:-}" ]]; then
    local IFS=':'
    # shellcheck disable=SC2206
    local -a override=(${POLARIS_EVIDENCE_TRUSTED_BIN_DIRS})
    search_dirs+=("${override[@]}")
  fi
  search_dirs+=("${TRUSTED_BIN_DIRS[@]}")
  local dir candidate
  for dir in "${search_dirs[@]}"; do
    candidate="$dir/$name"
    if [[ -x "$candidate" && ! -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

real_binary="$(resolve_real_binary "$binary")" || {
  echo "POLARIS_TOOL_MISSING:$binary — evidence binary not resolvable to a real absolute path" >&2
  exit 1
}

# --- Execute on the immune path ----------------------------------------------
# Export the kill-switch allowlist, then exec the real binary by absolute path.
# `exec` replaces this subprocess so the real binary's exit code propagates
# unchanged to the caller.
export "${PROXY_KILL_SWITCH_ENV[@]}"
exec "$real_binary" "$@"
