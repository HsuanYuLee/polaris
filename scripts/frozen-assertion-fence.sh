#!/usr/bin/env bash
# Frozen assertion fence: seal producer and tamper detector.
#
# A frozen block is the region between `<!-- POLARIS-FROZEN-{K}-BEGIN -->` and
# `<!-- POLARIS-FROZEN-{K}-END -->` in a Markdown body. The seal lives in the
# document frontmatter (`assertions_hash` / `frozen_by` / `frozen_at`), so
# writing the seal never invalidates it: the hash covers the fence *inner*
# bytes only, marker lines excluded.
#
# Canonical hash recipe (byte-identical to the hand-signed 05-redesign.md seal):
#   sed -n '/BEGIN/,/END/p' <file> | sed '1d;$d' | shasum -a 256
#
# Subcommands:
#   blocks <file>                 list fence block keys in document order
#   hash <file> --block <K>       print the fence inner-content sha256
#   hash --file <path>            print the sha256 of a whole file
#   hash --stdin                  print the sha256 of stdin
#   verify <file> [--block <K>]   recompute and compare against the seal
#   seal <file> --by <who>        write the seal for every block
#
# `verify` fails closed: a missing seal, an unknown block, an unterminated
# fence, or a hash mismatch all exit 2 and demand a human re-signature.
# `seal` additionally refuses to sign when an assertion id inside the fence is
# not canonical `AC-<LETTERS><digits>` shape. That check runs at signing time
# only, so fences signed before the rule existed keep verifying.

set -uo pipefail

# Assertion ids are normalized once, at the moment a human signs. Downstream
# artifacts (refinement.json, task.md, verify-AC reports) can then quote the id
# verbatim instead of rewriting it.
CANONICAL_ASSERTION_ID_RE='^AC-[A-Z]+[0-9]+$'
# A bold lead token only counts as an assertion id when it looks like one; the
# fence also carries prose in bold, which must not be flagged.
CANDIDATE_ASSERTION_ID_RE='^[A-Za-z][A-Za-z0-9]*-[A-Za-z]*[0-9]+$'
ASSERTIONS_HASH_RECIPE="sed -n '/<!-- POLARIS-FROZEN-{K}-BEGIN -->/,/<!-- POLARIS-FROZEN-{K}-END -->/p' <file> | sed '1d;\$d' | shasum -a 256"

