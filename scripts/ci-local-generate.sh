#!/usr/bin/env bash
# ci-local-generate.sh — Generate {repo}/scripts/ci-local.sh from repo CI declarations.
#
# DP-032 D12. Tool-agnostic: parses .woodpecker/, .github/workflows/, .gitlab-ci.yml,
# .husky/, .pre-commit-config.yaml, and package.json scripts via the existing
# ci-contract-discover.sh, then emits a self-contained per-repo mirror script.
#
# The generated script:
#   - Reads HEAD SHA + branch, derives /tmp/polaris-ci-local-{branch}-{head_sha}.json
#   - Cache hit (same head_sha + status PASS) → exit 0 immediately
#   - Otherwise runs each parsed install/lint/typecheck/test/coverage command in order
#   - When codecov.yml is present, runs patch-coverage compute + empty-coverage safety net
#   - Writes evidence JSON and exits 0 (PASS) or 1 (FAIL)
#
# Usage:
#   scripts/ci-local-generate.sh --repo <path> [--out <path>] [--force] [--dry-run]
#
#   --repo     target repo root (must be a git checkout)
#   --out      output path (default: {repo}/scripts/ci-local.sh)
#   --force    overwrite existing output
#   --dry-run  print rendered script to stdout, write nothing

set -euo pipefail

REPO_DIR=""
OUT_PATH=""
FORCE=0
DRY_RUN=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="$2"; shift 2 ;;
    --out) OUT_PATH="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '1,/^set -euo pipefail$/p' "$0" | sed -e 's/^# \{0,1\}//' -e '/^!\/usr/d' -e '/^set -euo/d'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$REPO_DIR" ]]; then
  echo "Usage: ci-local-generate.sh --repo <path> [--out <path>] [--force] [--dry-run]" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"
[[ -z "$OUT_PATH" ]] && OUT_PATH="$REPO_DIR/scripts/ci-local.sh"

DISCOVER="$SCRIPT_DIR/ci-contract-discover.sh"
if [[ ! -x "$DISCOVER" ]]; then
  echo "[ci-local-generate] ERROR: ci-contract-discover.sh not found or not executable at $DISCOVER" >&2
  exit 1
fi

CONTRACT_FILE=$(mktemp)
trap 'rm -f "$CONTRACT_FILE"' EXIT
"$DISCOVER" --repo "$REPO_DIR" > "$CONTRACT_FILE"

GENERATOR_HASH="$(shasum -a 256 "$0" | cut -c1-12)"

python3 - "$REPO_DIR" "$OUT_PATH" "$FORCE" "$DRY_RUN" "$CONTRACT_FILE" "$GENERATOR_HASH" <<'PY'
import datetime
import hashlib
import json
import os
import re
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2])
force = sys.argv[3] == "1"
dry_run = sys.argv[4] == "1"
contract_file = sys.argv[5]
generator_hash = sys.argv[6]

contract = json.loads(Path(contract_file).read_text(encoding="utf-8"))

# ---------- Filtering ----------
ALLOWED_CATEGORIES = {"install", "lint", "typecheck", "test", "coverage"}
CI_ENV_VAR_RE = re.compile(r"\$(?:\{)?CI_[A-Z_]+")


def has_ci_env_dep(cmd: str) -> bool:
    return bool(CI_ENV_VAR_RE.search(cmd))


def is_pure_control_flow_fragment(cmd: str) -> bool:
    """Multi-line YAML often splits if/for blocks across entries.
    Skip fragments that are clearly not standalone executable lines."""
    stripped = cmd.strip()
    if stripped in ("fi", "done", "else", "esac"):
        return True
    # Bare 'if [ ... ]; then' without body is a fragment
    if re.match(r"^if\s+\[.*\];\s*then\s*$", stripped):
        return True
    return False


