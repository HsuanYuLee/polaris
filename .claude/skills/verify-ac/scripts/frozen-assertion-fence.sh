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
# fence, a duplicate assertion id, or a hash mismatch all exit 2 and demand a
# human re-signature. `seal` runs the same duplicate-id check before signing.
#
# There is deliberately no assertion id *format* rule. Nothing downstream reads
# the shape of an id — record-measurement-change.sh compares it as an opaque
# string — and no frozen assertion asks for one, so a format rule would be a
# convention the tool invented for itself. Uniqueness is different: the ledger
# looks entries up by id equality, so two assertions sharing an id would let an
# unsanctioned command match a sibling's sanctioned entry, defeating A-N2.

set -uo pipefail

# A bold lead token only counts as an assertion id when it looks like one; the
# fence also carries prose in bold, which must not be collected.
CANDIDATE_ASSERTION_ID_RE='^[A-Za-z][A-Za-z0-9]*-[A-Za-z]*[0-9]+$'
ASSERTIONS_HASH_RECIPE="sed -n '/<!-- POLARIS-FROZEN-{K}-BEGIN -->/,/<!-- POLARIS-FROZEN-{K}-END -->/p' <file> | sed '1d;\$d' | shasum -a 256"

usage() {
  cat >&2 <<'EOF'
Usage:
  frozen-assertion-fence.sh blocks <file>
  frozen-assertion-fence.sh hash <file> --block <KEY>
  frozen-assertion-fence.sh hash --file <path>
  frozen-assertion-fence.sh hash --stdin
  frozen-assertion-fence.sh verify <file> [--block <KEY>] [--against <git-ref>]
      (the fence is compared against git history by default; --against picks the ref)
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

rename_source_of() {
  # Description: the path a file used to have, when it arrived at its current one by rename.
  # Args: $1 = repo root, $2 = path relative to that root
  # Returns: the old path on stdout, or nothing when this is not a rename.
  #
  # 兩種都要看得到：已經 commit 的搬移，以及還躺在 index 裡的（歸檔器用 `git mv`，所以單
  # 剛收斂時就是這一種）。-M 讓 git 自己判定相似度，不用我們猜。
  #
  # 不可以用 pathspec 限定成新路徑：搬移是由「一邊消失、一邊出現」推出來的，只給 git 看
  # 出現的那一邊，它就只看得到一個新檔案，回空的。所以整份列出來，自己 filter。
  local repo="$1" path="$2" src
  src="$(git -C "$repo" diff --cached -M --name-status --diff-filter=R 2>/dev/null \
         | awk -F'\t' -v target="$path" '$3 == target { print $2; exit }')"
  [[ -n "$src" ]] && { printf '%s\n' "$src"; return 0; }
  git -C "$repo" log -1 --format= --diff-filter=R --find-renames --name-status 2>/dev/null \
    | awk -F'\t' -v target="$path" '$3 == target { print $2; exit }'
}

assert_unchanged_since() {
  # Description: fail closed when a fence differs from the same file at a git ref.
  # Args: $1 = file, $2 = git ref, $3.. = block keys
  # Side effects: exits 2 when history is unreachable or the fence moved.
  #
  # A seal only proves the fence and its frontmatter agree with each other. Any
  # writer that edits the fence and re-seals in the same breath produces a green
  # verify — including an agent, since `--by` is just a string. Git history is the
  # one record a writer inside the repo cannot rewrite in place, so this is what
  # actually gives A-N1 teeth: a changed fence has to surface as a reviewable diff.
  local file="$1" ref="$2"
  shift 2

  local repo_root rel blob key before after changed=""
  repo_root="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null)" \
    || die "POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE" \
      "$file is not inside a git repository; a fence with no history cannot be shown to be unchanged"

  rel="$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$file" "$repo_root")"

  if ! git -C "$repo_root" cat-file -e "${ref}:${rel}" 2>/dev/null; then
    if ! git -C "$repo_root" rev-parse --verify --quiet "$ref" >/dev/null; then
      die "POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE" \
        "cannot resolve ${ref} in ${repo_root}; refusing to claim the fence is unchanged"
    fi
    # 不在 ref 上有兩種原因，結論相反：真的是新的（沒得比），或者它只是換了位置。
    # 一張單收斂時歸檔器會把它搬走，那一刻「不在 HEAD 上」對每一張正在交付的單都成立——
    # 把兩種混為一談，等於在交付的那一刻讓凍結檢查變成一句空話，而那正是它最該說話的時候。
    local renamed_from
    renamed_from="$(rename_source_of "$repo_root" "$rel")"
    if [[ -n "$renamed_from" ]]; then
      # 全形標點緊接變數時一定要 ${}，否則 bash 會把標點吃進變數名。
      echo "MOVED: $rel 在 ${ref} 上叫 ${renamed_from}；比對的是它搬家前的內容"
      rel="$renamed_from"
    else
      # A new fence is signed, not compared.
      echo "NEW: $rel does not exist at ${ref}; nothing to compare against"
      return 0
    fi
  fi

  blob="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$blob'" RETURN
  git -C "$repo_root" show "${ref}:${rel}" > "$blob" \
    || die "POLARIS_FROZEN_FENCE_HISTORY_UNAVAILABLE" "could not read ${ref}:${rel}"

  for key in "$@"; do
    before="$(fence_inner "$blob" "$key" | sha256_stdin)"
    after="$(fence_inner "$file" "$key" | sha256_stdin)"
    [[ "$before" == "$after" ]] && continue
    changed+="  ${key}: ${ref} sha256:${before} -> current sha256:${after}"$'\n'
  done

  if [[ -n "$changed" ]]; then
    die "POLARIS_FROZEN_FENCE_CHANGED_SINCE_REF" \
      "fence content in $rel differs from ${ref}; re-sealing does not authorise this — the change must be reviewed as a diff:"$'\n'"${changed%$'\n'}"
  fi

  echo "PASS: fence content in $rel is unchanged since ${ref}"
}