usage() {
  cat >&2 <<'EOF'
Usage:
  frozen-assertion-fence.sh blocks <file>
  frozen-assertion-fence.sh hash <file> --block <KEY>
  frozen-assertion-fence.sh hash --file <path>
  frozen-assertion-fence.sh hash --stdin
  frozen-assertion-fence.sh verify <file> [--block <KEY>]
  frozen-assertion-fence.sh seal <file> --by <signer> [--block <KEY>] [--at <iso8601>]
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
  # Description: fail-stop with a repair hint when the Polaris runtime is absent.
  if ! command -v python3 >/dev/null 2>&1; then
    echo "POLARIS_TOOL_MISSING:python3" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

sha256_stdin() {
  # Description: print the sha256 hex digest of stdin.
  # Side effects: none (reads stdin only).
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    echo "POLARIS_TOOL_MISSING:shasum" >&2
    echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
    exit 2
  fi
}

fence_inner() {
  # Description: print the fence inner bytes for one block (markers excluded).
  # Args: $1 = file, $2 = block key
  # Side effects: exits 2 when the block is missing or unterminated.
  local file="$1" key="$2"
  local begin="<!-- POLARIS-FROZEN-${key}-BEGIN -->"
  local end="<!-- POLARIS-FROZEN-${key}-END -->"

  grep -Fq "$begin" "$file" \
    || die "POLARIS_FROZEN_FENCE_BLOCK_MISSING" "block '$key' has no BEGIN marker in $file"
  grep -Fq "$end" "$file" \
    || die "POLARIS_FROZEN_FENCE_UNTERMINATED" "block '$key' has a BEGIN marker but no END marker in $file"

  awk -v begin="$begin" -v end="$end" '
    index($0, begin) { inside = 1; next }
    index($0, end)   { inside = 0; next }
    inside           { print }
  ' "$file"
}

list_blocks() {
  # Description: print fence block keys in document order, one per line.
  # Args: $1 = file
  sed -n 's/^.*<!-- POLARIS-FROZEN-\([A-Za-z0-9_-]*\)-BEGIN -->.*$/\1/p' "$1"
}

read_seal() {
  # Description: print "<block> <hash>" lines parsed from the frontmatter seal.
  # Args: $1 = file
  # Side effects: none; absent seal simply prints nothing.
  require_python3
  python3 - "$1" <<'PY'
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
if not lines or lines[0].strip() != "---":
    sys.exit(0)
try:
    end = lines.index("---", 1)
except ValueError:
    sys.exit(0)

front = lines[1:end]
for i, line in enumerate(front):
    if line.strip() != "assertions_hash:":
        continue
    for nested in front[i + 1:]:
        if not nested.startswith((" ", "\t")):
            break
        m = re.match(r"^\s+([A-Za-z0-9_-]+):\s*(\S+)\s*$", nested)
        if m:
            print(f"{m.group(1)} {m.group(2)}")
    break
PY
}

seal_hash_for() {
  # Description: print the sealed hash recorded for one block, or nothing.
  # Args: $1 = file, $2 = block key
  read_seal "$1" | awk -v k="$2" '$1 == k { print $2 }'
}

normalize_hash() {
  # Description: strip an optional `sha256:` prefix so comparisons are uniform.
  printf '%s\n' "${1#sha256:}"
}

cmd_blocks() {
  local file="${1:-}"
  [[ -n "$file" && -f "$file" ]] || die "POLARIS_FROZEN_FENCE_INPUT_UNREADABLE" "file not readable: ${file:-<missing>}"
  list_blocks "$file"
}

cmd_hash() {
  local file="" block="" mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --block) block="${2:-}"; shift 2 ;;
      --file) file="${2:-}"; mode="file"; shift 2 ;;
      --stdin) mode="stdin"; shift ;;
      -*) usage; exit 2 ;;
      *) file="$1"; shift ;;
    esac
  done

  if [[ "$mode" == "stdin" ]]; then
    sha256_stdin
    return 0
  fi

  [[ -n "$file" && -f "$file" ]] || die "POLARIS_FROZEN_FENCE_INPUT_UNREADABLE" "file not readable: ${file:-<missing>}"

  if [[ -n "$block" ]]; then
    fence_inner "$file" "$block" | sha256_stdin
  else
    sha256_stdin < "$file"
  fi
}

cmd_verify() {
  local file="" block=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --block) block="${2:-}"; shift 2 ;;
      -*) usage; exit 2 ;;
      *) file="$1"; shift ;;
    esac
  done

  [[ -n "$file" && -f "$file" ]] || die "POLARIS_FROZEN_FENCE_INPUT_UNREADABLE" "file not readable: ${file:-<missing>}"

  local keys
  if [[ -n "$block" ]]; then
    keys="$block"
  else
    keys="$(list_blocks "$file")"
  fi
  [[ -n "$keys" ]] || die "POLARIS_FROZEN_FENCE_NO_BLOCK" "no POLARIS-FROZEN fence found in $file"

  local key actual sealed
  while read -r key; do
    [[ -n "$key" ]] || continue
    actual="$(fence_inner "$file" "$key" | sha256_stdin)" || exit 2
    sealed="$(seal_hash_for "$file" "$key")"
    if [[ -z "$sealed" ]]; then
      die "POLARIS_FROZEN_FENCE_SEAL_MISSING" \
        "block '$key' has no assertions_hash entry in $file; a human must seal it before this fence can be trusted"
    fi
    sealed="$(normalize_hash "$sealed")"
    if [[ "$actual" != "$sealed" ]]; then
      die "POLARIS_FROZEN_FENCE_HASH_MISMATCH" \
        "block '$key' changed in $file (sealed sha256:$sealed, current sha256:$actual); a human must review and re-sign the fence"
    fi
    echo "PASS: frozen fence '$key' matches seal sha256:$sealed"
  done <<< "$keys"
}

