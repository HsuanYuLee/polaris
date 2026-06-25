#!/usr/bin/env bash
# Purpose: A-class fail-closed lint (DP-356 T2, AC3) against running an
#   EVIDENCE-BEARING command as a DIRECT Bash tool call — i.e. a command whose
#   stdout + exit code ARE the verification evidence, but which is executed over
#   the inherited PATH binary instead of an immune path. When a transparent
#   command-rewrite proxy (e.g. rtk) rewrites the outermost Bash tool-call
#   string, these commands return token-optimized summaries that flip the
#   evidence: a negative `! rg` becomes a false PASS, two different files get
#   reported "identical". The immune path (run-evidence-command.sh, or an
#   absolute-binary path) takes the evidence from the REAL binary instead.
#
# Inputs:  CLI args = paths to scan (task.md Verify Command blocks, candidate
#   evidence-gathering scripts, fixtures). `--allowlist <file>` supplies
#   `<path>:<reason>` per-line exemptions for sites that genuinely need a direct
#   call (documented; never an off switch). `--self-check` is an optional
#   convenience that scans scripts/** + .claude/** without asserting tree
#   cleanliness — it surfaces candidate sites for review, not a release gate.
#
# Scope note (DP-356): the A-class gateable slice this lint owns is "an
# evidence-bearing command typed as a DIRECT tool call to gather DP verification
# evidence". The lint is fixture-proven (selftest) and meant to be pointed at
# specific evidence-gathering targets. It is intentionally NOT wired as a
# whole-repo `--self-check` release gate: committed framework scripts use rg /
# git / checksum binaries for their own internal control flow (not as DP
# verification evidence), so a blanket tree scan would conflate them. The
# residual "sub-agent ad-hoc evidence gathering" has no persistent callsite and
# is the B-class canary half (.claude/rules/mechanism-registry.md).
# Outputs: stderr `POLARIS_EVIDENCE_DIRECT_CALL: <file>:<line>` per violation.
# Exit:
#   0 — no violations (or all violations allowlisted)
#   2 — at least one un-allowlisted direct-call evidence command; stderr lists
#       the offending sites
#
# Evidence-bearing patterns flagged (DP-356 Blind Spots enumeration):
#   - `! rg <pattern>`            negative-assertion grep (false-PASS shape)
#   - `rg --pcre2` / `rg -P`      PCRE2 grep (BSD-grep-rewrite-error shape)
#   - `git apply`                 patch application (comparison evidence)
#   - `git diff --no-index`       file comparison (false-identical shape)
#   - `cksum` / `sha1sum` / `sha256sum` / `shasum`   checksum comparison
#
# NOT flagged (safe):
#   - AC-NEG1: general dev `rg foo` (no --pcre2/-P, no leading `!`), plain
#     `git diff` (no --no-index), and comment lines — ordinary proxy-rewritten
#     dev operations are intentionally left alone.
#   - AC-NEG2: a flagged pattern already on an immune path — routed through
#     `run-evidence-command.sh`, or invoked via an absolute binary path
#     (e.g. /opt/homebrew/bin/rg, /usr/bin/git) — these read the real binary.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ALLOWLIST=""
SELF_CHECK=0
declare -a TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --allowlist)
      ALLOWLIST="${2:-}"
      shift 2
      ;;
    --self-check)
      SELF_CHECK=1
      shift
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do TARGETS+=("$1"); shift; done
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [[ "$SELF_CHECK" -eq 1 ]]; then
  while IFS= read -r -d '' p; do
    TARGETS+=("$p")
  done < <(
    find "${WORKSPACE_ROOT}/scripts" "${WORKSPACE_ROOT}/.claude" \
      -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' -o -name '*.ts' \) \
      -print0 2>/dev/null || true
  )
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  exit 0
fi

python3 - "${ALLOWLIST}" "${TARGETS[@]}" <<'PY'
import os
import re
import sys

allowlist_path = sys.argv[1]
targets = sys.argv[2:]

# Load <path>:<reason> allowlist. The reason is mandatory (it documents why the
# site genuinely needs a direct call); an entry without a non-empty reason is
# rejected so the allowlist can never become an undocumented blanket exemption.
# Allowlisted paths are matched by realpath, so a per-path entry can never
# become an over-broad directory wildcard.
allowed = set()
if allowlist_path:
    try:
        with open(allowlist_path, encoding="utf-8") as fh:
            for raw in fh:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                path, sep, reason = line.partition(":")
                if not sep or not reason.strip():
                    sys.stderr.write(
                        "POLARIS_EVIDENCE_DIRECT_CALL: malformed allowlist entry "
                        f"(need <path>:<reason>): {line}\n"
                    )
                    sys.exit(2)
                allowed.add(os.path.realpath(path.strip()))
    except OSError as exc:
        sys.stderr.write(
            f"POLARIS_EVIDENCE_DIRECT_CALL: cannot read allowlist: {exc}\n"
        )
        sys.exit(2)

# --- Immune-path recognition (AC-NEG2) --------------------------------------
# A line is already immune when the evidence command is routed through the
# DP-356 T1 helper, or invoked via an absolute binary path (which bypasses
# function wrappers AND PATH-front shims a proxy may inject).
immune_helper = re.compile(r"run-evidence-command\.sh")
# An absolute path to the evidence binary, e.g. /opt/homebrew/bin/rg,
# /usr/bin/git, /usr/bin/cksum, /sbin/sha256sum. The token right before the
# evidence binary name is an absolute path component.
absolute_binary = re.compile(
    r"(?:^|[\s!|(=])/(?:[\w.+-]+/)+(?:rg|git|cksum|sha1sum|sha256sum|shasum)\b"
)