def filter_checks(checks):
    """Pick install/lint/typecheck/test/coverage checks that are runnable locally."""
    keep = []
    seen_cmds = set()
    install_cmd = None  # Prefer --frozen-lockfile install
    for c in checks:
        if c.get("category") not in ALLOWED_CATEGORIES:
            continue
        if not c.get("local_executable"):
            continue
        cmd = (c.get("command") or "").strip()
        if not cmd:
            continue
        if has_ci_env_dep(cmd):
            continue
        if is_pure_control_flow_fragment(cmd):
            continue
        # De-dupe by exact command string
        if cmd in seen_cmds:
            continue
        # Special handling for install: prefer --frozen-lockfile, then plain, then --no-frozen
        if c.get("category") == "install":
            if install_cmd is None:
                install_cmd = (cmd, c)
            else:
                prev_cmd, _ = install_cmd
                rank = lambda s: (
                    0 if "--frozen-lockfile" in s else
                    2 if "--no-frozen-lockfile" in s else
                    1
                )
                if rank(cmd) < rank(prev_cmd):
                    install_cmd = (cmd, c)
            continue
        seen_cmds.add(cmd)
        keep.append(c)
    if install_cmd is not None:
        seen_cmds.add(install_cmd[0])
        # Install runs first
        keep.insert(0, install_cmd[1])
    return keep


def filter_dev_hooks(dev_hooks):
    """Include pre-commit shell hooks; skip lint-staged-config marker rows."""
    keep = []
    seen = set()
    for h in dev_hooks or []:
        ht = (h.get("hook_type") or "").lower()
        if ht not in ("pre-commit", "pre-push"):
            continue
        if not h.get("local_executable"):
            continue
        cmd = (h.get("command") or "").strip()
        if not cmd:
            continue
        if has_ci_env_dep(cmd):
            continue
        if cmd in seen:
            continue
        seen.add(cmd)
        keep.append(h)
    return keep


checks = filter_checks(contract.get("checks", []))
dev_hooks = filter_dev_hooks(contract.get("dev_hooks", []))
codecov_gates = contract.get("codecov_flag_gates", []) or []
provider = contract.get("provider", "unknown")

has_anything = bool(checks) or bool(dev_hooks) or bool(codecov_gates)

# ---------- Source fingerprints (for staleness advisory) ----------
def file_fingerprint(rel_path: str):
    p = repo / rel_path
    try:
        st = p.stat()
        return {"path": rel_path, "size": st.st_size, "mtime": int(st.st_mtime)}
    except FileNotFoundError:
        return {"path": rel_path, "size": None, "mtime": None}


sources = []
for f in contract.get("files", []):
    sources.append(file_fingerprint(f))
# Codecov sources
for name in ("codecov.yml", ".codecov.yml"):
    if (repo / name).exists():
        sources.append(file_fingerprint(name))
# Husky / pre-commit sources
husky_root = repo / ".husky"
if husky_root.is_dir():
    for hp in sorted(husky_root.iterdir()):
        if hp.is_file():
            sources.append(file_fingerprint(str(hp.relative_to(repo))))
for n in (".pre-commit-config.yaml", ".pre-commit-hooks.yaml"):
    if (repo / n).exists():
        sources.append(file_fingerprint(n))

generated_at = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# ---------- Render ci-local.sh ----------
def shell_quote(s: str) -> str:
    """Single-quote escape a string for safe shell embedding."""
    return "'" + s.replace("'", "'\"'\"'") + "'"


def heredoc_block(label: str, body: str) -> str:
    """Produce a single-quoted heredoc with a unique sentinel.
    Used for embedding multi-line commands without escape hell."""
    sentinel = label
    # Bump sentinel until it doesn't appear in body as a standalone line
    counter = 0
    while True:
        candidate = f"{sentinel}_{counter:03d}"
        if not re.search(rf"^{re.escape(candidate)}$", body, re.MULTILINE):
            sentinel = candidate
            break
        counter += 1
    return f"<<'{sentinel}'\n{body}\n{sentinel}"