cmd_verify() {
  # A fence is frozen by being committed, not by carrying a seal. The seal only
  # proves the fence and its frontmatter agree; git history is what makes a change
  # surface as a reviewable diff. So the comparison is the default, not an opt-in,
  # and there is deliberately no flag to turn it off.
  local file="" block="" against="HEAD"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --block) block="${2:-}"; shift 2 ;;
      --against) against="${2:-}"; shift 2 ;;
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

  local key verify_key_array=()
  while read -r key; do
    [[ -n "$key" ]] || continue
    verify_key_array+=("$key")
  done <<< "$keys"
  assert_unique_ids verify "$file" "${verify_key_array[@]}"

  local actual sealed
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

  # Last, and unconditional: the seal only proves internal agreement, so the
  # fence must also match what git already holds. Freezing is committing.
  assert_unchanged_since "$file" "$against" "${verify_key_array[@]}"
}

assert_unique_ids() {
  # Description: reject a fence whose assertion ids collide across the file.
  # Args: $1 = verb shown in the error ("seal" / "verify"), $2 = file, $3.. = block keys
  # Side effects: exits 2 listing every duplicated id.
  local verb="$1" file="$2"
  shift 2
  local key seen="" duplicates=""
  for key in "$@"; do
    while read -r candidate; do
      [[ -n "$candidate" ]] || continue
      [[ "$candidate" =~ $CANDIDATE_ASSERTION_ID_RE ]] || continue
      if printf '%s' "$seen" | grep -qxF "$candidate"; then
        printf '%s' "$duplicates" | grep -qxF "$candidate" || duplicates+="  ${candidate}"$'\n'
      else
        seen+="${candidate}"$'\n'
      fi
    done < <(fence_inner "$file" "$key" | sed -n 's/^[[:space:]]*[-*][[:space:]]*\*\*\([^ *]*\).*$/\1/p')
  done

  if [[ -n "$duplicates" ]]; then
    die "POLARIS_FROZEN_FENCE_ASSERTION_ID_DUPLICATE" \
      "refusing to ${verb} ${file}; the measurement ledger looks entries up by id equality, so these must be unique:"$'\n'"${duplicates%$'\n'}"
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

  # `--block` 只動一格，不帶就是重算全部。這個分別要傳給下面寫 frontmatter 的那一段：
  # 只有「重算全部」才有資格把這次沒算到的 key 清掉。
  local keys scope
  if [[ -n "$block" ]]; then
    keys="$block"
    scope="block"
  else
    keys="$(list_blocks "$file")"
    scope="all"
  fi
  [[ -n "$keys" ]] || die "POLARIS_FROZEN_FENCE_NO_BLOCK" "no POLARIS-FROZEN fence found in $file"

  local key_array=()
  while read -r key; do
    [[ -n "$key" ]] || continue
    key_array+=("$key")
  done <<< "$keys"

  assert_unique_ids seal "$file" "${key_array[@]}"

  # Pairs travel as argv, not stdin: the python program itself arrives on stdin
  # via heredoc, so a pipe here would be silently swallowed.
  local pairs=()
  for key in "${key_array[@]}"; do
    pairs+=("${key}:$(fence_inner "$file" "$key" | sha256_stdin)")
  done

  [[ -n "$at" ]] || at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  require_python3
  python3 - "$file" "$signer" "$at" "$ASSERTIONS_HASH_RECIPE" "$scope" "${pairs[@]}" <<'PY'
import sys

path, signer, frozen_at, recipe, scope = sys.argv[1:6]
pairs = [item.split(":", 1) for item in sys.argv[6:]]

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

# 既有的 map 要先讀出來再寫回去。`--block K` 只重算 K，而 seal 過去是把整段
# assertions_hash 丟掉、用本次的 pairs 重建——於是其他區塊的封條被靜靜刪掉，而 seal
# 回的是綠的（DP-548，2026-08-17 在一張三區塊的單上真的發生過）。
existing: "dict[str, str]" = {}
kept = []
skipping_nested = False
for line in front:
    if skipping_nested and line.startswith((" ", "\t")):
        entry = line.strip()
        if ":" in entry:
            key, value = entry.split(":", 1)
            existing[key.strip()] = value.strip()
        continue
    skipping_nested = False
    stripped = line.lstrip()
    if any(stripped.startswith(k) for k in SEAL_KEYS):
        skipping_nested = stripped.startswith("assertions_hash:")
        continue
    kept.append(line)

merged = dict(existing)
merged.update({key: f"sha256:{digest}" for key, digest in pairs})

# 整份 seal 是重算全部，所以這一次沒算到的 key 就是 fence 已經不在檔案裡的——留著會讓
# verify 去驗一個不存在的東西。`--block` 只動一格，不做這件事。
if scope == "all":
    merged = {key: merged[key] for key, _ in pairs}

seal = [f"frozen_by: {signer}", f"frozen_at: {frozen_at}", "assertions_hash:"]
seal += [f"  {key}: {value}" for key, value in merged.items()]
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
