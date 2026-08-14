#!/usr/bin/env bash
set -euo pipefail

# compile-runtime-instructions.sh
#
# 把 .claude/instructions/ 底下的片段接成各 runtime 讀的那份常駐指令。
# 來源是 manifest.yaml 的 includes；這支腳本不自己生內容——內容寫死在編譯器裡的話，
# 那些宣稱是來源的檔案就只是裝飾，改了不會生效。
#
# Usage:
#   bash .claude/instructions/compile.sh [--target {claude|agents|codex|copilot|all}]
#   bash .claude/instructions/compile.sh --check

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 顯式的 GIT_DIR 蓋過 `-C`：git hook 執行期間 git 會設它，於是 `--show-toplevel` 改拿 cwd
# 當工作區，這裡解出來的是 SCRIPT_DIR 自己，每一個 include 都變成「找不到」。清掉再解。
ROOT_DIR="$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MANIFEST="$SCRIPT_DIR/manifest.yaml"
CHECK_ONLY=false
TARGET="all"

usage() {
  sed -n '4,12p' "$0" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --target) [[ $# -ge 2 ]] || usage; TARGET="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

case "$TARGET" in
  claude|agents|codex|copilot|all) ;;
  *) echo "Invalid target: $TARGET" >&2; exit 2 ;;
esac

[[ -f "$MANIFEST" ]] || { echo "Missing manifest: $MANIFEST" >&2; exit 1; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "POLARIS_TOOL_MISSING:python3" >&2
  echo "Repair: run mise install, then mise run doctor -- --profile runtime" >&2
  exit 2
fi

# Description: 讀 manifest，對每個目標印一行 "<名稱>\t<輸出路徑>\t<include,include>"。
# Outputs: tab 分隔的三欄，每個目標一行。
read_manifest() {
  python3 - "$MANIFEST" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
block = text.split("targets:", 1)[1].split("\nscope_policy:", 1)[0]
name = path = None
includes = []
def flush():
    if name and path:
        print(f"{name}\t{path}\t{','.join(includes)}")
for line in block.splitlines():
    if re.match(r"^  [\w-]+:\s*$", line):
        flush()
        name, path, includes = line.strip().rstrip(":"), None, []
    elif m := re.match(r'^    path:\s*"?([^"]+?)"?\s*$', line):
        path = m.group(1)
    elif m := re.match(r'^      - "?([^"]+?)"?\s*$', line):
        includes.append(m.group(1))
flush()
PY
}

# Description: 把一個目標的完整內容印到 stdout。
# Args: $1 = 目標名, $2 = 逗號分隔的 include 清單
render() {
  local name="$1" includes="$2" inc
  cat <<EOF
<!-- 由 .claude/instructions/compile.sh 產生，不要直接改這個檔。 -->
<!-- 來源：.claude/instructions/manifest.yaml 的目標 $name -->
<!-- 重新產生：bash .claude/instructions/compile.sh --target $name -->
<!-- 檢查有沒有過期：bash .claude/instructions/compile.sh --check -->

# Polaris
EOF
  local IFS=,
  for inc in $includes; do
    [[ -f "$ROOT_DIR/$inc" ]] || { echo "Missing include: $inc (target $name)" >&2; return 1; }
    echo
    cat "$ROOT_DIR/$inc"
  done
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

status=0
while IFS=$'\t' read -r name path includes; do
  [[ "$TARGET" == "all" || "$TARGET" == "$name" ]] || continue
  out="$tmpdir/$name.out"
  render "$name" "$includes" > "$out" || { status=1; continue; }
  full="$ROOT_DIR/$path"
  if [[ "$CHECK_ONLY" == true ]]; then
    if [[ ! -f "$full" ]]; then
      echo "DRIFT: missing $path" >&2; status=1
    elif ! command diff -q "$out" "$full" >/dev/null 2>&1; then
      echo "DRIFT: $path is out of date." >&2
      command diff -u "$full" "$out" | head -40 >&2
      status=1
    fi
  else
    mkdir -p "$(dirname "$full")"
    cp "$out" "$full"
    echo "Generated: $path"
  fi
done < <(read_manifest)

if [[ "$CHECK_ONLY" == true && "$status" -eq 0 ]]; then
  echo "OK: runtime instruction targets are in sync."
fi
exit "$status"