parts = []
parts.append("#!/usr/bin/env bash")
parts.append("# ci-local.sh — Tool-agnostic local mirror of repo CI checks (DP-032 D12).")
parts.append(f"# Generated by Polaris/scripts/ci-local-generate.sh on {generated_at}.")
parts.append(f"# Generator hash: {generator_hash}")
parts.append(f"# CI provider: {provider}")
parts.append("# Source CI declarations (regenerate when these change):")
for s in sources:
    if s["mtime"] is not None:
        ts = datetime.datetime.fromtimestamp(s["mtime"], datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        parts.append(f"#   {s['path']} ({s['size']} bytes, mtime {ts})")
    else:
        parts.append(f"#   {s['path']} (missing)")
parts.append("#")
parts.append("# DO NOT EDIT MANUALLY — regenerate via:")
parts.append("#   {polaris}/scripts/ci-local-generate.sh --repo $(pwd) --force")
parts.append("")
parts.append("set -uo pipefail")
parts.append("")
parts.append('# Locate repo root (this script lives in <repo>/scripts/)')
parts.append('SCRIPT_DIR_REAL="$(cd "$(dirname "$0")" && pwd)"')
parts.append('REPO_ROOT="$(cd "$SCRIPT_DIR_REAL/.." && pwd)"')
parts.append('cd "$REPO_ROOT"')
parts.append("")
parts.append('HEAD_SHA="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"')
parts.append('BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"')
parts.append('BRANCH_SLUG="$(printf "%s" "$BRANCH" | tr "/" "-")"')
parts.append('EVIDENCE_PATH="/tmp/polaris-ci-local-${BRANCH_SLUG}-${HEAD_SHA}.json"')
parts.append("")
parts.append('# --- Cache check: same head_sha + PASS evidence → exit 0 (no rerun)')
parts.append('if [ -f "$EVIDENCE_PATH" ]; then')
parts.append('  CACHED_STATUS="$(python3 -c "import json,sys')
parts.append('try: print(json.load(open(sys.argv[1])).get(\\"status\\", \\"\\"))')
parts.append('except: print(\\"\\")" "$EVIDENCE_PATH" 2>/dev/null)"')
parts.append('  if [ "$CACHED_STATUS" = "PASS" ]; then')
parts.append('    echo "[ci-local] cache hit: $EVIDENCE_PATH (head_sha=$HEAD_SHA, status=PASS)"')
parts.append('    exit 0')
parts.append('  fi')
parts.append('fi')
parts.append("")
parts.append('# --- Staleness advisory (does not block): warn if any source CI config is newer than this script')
parts.append('SCRIPT_MTIME=$(stat -f %m "$0" 2>/dev/null || stat -c %Y "$0" 2>/dev/null || echo 0)')
parts.append('STALE_FILES=""')
for s in sources:
    if s["mtime"] is None:
        continue
    parts.append(f'_src_mtime=$(stat -f %m "{s["path"]}" 2>/dev/null || stat -c %Y "{s["path"]}" 2>/dev/null || echo 0)')
    parts.append(f'if [ "$_src_mtime" -gt "$SCRIPT_MTIME" ]; then STALE_FILES="$STALE_FILES {s["path"]}"; fi')
parts.append('if [ -n "$STALE_FILES" ]; then')
parts.append('  echo "[ci-local] WARN: CI config newer than this script — consider regenerating:$STALE_FILES" >&2')
parts.append('fi')
parts.append("")

if not has_anything:
    # NO_CHECKS_CONFIGURED branch
    parts.append('# --- NO_CHECKS_CONFIGURED: this repo has no CI declarations to mirror')
    parts.append('echo "[ci-local] NO_CHECKS_CONFIGURED — repo has no parseable CI declarations"')
    parts.append('python3 - "$EVIDENCE_PATH" "$BRANCH" "$HEAD_SHA" <<\'CILOCAL_NCC_PY\'')
    parts.append('import json, sys, datetime')
    parts.append('path, branch, sha = sys.argv[1], sys.argv[2], sys.argv[3]')
    parts.append('with open(path, "w") as f:')
    parts.append('    json.dump({')
    parts.append('        "branch": branch, "head_sha": sha,')
    parts.append('        "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),')
    parts.append('        "status": "PASS",')
    parts.append('        "writer": "ci-local.sh",')
    parts.append('        "checks": [],')
    parts.append('        "reason": "NO_CHECKS_CONFIGURED",')
    parts.append('    }, f, indent=2)')
    parts.append('CILOCAL_NCC_PY')
    parts.append('echo "[ci-local] evidence written: $EVIDENCE_PATH"')
    parts.append('exit 0')
else:
    parts.append('RESULTS_TMP=$(mktemp)')
    parts.append('CMD_OUT_DIR=$(mktemp -d)')
    parts.append('trap \'rm -rf "$RESULTS_TMP" "$CMD_OUT_DIR"\' EXIT')
    parts.append('FAILED=0')
    parts.append("")
    parts.append('run_check() {')
    parts.append('  local idx="$1" category="$2" job="$3" source_file="$4" cmd_file="$5"')
    parts.append('  local cmd_preview')
    parts.append('  cmd_preview="$(head -1 "$cmd_file")"')
    parts.append('  echo "[ci-local] [$category] $source_file::$job"')
    parts.append('  echo "  > $cmd_preview"')
    parts.append('  local out_file="$CMD_OUT_DIR/${idx}.out"')
    parts.append('  local rc=0')
    parts.append('  bash -lc "$(cat "$cmd_file")" >"$out_file" 2>&1 || rc=$?')
    parts.append('  python3 - "$RESULTS_TMP" "$idx" "$category" "$job" "$source_file" "$cmd_file" "$out_file" "$rc" <<\'CILOCAL_RC_PY\'')
    parts.append('import json, sys, os')
    parts.append('results_path, idx, category, job, source_file, cmd_file, out_file, rc = sys.argv[1:9]')
    parts.append('rc = int(rc)')
    parts.append('cmd = open(cmd_file).read().rstrip()')
    parts.append('try:')
    parts.append('    output = open(out_file).read()')
    parts.append('except Exception:')
    parts.append('    output = ""')
    parts.append('lines = output.strip().splitlines()')
    parts.append('tail = "\\n".join(lines[-40:])')
    parts.append('entry = {')
    parts.append('    "idx": int(idx),')
    parts.append('    "category": category,')
    parts.append('    "job": job,')
    parts.append('    "source_file": source_file,')
    parts.append('    "command": cmd,')
    parts.append('    "exit_code": rc,')
    parts.append('    "status": "PASS" if rc == 0 else "FAIL",')
    parts.append('    "output_tail": tail,')
    parts.append('}')
    parts.append('with open(results_path, "a") as f:')
    parts.append('    f.write(json.dumps(entry) + "\\n")')
    parts.append('CILOCAL_RC_PY')
    parts.append('  if [ $rc -ne 0 ]; then')
    parts.append('    if [ "$category" = "install" ]; then')
    parts.append('      echo "  ✗ install FAIL (exit $rc) — aborting (downstream checks meaningless)" >&2')
    parts.append('      tail -40 "$out_file" >&2 || true')
    parts.append('      FAILED=1')
    parts.append('      return 1')
    parts.append('    else')
    parts.append('      echo "  ✗ FAIL (exit $rc)"')
    parts.append('      tail -20 "$out_file" || true')
    parts.append('      FAILED=1')
    parts.append('    fi')
    parts.append('  else')
    parts.append('    echo "  ✓ PASS"')
    parts.append('  fi')
    parts.append('}')
    parts.append("")
    # Emit numbered command files
    idx = 0
    all_runs = []
    for c in checks:
        idx += 1
        cat = c.get("category", "other")
        job = c.get("job", "")
        src = c.get("source_file", "")
        cmd_body = c.get("command", "").rstrip("\n")
        parts.append(f"# Check {idx}: [{cat}] {src}::{job}")
        parts.append(f'cat > "$CMD_OUT_DIR/{idx}.cmd" {heredoc_block("CILOCAL_CMD", cmd_body)}')
        all_runs.append((idx, cat, job, src))
    for h in dev_hooks:
        idx += 1
        cat = h.get("category", "other")
        ht = h.get("hook_type", "pre-commit")
        src = h.get("source_file", "")
        cmd_body = h.get("command", "").rstrip("\n")
        parts.append(f"# Dev hook {idx}: [{cat}] {src}::{ht}")
        parts.append(f'cat > "$CMD_OUT_DIR/{idx}.cmd" {heredoc_block("CILOCAL_HOOK", cmd_body)}')
        all_runs.append((idx, cat, ht, src))
    parts.append("")
    for idx_, cat, job, src in all_runs:
        parts.append(
            f'run_check {idx_} {shell_quote(cat)} {shell_quote(job)} {shell_quote(src)} "$CMD_OUT_DIR/{idx_}.cmd" || true'
        )
    parts.append("")

    # ---------- Codecov post-check ----------
    if codecov_gates:
        gates_json = json.dumps(codecov_gates, ensure_ascii=False)
        parts.append('# --- Codecov patch coverage compute + empty-coverage safety net')
        parts.append('python3 - "$RESULTS_TMP" "$REPO_ROOT" <<\'CILOCAL_COV_PY\'')
        parts.append('import json, os, re, subprocess, sys')
        parts.append('from fnmatch import fnmatch')
        parts.append('from pathlib import Path')
        parts.append('results_path = sys.argv[1]')
        parts.append('repo = Path(sys.argv[2]).resolve()')
        parts.append(f'gates = json.loads({json.dumps(gates_json)})')
        parts.append('')
        parts.append('def git(args):')
        parts.append('    proc = subprocess.run(["git", *args], cwd=str(repo),')
        parts.append('                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)')
        parts.append('    return proc.stdout.strip() if proc.returncode == 0 else ""')
        parts.append('')
        parts.append('def resolve_base():')
        parts.append('    for cand in ("develop", "main", "master"):')
        parts.append('        if git(["rev-parse", f"origin/{cand}"]):')
        parts.append('            return cand')
        parts.append('    return "main"')
        parts.append('')
        parts.append('def parse_changed_lines(diff_text):')
        parts.append('    file_lines = {}')
        parts.append('    current_file = None')
        parts.append('    for line in diff_text.splitlines():')
        parts.append('        if line.startswith("+++ b/"):')
        parts.append('            current_file = line[6:]')
        parts.append('            file_lines.setdefault(current_file, set())')
        parts.append('            continue')
        parts.append('        if line.startswith("@@") and current_file:')
        parts.append('            m = re.search(r"\\+(\\d+)(?:,(\\d+))?", line)')
        parts.append('            if not m: continue')
        parts.append('            start = int(m.group(1))')
        parts.append('            length = int(m.group(2) or "1")')
        parts.append('            if length == 0: continue')
        parts.append('            for n in range(start, start + length):')
        parts.append('                file_lines[current_file].add(n)')
        parts.append('    return file_lines')
        parts.append('')
        parts.append('def merge(*maps):')
        parts.append('    out = {}')
        parts.append('    for m in maps:')
        parts.append('        for f, lines in m.items():')
        parts.append('            out.setdefault(f, set()).update(lines)')
        parts.append('    return out')
        parts.append('')
        parts.append('base = resolve_base()')
        parts.append('mb = git(["merge-base", "HEAD", f"origin/{base}"]) or git(["merge-base", "HEAD", base])')
        parts.append('branch_diff = git(["diff", "-U0", "--no-color", f"{mb}...HEAD"]) if mb else ""')
        parts.append('working_diff = git(["diff", "-U0", "--no-color"])')
        parts.append('staged_diff = git(["diff", "-U0", "--no-color", "--cached"])')
        parts.append('changed = merge(parse_changed_lines(branch_diff),')
        parts.append('                parse_changed_lines(working_diff),')
        parts.append('                parse_changed_lines(staged_diff))')
        parts.append('')
        parts.append('def parse_lcov(root):')
        parts.append('    data = {}')
        parts.append('    for lcov in root.rglob("lcov.info"):')
        parts.append('        try: text = lcov.read_text(encoding="utf-8", errors="ignore")')
        parts.append('        except Exception: continue')
        parts.append('        cur = None')
        parts.append('        for ln in text.splitlines():')
        parts.append('            if ln.startswith("SF:"):')
        parts.append('                sf = ln[3:].strip()')
        parts.append('                p = Path(sf)')
        parts.append('                if p.is_absolute():')
        parts.append('                    try: cur = p.resolve().relative_to(root.resolve()).as_posix()')
        parts.append('                    except Exception: cur = p.as_posix()')
        parts.append('                else: cur = p.as_posix()')
        parts.append('                data.setdefault(cur, {})')
        parts.append('            elif ln.startswith("DA:") and cur:')
        parts.append('                try:')
        parts.append('                    n_s, h_s = ln[3:].split(",", 1)')
        parts.append('                    data[cur][int(n_s)] = int(float(h_s))')
        parts.append('                except Exception: pass')
        parts.append('    return data')
        parts.append('')
        parts.append('lcov_map = parse_lcov(repo)')
        parts.append('')
        parts.append('def normalize(p):')
        parts.append('    p = p.strip()')
        parts.append('    return p + "**" if p.endswith("/") else p')
        parts.append('')
        parts.append('def matches(path, includes, excludes):')
        parts.append('    inc = [normalize(p) for p in includes or []]')
        parts.append('    exc = [normalize(p) for p in excludes or []]')
        parts.append('    if inc and not any(fnmatch(path, pat) for pat in inc): return False')
        parts.append('    if any(fnmatch(path, pat) for pat in exc): return False')
        parts.append('    return True')
        parts.append('')
        parts.append('def compute(include, exclude):')
        parts.append('    matched = [f for f in changed.keys() if matches(f, include, exclude)]')
        parts.append('    total = covered = 0')
        parts.append('    prefixes = [p.rstrip("/") for p in (include or []) if p and "*" not in p]')
        parts.append('    for f in matched:')
        parts.append('        lines = changed.get(f, set())')
        parts.append('        lcov_lines = lcov_map.get(f)')
        parts.append('        if lcov_lines is None:')
        parts.append('            for pre in prefixes:')
        parts.append('                if f.startswith(pre + "/"):')
        parts.append('                    stripped = f[len(pre)+1:]')
        parts.append('                    lcov_lines = lcov_map.get(stripped)')
        parts.append('                    if lcov_lines is not None: break')
        parts.append('        if lcov_lines is None:')
        parts.append('            for k, v in lcov_map.items():')
        parts.append('                if k.endswith(f) or f.endswith(k):')
        parts.append('                    lcov_lines = v; break')
        parts.append('        if not lcov_lines: continue')
        parts.append('        for ln in lines:')
        parts.append('            if ln not in lcov_lines: continue')
        parts.append('            total += 1')
        parts.append('            if lcov_lines[ln] > 0: covered += 1')
        parts.append('    return matched, covered, total')
        parts.append('')
        parts.append('flag_results = []')
        parts.append('for gate in gates:')
        parts.append('    flag = gate.get("flag")')
        parts.append('    matched, covered, total = compute(gate.get("include_paths", []), gate.get("exclude_paths", []))')
        parts.append('    pct = round((covered/total)*100, 2) if total > 0 else None')
        parts.append('    statuses = gate.get("statuses") or []')
        parts.append('    if not statuses:')
        parts.append('        flag_results.append({"flag": flag, "status": "SKIP",')
        parts.append('            "reason": "flag_has_no_statuses", "covered_lines": covered,')
        parts.append('            "total_lines": total, "coverage_percent": pct,')
        parts.append('            "matched_files": matched})')
        parts.append('        continue')
        parts.append('    for s in statuses:')
        parts.append('        st = s.get("type"); tgt = s.get("target_percent"); thr = s.get("threshold_percent")')
        parts.append('        is_auto = bool(s.get("is_auto"))')
        parts.append('        eff = (float(tgt) - float(thr or 0)) if tgt is not None else None')
        parts.append('        entry = {"flag": flag, "status_type": st, "target_percent": tgt,')
        parts.append('                 "threshold_percent": thr, "effective_target_percent": eff,')
        parts.append('                 "is_auto": is_auto, "covered_lines": covered, "total_lines": total,')
        parts.append('                 "coverage_percent": pct, "matched_files": matched}')
        parts.append('        if st == "project":')
        parts.append('            entry["status"] = "SKIP"; entry["reason"] = "project_gate_not_implemented"')
        parts.append('        elif st == "patch" and is_auto:')
        parts.append('            entry["status"] = "SKIP"; entry["reason"] = "patch_auto_target_not_supported_locally"')
        parts.append('        elif st != "patch":')
        parts.append('            entry["status"] = "SKIP"; entry["reason"] = f"unknown_status_type_{st}"')
        parts.append('        elif total == 0:')
        parts.append('            entry["status"] = "SKIP"; entry["reason"] = "no_instrumented_patch_lines"')
        parts.append('        elif eff is None:')
        parts.append('            entry["status"] = "SKIP"; entry["reason"] = "patch_target_missing"')
        parts.append('        else:')
        parts.append('            entry["status"] = "PASS" if (pct is not None and pct >= eff) else "FAIL"')
        parts.append('            entry["reason"] = None')
        parts.append('        flag_results.append(entry)')
        parts.append('')
        parts.append('# Empty-coverage safety net (D13 invariant)')
        parts.append('explicit = [g for g in flag_results if g.get("status_type")=="patch"')
        parts.append('            and g.get("target_percent") is not None and not g.get("is_auto")]')
        parts.append('if explicit:')
        parts.append('    all_skip_no_lines = all(g.get("status")=="SKIP" and')
        parts.append('                            g.get("reason")=="no_instrumented_patch_lines" for g in explicit)')
        parts.append('    has_matched = any(len(g.get("matched_files", [])) > 0 for g in explicit)')
        parts.append('    if all_skip_no_lines and has_matched:')
        parts.append('        print("[ci-local] FAIL: all patch gates show 0 instrumented lines but changed files match gate paths.", file=sys.stderr)')
        parts.append('        for g in explicit:')
        parts.append('            g["status"] = "FAIL"')
        parts.append('            g["reason"] = "no_coverage_data_with_changed_files"')
        parts.append('')
        parts.append('with open(results_path, "a") as f:')
        parts.append('    for g in flag_results:')
        parts.append('        f.write(json.dumps({"kind": "codecov", **g}) + "\\n")')
        parts.append('CILOCAL_COV_PY')
        parts.append("")
        parts.append('# Roll codecov FAILs into FAILED flag')
        parts.append('CODECOV_FAIL=$(grep -c \'"kind": "codecov"\' "$RESULTS_TMP" 2>/dev/null || echo 0)')
        parts.append('CODECOV_FAIL=$(python3 -c "import json,sys')
        parts.append('count = 0')
        parts.append('for line in open(sys.argv[1]):')
        parts.append('  try: e = json.loads(line)')
        parts.append('  except: continue')
        parts.append('  if e.get(\\"kind\\") == \\"codecov\\" and e.get(\\"status\\") == \\"FAIL\\": count += 1')
        parts.append('print(count)" "$RESULTS_TMP")')
        parts.append('if [ "${CODECOV_FAIL:-0}" -gt 0 ]; then FAILED=1; fi')
        parts.append("")

    # ---------- Evidence write + final exit ----------
    parts.append('# --- Aggregate results, write evidence, exit')
    parts.append('python3 - "$RESULTS_TMP" "$EVIDENCE_PATH" "$BRANCH" "$HEAD_SHA" "$FAILED" <<\'CILOCAL_FIN_PY\'')
    parts.append('import json, sys, datetime')
    parts.append('results_path, ev_path, branch, sha, failed = sys.argv[1:6]')
    parts.append('failed = int(failed)')
    parts.append('checks, codecov = [], []')
    parts.append('try:')
    parts.append('    for line in open(results_path):')
    parts.append('        try: e = json.loads(line)')
    parts.append('        except: continue')
    parts.append('        if e.get("kind") == "codecov":')
    parts.append('            codecov.append(e)')
    parts.append('        else:')
    parts.append('            checks.append(e)')
    parts.append('except FileNotFoundError:')
    parts.append('    pass')
    parts.append('summary = {')
    parts.append('    "executed_checks": len(checks),')
    parts.append('    "failed_checks": sum(1 for c in checks if c.get("status") == "FAIL"),')
    parts.append('    "codecov_failures": sum(1 for g in codecov if g.get("status") == "FAIL"),')
    parts.append('}')
    parts.append('overall = "FAIL" if failed else "PASS"')
    parts.append('payload = {')
    parts.append('    "branch": branch, "head_sha": sha,')
    parts.append('    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),')
    parts.append('    "status": overall,')
    parts.append('    "writer": "ci-local.sh",')
    parts.append('    "checks": checks,')
    parts.append('    "codecov_results": codecov,')
    parts.append('    "summary": summary,')
    parts.append('}')
    parts.append('with open(ev_path, "w") as f: json.dump(payload, f, indent=2)')
    parts.append('print(f"[ci-local] {overall}: {summary[\\"failed_checks\\"]} check failures, {summary[\\"codecov_failures\\"]} codecov failures (evidence: {ev_path})")')
    parts.append('sys.exit(0 if overall == "PASS" else 1)')
    parts.append('CILOCAL_FIN_PY')

content = "\n".join(parts) + "\n"

if dry_run:
    sys.stdout.write(content)
    sys.exit(0)

if out_path.exists() and not force:
    print(f"[ci-local-generate] ERROR: {out_path} already exists. Use --force to overwrite.", file=sys.stderr)
    sys.exit(1)

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(content, encoding="utf-8")
os.chmod(out_path, 0o755)
print(f"[ci-local-generate] wrote {out_path} ({len(content)} bytes, {len(parts)} lines)")
PY