assert_canonical_ids() {
  # Description: reject a seal attempt when any fence assertion id is non-canonical.
  # Args: $1 = file, $2.. = block keys
  # Side effects: exits 2 listing every violating id.
  local file="$1"
  shift
  local key violations=""
  for key in "$@"; do
    while read -r candidate; do
      [[ -n "$candidate" ]] || continue
      [[ "$candidate" =~ $CANDIDATE_ASSERTION_ID_RE ]] || continue
      [[ "$candidate" =~ $CANONICAL_ASSERTION_ID_RE ]] && continue
      violations+="  ${key}: ${candidate}"$'\n'
    done < <(fence_inner "$file" "$key" | sed -n 's/^[[:space:]]*[-*][[:space:]]*\*\*\([^ *]*\).*$/\1/p')
  done

  if [[ -n "$violations" ]]; then
    die "POLARIS_FROZEN_FENCE_ASSERTION_ID_NOT_CANONICAL" \
      "refusing to seal $file; assertion ids must match AC-<LETTERS><digits>:"$'\n'"${violations%$'\n'}"
  fi
}

cmd_seal() {
  local file="" signer="" at="" block=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --by) signer="${2:-}"; shift 2 ;;
      --at) at="${2:-}"; shift 2 ;;
      --block) block="${2:-}"; shift 2 ;;
      -*) usage; exit 2 ;;
      *) file="$1"; shift ;;
    esac
  done

  [[ -n "$file" && -f "$file" ]] || die "POLARIS_FROZEN_FENCE_INPUT_UNREADABLE" "file not readable: ${file:-<missing>}"
  [[ -n "$signer" ]] || die "POLARIS_FROZEN_FENCE_SIGNER_MISSING" "seal requires --by <signer>; only a human can freeze a fence"

  local keys
  if [[ -n "$block" ]]; then
    keys="$block"
  else
    keys="$(list_blocks "$file")"
  fi
  [[ -n "$keys" ]] || die "POLARIS_FROZEN_FENCE_NO_BLOCK" "no POLARIS-FROZEN fence found in $file"

  local key_array=()
  while read -r key; do
    [[ -n "$key" ]] || continue
    key_array+=("$key")
  done <<< "$keys"

  assert_canonical_ids "$file" "${key_array[@]}"

  # Pairs travel as argv, not stdin: the python program itself arrives on stdin
  # via heredoc, so a pipe here would be silently swallowed.
  local pairs=()
  for key in "${key_array[@]}"; do
    pairs+=("${key}:$(fence_inner "$file" "$key" | sha256_stdin)")
  done

  [[ -n "$at" ]] || at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  require_python3
  python3 - "$file" "$signer" "$at" "$ASSERTIONS_HASH_RECIPE" "${pairs[@]}" <<'PY'
import sys

path, signer, frozen_at, recipe = sys.argv[1:5]
pairs = [item.split(":", 1) for item in sys.argv[5:]]

text = open(path, encoding="utf-8").read()
lines = text.split("\n")
if not lines or lines[0].strip() != "---":
    print("POLARIS_FROZEN_FENCE_FRONTMATTER_MISSING", file=sys.stderr)
    print(f"{path} has no frontmatter to hold the seal", file=sys.stderr)
    sys.exit(2)
try:
    end = lines.index("---", 1)
except ValueError:
    print("POLARIS_FROZEN_FENCE_FRONTMATTER_MISSING", file=sys.stderr)
    print(f"{path} frontmatter is unterminated", file=sys.stderr)
    sys.exit(2)

front = lines[1:end]
body = lines[end:]

SEAL_KEYS = ("frozen_by:", "frozen_at:", "assertions_hash:", "assertions_hash_recipe:")

kept = []
skipping_nested = False
for line in front:
    if skipping_nested and line.startswith((" ", "\t")):
        continue
    skipping_nested = False
    stripped = line.lstrip()
    if any(stripped.startswith(k) for k in SEAL_KEYS):
        skipping_nested = stripped.startswith("assertions_hash:")
        continue
    kept.append(line)

seal = [f"frozen_by: {signer}", f"frozen_at: {frozen_at}", "assertions_hash:"]
seal += [f"  {key}: sha256:{digest}" for key, digest in pairs]
seal.append(f'assertions_hash_recipe: "{recipe}"')

open(path, "w", encoding="utf-8").write("\n".join(["---"] + kept + seal + body))
for key, digest in pairs:
    print(f"SEALED: {key} sha256:{digest}")
PY
}

main() {
  local sub="${1:-}"
  [[ -n "$sub" ]] || { usage; exit 2; }
  shift
  case "$sub" in
    blocks) cmd_blocks "$@" ;;
    hash) cmd_hash "$@" ;;
    verify) cmd_verify "$@" ;;
    seal) cmd_seal "$@" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