def is_immune(line: str) -> bool:
    return bool(immune_helper.search(line) or absolute_binary.search(line))

# --- Evidence-bearing command patterns (AC3) --------------------------------
# Each entry: (compiled regex, short label). The regexes match the evidence-
# bearing STRUCTURE so adversarial flag-order / variable-interpolation variants
# are still caught (refinement.json adversarial_pass AC3).

# `! rg <pattern>` — negative-assertion grep. The `!` may have leading
# whitespace or follow a `&&`/`||`/`;`/`(`/`do`. We anchor on a `!` token
# followed (allowing whitespace) by a bare `rg` invocation.
neg_rg = re.compile(r"(?:^|[\s;&|(])!\s+(?:command\s+)?rg(?:\s|$)")

# `rg --pcre2` or `rg -P` — PCRE2 grep, the shape rewritten to BSD grep.
# Match a bare `rg` (word-bounded, not part of a path) followed anywhere on the
# line by the --pcre2 long flag or a -P short flag (flag order agnostic).
pcre2_rg = re.compile(
    r"(?:^|[\s;&|(!])rg\b.*(?:--pcre2\b|(?:^|\s)-[A-Za-z]*P[A-Za-z]*(?:\s|$|=))"
)

# `git apply` — patch application (comparison evidence). Allow `git` global
# options (e.g. --no-pager) between `git` and `apply`.
git_apply = re.compile(r"(?:^|[\s;&|(!])git\b[^|]*?\bapply\b")

# `git diff --no-index` — file comparison (false-identical shape). Flag order
# agnostic: --no-index may appear before or after the operands.
git_noindex = re.compile(r"(?:^|[\s;&|(!])git\b[^|]*?\bdiff\b.*--no-index\b")

# checksum comparison — cksum / sha*sum / shasum whose RAW STDOUT is the
# comparison evidence (`cksum a.txt b.txt`, two file operands printed for direct
# inspection). A proxy can flip the false-identical verdict here.
#
# NOT the evidence shape (so not flagged by `checksum_matches`):
#   - digest CAPTURE: `h="$(shasum file)"`, `$(sha256sum f | cut ...)` — the
#     script captures the digest and does its own string compare; the raw
#     stdout is not the verdict.
#   - single-operand digest: `shasum -a 256 file` (one file) — a digest print,
#     not a two-file comparison.
checksum_cmd = re.compile(
    r"(?:^|[\s;&|(!])(?:command\s+)?(?:cksum|sha1sum|sha256sum|shasum)\b"
)


def checksum_matches(line: str) -> bool:
    """Flag a checksum command only when its raw stdout is comparison evidence.

    Returns True when the line invokes cksum/sha*sum directly (not captured into
    a variable, not piped) over two or more file operands. Returns False for
    digest-capture / piped / single-operand forms, which are the script doing
    its own comparison rather than relying on the raw checksum verdict.
    """
    m = checksum_cmd.search(line)
    if not m:
        return False
    # Inside a command substitution `$(...)` or backticks => digest capture.
    head = line[: m.start()]
    if "$(" in head or "`" in head:
        return False
    # Tail after the command: stop at the first pipe / redirect / `)` / `;`.
    tail = line[m.end():]
    tail = re.split(r"[|&;<>`)]", tail, maxsplit=1)[0]
    # Count non-flag operand tokens; `-a 256` (flag + numeric arg) is skipped.
    tokens = tail.split()
    operands = []
    skip_next = False
    for tok in tokens:
        if skip_next:
            skip_next = False
            continue
        if tok in ("-a", "--algorithm"):
            skip_next = True
            continue
        if tok.startswith("-"):
            continue
        operands.append(tok)
    return len(operands) >= 2

# Regex-only patterns (label). The checksum case needs operand/context logic,
# so it is handled separately via checksum_matches().
PATTERNS = [
    (neg_rg, "! rg (negative-assertion grep)"),
    (pcre2_rg, "rg --pcre2 / -P (PCRE2 grep)"),
    (git_apply, "git apply (patch application)"),
    (git_noindex, "git diff --no-index (file comparison)"),
]
CHECKSUM_LABEL = "cksum / sha*sum (checksum comparison)"

comment_line = re.compile(r"^\s*#")

violations = []
for path in targets:
    real = os.path.realpath(path)
    if real in allowed:
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, 1):
                if comment_line.search(line):
                    continue
                if is_immune(line):
                    continue
                matched = False
                for pat, label in PATTERNS:
                    if pat.search(line):
                        violations.append((path, lineno, label))
                        matched = True
                        break
                if not matched and checksum_matches(line):
                    violations.append((path, lineno, CHECKSUM_LABEL))
    except OSError:
        continue

if violations:
    for path, lineno, label in violations:
        sys.stderr.write(
            f"POLARIS_EVIDENCE_DIRECT_CALL: {path}:{lineno} — {label}\n"
        )
    sys.stderr.write(
        f"\n{len(violations)} evidence-bearing command(s) run as a direct call: "
        "the stdout/exit code IS verification evidence but a transparent "
        "command-rewrite proxy can corrupt it (false PASS / false identical). "
        "Route through scripts/run-evidence-command.sh, or invoke via an "
        "absolute binary path. If the site genuinely needs a direct call, add a "
        "<path>:<reason> allowlist entry.\n"
    )
    sys.exit(2)

sys.exit(0)
PY
