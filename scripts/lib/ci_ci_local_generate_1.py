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
env_classifier = sys.argv[7]

contract = json.loads(Path(contract_file).read_text(encoding="utf-8"))


def ci_local_override_path() -> Path:
    if out_path.parent.name == "generated-scripts":
        return out_path.parent.parent / "ci-local-overrides.json"
    return out_path.parent / "ci-local-overrides.json"


override_path = ci_local_override_path()
override_raw = ""
override_config = {}
if override_path.exists():
    override_raw = override_path.read_text(encoding="utf-8")
    try:
        override_config = json.loads(override_raw)
    except json.JSONDecodeError as exc:
        print(
            f"[ci-local-generate] ERROR: invalid JSON in {override_path}: {exc}",
            file=sys.stderr,
        )
        sys.exit(1)
    if not isinstance(override_config, dict):
        print(
            f"[ci-local-generate] ERROR: {override_path} must contain a JSON object",
            file=sys.stderr,
        )
        sys.exit(1)

mirror_hash = hashlib.sha256(
    (
        generator_hash
        + "\n"
        + json.dumps(
            contract, sort_keys=True, ensure_ascii=False, separators=(",", ":")
        )
        + "\n"
        + override_raw
    ).encode("utf-8")
).hexdigest()[:16]

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

                def rank(command):
                    if "--frozen-lockfile" in command:
                        return 0
                    if "--no-frozen-lockfile" in command:
                        return 2
                    return 1

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


def override_entries():
    entries = override_config.get("checks", [])
    if entries is None:
        return []
    if not isinstance(entries, list):
        print(
            f"[ci-local-generate] ERROR: {override_path} field checks must be a list",
            file=sys.stderr,
        )
        sys.exit(1)
    out = []
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            print(
                f"[ci-local-generate] ERROR: override checks[{idx}] must be an object",
                file=sys.stderr,
            )
            sys.exit(1)
        action = entry.get("action")
        if action != "skip":
            print(
                f"[ci-local-generate] ERROR: override checks[{idx}].action must be 'skip'",
                file=sys.stderr,
            )
            sys.exit(1)
        reason = str(entry.get("reason") or "").strip()
        if not reason:
            print(
                f"[ci-local-generate] ERROR: override checks[{idx}].reason is required",
                file=sys.stderr,
            )
            sys.exit(1)
        match = entry.get("match") or {}
        if not isinstance(match, dict) or not match:
            print(
                f"[ci-local-generate] ERROR: override checks[{idx}].match is required",
                file=sys.stderr,
            )
            sys.exit(1)
        out.append(
            {
                "id": str(entry.get("id") or f"override-{idx + 1}"),
                "action": action,
                "reason": reason,
                "match": match,
            }
        )
    return out


OVERRIDES = override_entries()


def check_matches_override(check, override) -> bool:
    match = override["match"]
    fields = {
        "category": check.get("category", ""),
        "job": check.get("job", ""),
        "source_file": check.get("source_file", ""),
        "command": check.get("command", ""),
    }
    for key in ("category", "job", "source_file", "command"):
        if key in match and str(match[key]) != str(fields[key]):
            return False
    if "command_contains" in match and str(match["command_contains"]) not in str(
        fields["command"]
    ):
        return False
    return True


def apply_check_overrides(checks):
    kept = []
    skipped = []
    for check in checks:
        override = next(
            (o for o in OVERRIDES if check_matches_override(check, o)), None
        )
        if override is None:
            kept.append(check)
            continue
        skipped.append(
            {
                "category": check.get("category", ""),
                "job": check.get("job", ""),
                "source_file": check.get("source_file", ""),
                "command": check.get("command", ""),
                "conditions": check.get("conditions") or {},
                "reason": f"repo_override:{override['id']}:{override['reason']}",
            }
        )
    return kept, skipped


def changeset_policy_command() -> str:
    return r"""python3 - "$BASE_BRANCH" <<'CILOCAL_CHANGESET_POLICY_PY'
import pathlib
import re
import subprocess
import sys

base_branch = sys.argv[1].strip()
ticket_re = re.compile(r"\[[A-Z0-9]+-[0-9]+\]")


def git(args):
    proc = subprocess.run(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def ref_exists(ref):
    return bool(git(["rev-parse", "--verify", ref]))


def resolve_base_ref():
    candidates = []
    if base_branch:
        if base_branch.startswith("origin/"):
            candidates.extend([base_branch, base_branch[len("origin/"):]])
        else:
            candidates.extend([f"origin/{base_branch}", base_branch])
    for cand in candidates:
        if ref_exists(cand):
            return cand
    for cand in ("origin/develop", "develop", "origin/main", "main", "origin/master", "master"):
        if ref_exists(cand):
            return cand
    return ""


def names_from_diff(args):
    output = git(["diff", "--name-only", *args])
    return [line.strip() for line in output.splitlines() if line.strip()]


base_ref = resolve_base_ref()
changed = set()
if base_ref:
    merge_base = git(["merge-base", "HEAD", base_ref])
    if merge_base:
        changed.update(names_from_diff([f"{merge_base}...HEAD"]))
changed.update(names_from_diff([]))
changed.update(names_from_diff(["--cached"]))

files = sorted(
    path
    for path in changed
    if path.startswith(".changeset/")
    and path.endswith(".md")
    and pathlib.Path(path).name.lower() != "readme.md"
)

if not files:
    print("[ci-local] FAIL: no .changeset/*.md file found in PR diff", file=sys.stderr)
    raise SystemExit(1)

missing_ticket = []
for file_name in files:
    try:
        text = pathlib.Path(file_name).read_text(encoding="utf-8")
    except OSError as exc:
        print(f"[ci-local] FAIL: cannot read {file_name}: {exc}", file=sys.stderr)
        raise SystemExit(1)
    if not ticket_re.search(text):
        missing_ticket.append(file_name)

if missing_ticket:
    print(
        "[ci-local] FAIL: changeset missing JIRA ticket ID: "
        + ", ".join(missing_ticket),
        file=sys.stderr,
    )
    raise SystemExit(1)

print("[ci-local] changeset policy PASS: " + ", ".join(files))
CILOCAL_CHANGESET_POLICY_PY"""


def release_readiness_consistency_command() -> str:
    """Emit the changeset-driven release-readiness consistency check (DP-295 AC4).

    A repo carrying the changeset version SoT (.changeset/config.json + package.json
    version + VERSION mirror) must keep VERSION == package.json version and have a
    CHANGELOG.md block for that version. Once a version bump consumes changesets, a
    drift between VERSION / package.json / CHANGELOG blocks the PR. The check runs
    from REPO_ROOT, which the generated mirror cd's into before any check.
    """
    return r"""python3 - <<'CILOCAL_RELEASE_READINESS_PY'
import json
import pathlib
import re
import sys

root = pathlib.Path.cwd()
pkg_path = root / "package.json"
version_path = root / "VERSION"
changelog_path = root / "CHANGELOG.md"

if not pkg_path.is_file():
    print("[ci-local] FAIL: release-readiness expects package.json at repo root", file=sys.stderr)
    raise SystemExit(1)

try:
    pkg_version = str(json.loads(pkg_path.read_text(encoding="utf-8"))["version"]).strip()
except (json.JSONDecodeError, KeyError, OSError) as exc:
    print(f"[ci-local] FAIL: cannot read package.json version: {exc}", file=sys.stderr)
    raise SystemExit(1)

if not version_path.is_file():
    print("[ci-local] FAIL: VERSION mirror file missing at repo root", file=sys.stderr)
    raise SystemExit(1)

version_mirror = version_path.read_text(encoding="utf-8").strip()

if version_mirror != pkg_version:
    print(
        f"[ci-local] FAIL: VERSION ({version_mirror}) != package.json version ({pkg_version})",
        file=sys.stderr,
    )
    raise SystemExit(1)

if not changelog_path.is_file():
    print("[ci-local] FAIL: CHANGELOG.md missing at repo root", file=sys.stderr)
    raise SystemExit(1)

changelog = changelog_path.read_text(encoding="utf-8")
block_re = re.compile(r"^##\s*\[" + re.escape(pkg_version) + r"\]", re.MULTILINE)
if not block_re.search(changelog):
    print(f"[ci-local] FAIL: CHANGELOG.md has no block for version {pkg_version}", file=sys.stderr)
    raise SystemExit(1)

print(f"[ci-local] release-readiness consistency PASS: VERSION == package.json == {pkg_version}; CHANGELOG block present")
CILOCAL_RELEASE_READINESS_PY"""


def has_changeset_version_sot() -> bool:
    """True when the repo carries the changeset version SoT (DP-295).

    Gate the release-readiness consistency check to repos that actually own a
    changeset config + package.json version + VERSION mirror, so product repos
    without that SoT do not gain a false-positive check.
    """
    if not (repo / ".changeset" / "config.json").is_file():
        return False
    if not (repo / "VERSION").is_file():
        return False
    pkg = repo / "package.json"
    if not pkg.is_file():
        return False
    try:
        return bool(
            str(
                json.loads(pkg.read_text(encoding="utf-8")).get("version") or ""
            ).strip()
        )
    except (json.JSONDecodeError, OSError):
        return False


def synthesize_release_readiness_checks():
    """Emit the release-readiness consistency policy for changeset-SoT repos."""
    if not has_changeset_version_sot():
        return []
    return [
        {
            "category": "policy",
            "source_file": "release-readiness",
            "job": "version-changelog-consistency",
            "command": release_readiness_consistency_command(),
            "conditions": {},
        }
    ]


def synthesize_policy_checks(checks):
    """Replace known CI policy jobs with local equivalents.

    CI containers often express a policy gate as several setup/control-flow
    fragments. Replaying those fragments locally is brittle, so the mirror
    emits a single deterministic check for each supported policy.
    """
    synthesized = []
    seen = set()
    for c in checks or []:
        source = c.get("source_file", "")
        job = c.get("job", "")
        key_text = f"{source}\n{job}".lower()
        if "changeset" not in key_text:
            continue
        key = ("changeset", source, job)
        if key in seen:
            continue
        seen.add(key)
        synthesized.append(
            {
                "category": "policy",
                "source_file": source,
                "job": job,
                "command": changeset_policy_command(),
                "conditions": c.get("conditions") or {},
            }
        )
    return synthesized


checks = filter_checks(contract.get("checks", []))
policy_checks = synthesize_policy_checks(contract.get("checks", []))
policy_checks.extend(synthesize_release_readiness_checks())
checks, forced_skip_checks = apply_check_overrides(checks)
policy_checks, forced_skip_policy_checks = apply_check_overrides(policy_checks)
forced_skip_checks.extend(forced_skip_policy_checks)
dev_hooks = filter_dev_hooks(contract.get("dev_hooks", []))
provider = contract.get("provider", "unknown")

# Install commands are a local dependency bootstrap. Keep them runnable even
# when the CI job that contributed the install command has branch filters, so
# other checks that do apply locally do not fail from missing dependencies.
for c in checks:
    if c.get("category") == "install":
        c["conditions"] = {}

has_anything = (
    bool(checks) or bool(policy_checks) or bool(forced_skip_checks) or bool(dev_hooks)
)


# ---------- Source fingerprints (for staleness advisory) ----------
def file_fingerprint(rel_path: str):
    # DP-338 D3: capture a content SHA so the generated staleness guard compares
    # file content (not mtime). A worktree checkout rewrites mtime without changing
    # content, which made the old mtime guard fire a false-positive stale error.
    p = repo / rel_path
    try:
        data = p.read_bytes()
        st = p.stat()
        content_sha = hashlib.sha256(data).hexdigest()
        return {
            "path": rel_path,
            "size": st.st_size,
            "mtime": int(st.st_mtime),
            "content_sha": content_sha,
        }
    except FileNotFoundError:
        return {"path": rel_path, "size": None, "mtime": None, "content_sha": None}


sources = []
for f in contract.get("files", []):
    sources.append(file_fingerprint(f))
# Husky / pre-commit sources
husky_root = repo / ".husky"
if husky_root.is_dir():
    for hp in sorted(husky_root.iterdir()):
        if hp.is_file():
            sources.append(file_fingerprint(str(hp.relative_to(repo))))
for n in (".pre-commit-config.yaml", ".pre-commit-hooks.yaml"):
    if (repo / n).exists():
        sources.append(file_fingerprint(n))
if override_path.exists():
    try:
        sources.append(file_fingerprint(str(override_path.relative_to(repo))))
    except ValueError:
        st = override_path.stat()
        sources.append(
            {
                "path": str(override_path),
                "size": st.st_size,
                "mtime": int(st.st_mtime),
                "content_sha": hashlib.sha256(override_path.read_bytes()).hexdigest(),
            }
        )

generated_at = datetime.datetime.now(datetime.timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%SZ"
)


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
parts.append(
    "# ci-local.sh — Tool-agnostic local mirror of repo CI checks (DP-032 D12 + DP-079)."
)
parts.append(f"# Generated by Polaris/scripts/ci-local-generate.sh on {generated_at}.")
parts.append(f"# Generator hash: {generator_hash}")
parts.append(f"# Mirror hash: {mirror_hash}")
parts.append(f"# CI provider: {provider}")
if override_path.exists():
    parts.append(f"# Repo overrides: {override_path}")
parts.append(
    "# Location: <company>/polaris-config/<project>/generated-scripts/ci-local.sh (workspace-owned)."
)
parts.append("# Usage:")
parts.append(
    "#   bash <company>/polaris-config/<project>/generated-scripts/ci-local.sh                # validates main checkout"
)
parts.append(
    "#   bash <company>/polaris-config/<project>/generated-scripts/ci-local.sh --repo <wt>    # validates worktree <wt>"
)
parts.append(
    "#   Cross-worktree: same canonical script serves every worktree of the repo."
)
parts.append("# Source CI declarations (regenerate when these change):")
for s in sources:
    if s["mtime"] is not None:
        ts = datetime.datetime.fromtimestamp(
            s["mtime"], datetime.timezone.utc
        ).strftime("%Y-%m-%d %H:%M:%S")
        parts.append(f"#   {s['path']} ({s['size']} bytes, mtime {ts})")
    else:
        parts.append(f"#   {s['path']} (missing)")
parts.append("#")
parts.append("# DO NOT EDIT MANUALLY — regenerate via:")
parts.append("#   {polaris}/scripts/ci-local-generate.sh --repo $(pwd) --force")
parts.append("")
parts.append("set -uo pipefail")
parts.append("")
parts.append("# Resolve target repo root.")
parts.append("# Priority: --repo <path> flag → script-location auto-detect (legacy).")
parts.append("# Why --repo: this script is canonically stored in the main checkout but")
parts.append(
    "# may be invoked to validate any worktree of the same repo (DP-043 follow-up)."
)
parts.append('TARGET_REPO=""')
parts.append(f"CI_LOCAL_MIRROR_HASH={shell_quote(mirror_hash)}")
parts.append('EVENT="${CI_LOCAL_EVENT:-pull_request}"')
parts.append('BASE_BRANCH="${CI_LOCAL_BASE_BRANCH:-}"')
parts.append('SOURCE_BRANCH="${CI_LOCAL_SOURCE_BRANCH:-}"')
parts.append('REF="${CI_LOCAL_REF:-}"')
parts.append("while [[ $# -gt 0 ]]; do")
parts.append('  case "$1" in')
parts.append('    --repo) TARGET_REPO="$2"; shift 2 ;;')
parts.append('    --event) EVENT="$2"; shift 2 ;;')
parts.append('    --base-branch) BASE_BRANCH="$2"; shift 2 ;;')
parts.append('    --source-branch) SOURCE_BRANCH="$2"; shift 2 ;;')
parts.append('    --ref) REF="$2"; shift 2 ;;')
parts.append("    --help|-h)")
parts.append(
    '      echo "Usage: ci-local.sh [--repo <path>] [--event pull_request|push|tag] [--base-branch <branch>] [--source-branch <branch>] [--ref <ref>]" >&2'
)
parts.append(
    '      echo "  --repo  target repo root (default: auto-detect from script location)" >&2'
)
parts.append("      exit 0 ;;")
parts.append('    *) echo "[ci-local] Unknown argument: $1" >&2; exit 2 ;;')
parts.append("  esac")
parts.append("done")
parts.append("")
parts.append('if [[ -n "$TARGET_REPO" ]]; then')
parts.append('  REPO_ROOT="$(cd "$TARGET_REPO" 2>/dev/null && pwd)"')
parts.append('  if [[ -z "$REPO_ROOT" ]]; then')
parts.append('    echo "[ci-local] ERROR: --repo path not found: $TARGET_REPO" >&2')
parts.append("    exit 2")
parts.append("  fi")
parts.append("else")
parts.append('  SCRIPT_DIR_REAL="$(cd "$(dirname "$0")" && pwd)"')
parts.append(
    '  REPO_ROOT="$(git -C "$SCRIPT_DIR_REAL" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR_REAL/../.." && pwd))"'
)
parts.append("fi")
parts.append('cd "$REPO_ROOT"')
parts.append("")
parts.append('HEAD_SHA="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"')
parts.append('BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"')
parts.append('if [ -z "$SOURCE_BRANCH" ]; then SOURCE_BRANCH="$BRANCH"; fi')
parts.append(
    'if [ -z "$REF" ] && [ "$BRANCH" != "HEAD" ] && [ "$BRANCH" != "unknown" ]; then REF="refs/heads/$BRANCH"; fi'
)
parts.append('if [ -z "$BASE_BRANCH" ]; then')
parts.append(
    '  _upstream="$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null || true)"'
)
parts.append('  _upstream="${_upstream#origin/}"')
parts.append('  if [ -n "$_upstream" ] && [ "$_upstream" != "$BRANCH" ]; then')
parts.append('    BASE_BRANCH="$_upstream"')
parts.append("  else")
parts.append("    for _cand in develop main master; do")
parts.append(
    '      if git rev-parse --verify "origin/${_cand}" >/dev/null 2>&1; then BASE_BRANCH="$_cand"; break; fi'
)
parts.append("    done")
parts.append("  fi")
parts.append("fi")
parts.append('BRANCH_SLUG="$(printf "%s" "$BRANCH" | tr "/" "-")"')
parts.append(
    'CONTEXT_HASH="$(python3 -c "import hashlib,sys; print(hashlib.sha1(sys.argv[1].encode()).hexdigest()[:12])" "$EVENT|$BASE_BRANCH|$SOURCE_BRANCH|$REF")"'
)
parts.append(
    'EVIDENCE_PATH="/tmp/polaris-ci-local-${BRANCH_SLUG}-${HEAD_SHA}-${CONTEXT_HASH}.json"'
)
parts.append(
    'echo "[ci-local] context: event=$EVENT base_branch=${BASE_BRANCH:-unknown} source_branch=${SOURCE_BRANCH:-unknown} ref=${REF:-unknown}"'
)
parts.append('COMMAND_CI="${CI_LOCAL_CI:-${CI:-true}}"')
parts.append('COMMAND_TZ="${CI_LOCAL_TZ:-${TZ:-UTC}}"')
parts.append('if [ -n "${CI_LOCAL_DEBUG+x}" ]; then')
parts.append('  COMMAND_DEBUG="$CI_LOCAL_DEBUG"')
parts.append('  COMMAND_DEBUG_LABEL="$COMMAND_DEBUG"')
parts.append("else")
parts.append('  COMMAND_DEBUG=""')
parts.append('  COMMAND_DEBUG_LABEL="<unset>"')
parts.append("fi")
parts.append(f"CILOCAL_ENV_CLASSIFIER={shell_quote(env_classifier)}")
parts.append(
    'echo "[ci-local] command env: CI=$COMMAND_CI TZ=$COMMAND_TZ DEBUG=$COMMAND_DEBUG_LABEL"'
)
parts.append("")
parts.append("# --- Staleness guard: CI declarations are the source of this mirror.")
parts.append(
    "# DP-338 D3: compare each source file by CONTENT HASH captured at generation"
)
parts.append(
    "# time, not mtime. A worktree checkout rewrites source mtime without changing"
)
parts.append(
    '# content; an mtime guard would false-positive "CI config changed" there.'
)
parts.append("# A real content edit still changes the hash and trips the guard.")
parts.append("_ci_local_content_sha() {")
parts.append("  if command -v shasum >/dev/null 2>&1; then")
parts.append('    shasum -a 256 "$1" 2>/dev/null | cut -d" " -f1')
parts.append("  elif command -v sha256sum >/dev/null 2>&1; then")
parts.append('    sha256sum "$1" 2>/dev/null | cut -d" " -f1')
parts.append("  else")
parts.append(
    '    echo "[ci-local] ERROR: neither shasum nor sha256sum found for staleness check" >&2'
)
parts.append('    echo "POLARIS_TOOL_MISSING:shasum" >&2')
parts.append("    exit 2")
parts.append("  fi")
parts.append("}")
parts.append('STALE_FILES=""')
for s in sources:
    if s["content_sha"] is None:
        continue
    parts.append(f'if [ ! -e "{s["path"]}" ]; then')
    parts.append(f'  STALE_FILES="$STALE_FILES {s["path"]}(missing)"')
    parts.append("else")
    parts.append(f'  _src_sha=$(_ci_local_content_sha "{s["path"]}")')
    parts.append(
        f'  if [ "$_src_sha" != "{s["content_sha"]}" ]; then STALE_FILES="$STALE_FILES {s["path"]}"; fi'
    )
    parts.append("fi")
parts.append('if [ -n "$STALE_FILES" ]; then')
parts.append(
    '  echo "[ci-local] ERROR: CI config changed after ci-local.sh generation:$STALE_FILES" >&2'
)
parts.append(
    '  echo "[ci-local] Regenerate with: bash {polaris}/scripts/ci-local-generate.sh --repo ${REPO_ROOT} --force" >&2'
)
parts.append("  exit 2")
parts.append("fi")
parts.append("")
parts.append(
    "# --- Cache check: same head_sha + same mirror hash + PASS evidence → exit 0 (no rerun)"
)
parts.append('if [ -f "$EVIDENCE_PATH" ]; then')
parts.append('  CACHED_META="$(python3 - "$EVIDENCE_PATH" <<\'CILOCAL_CACHE_PY\'')
parts.append("import json, sys")
parts.append("try:")
parts.append('    d = json.load(open(sys.argv[1], "r", encoding="utf-8"))')
parts.append(
    '    print(str(d.get("status", "")) + "|" + str(d.get("ci_local_mirror_hash", "")))'
)
parts.append("except Exception:")
parts.append('    print("|")')
parts.append("CILOCAL_CACHE_PY")
parts.append(')"')
parts.append('  CACHED_STATUS="${CACHED_META%%|*}"')
parts.append('  CACHED_MIRROR_HASH="${CACHED_META#*|}"')
parts.append(
    '  if [ "$CACHED_STATUS" = "PASS" ] && [ "$CACHED_MIRROR_HASH" = "$CI_LOCAL_MIRROR_HASH" ]; then'
)
parts.append(
    '    echo "[ci-local] cache hit: $EVIDENCE_PATH (head_sha=$HEAD_SHA, mirror_hash=$CI_LOCAL_MIRROR_HASH, status=PASS)"'
)
parts.append("    exit 0")
parts.append("  fi")
parts.append('  if [ "$CACHED_STATUS" = "PASS" ]; then')
parts.append(
    '    echo "[ci-local] cache ignored: mirror hash changed (cached=${CACHED_MIRROR_HASH:-<none>} current=$CI_LOCAL_MIRROR_HASH)" >&2'
)
parts.append("  fi")
parts.append("fi")
parts.append("")

if not has_anything:
    # NO_CHECKS_CONFIGURED branch
    parts.append(
        "# --- NO_CHECKS_CONFIGURED: this repo has no CI declarations to mirror"
    )
    parts.append(
        'echo "[ci-local] NO_CHECKS_CONFIGURED — repo has no parseable CI declarations"'
    )
    parts.append(
        'python3 - "$EVIDENCE_PATH" "$BRANCH" "$HEAD_SHA" "$EVENT" "$BASE_BRANCH" "$SOURCE_BRANCH" "$REF" "$CI_LOCAL_MIRROR_HASH" <<\'CILOCAL_NCC_PY\''
    )
    parts.append("import json, sys, datetime")
    parts.append(
        "path, branch, sha, event, base_branch, source_branch, ref, mirror_hash = sys.argv[1:9]"
    )
    parts.append('with open(path, "w") as f:')
    parts.append("    json.dump({")
    parts.append('        "branch": branch, "head_sha": sha,')
    parts.append('        "ci_local_mirror_hash": mirror_hash,')
    parts.append(
        '        "context": {"event": event, "base_branch": base_branch, "source_branch": source_branch, "ref": ref},'
    )
    parts.append(
        '        "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),'
    )
    parts.append('        "status": "PASS",')
    parts.append('        "writer": "ci-local.sh",')
    parts.append('        "checks": [],')
    parts.append('        "reason": "NO_CHECKS_CONFIGURED",')
    parts.append("    }, f, indent=2)")
    parts.append("CILOCAL_NCC_PY")
    parts.append('echo "[ci-local] evidence written: $EVIDENCE_PATH"')
    parts.append("exit 0")
else:
    parts.append("RESULTS_TMP=$(mktemp)")
    parts.append("CMD_OUT_DIR=$(mktemp -d)")
    parts.append('trap \'rm -rf "$RESULTS_TMP" "$CMD_OUT_DIR"\' EXIT')
    parts.append("FAILED=0")
    parts.append("BLOCKED_ENV=0")
    parts.append("INSTALL_ABORT=0")
    parts.append("")
    parts.append("condition_result() {")
    parts.append('  local conditions_json="$1"')
    parts.append(
        '  CILOCAL_CONDITIONS_JSON="$conditions_json" python3 - "$EVENT" "$BASE_BRANCH" "$SOURCE_BRANCH" "$REF" <<\'CILOCAL_COND_PY\''
    )
    parts.append("import fnmatch, json, os, sys")
    parts.append(
        'conditions = json.loads(os.environ.get("CILOCAL_CONDITIONS_JSON") or "{}")'
    )
    parts.append("event, base_branch, source_branch, ref = sys.argv[1:5]")
    parts.append("")
    parts.append("def values(name):")
    parts.append("    raw = conditions.get(name) or []")
    parts.append("    if isinstance(raw, str):")
    parts.append("        return [raw]")
    parts.append("    if isinstance(raw, list):")
    parts.append("        return [str(x) for x in raw]")
    parts.append("    return []")
    parts.append("")
    parts.append("def match_any(value, patterns):")
    parts.append('    return any(fnmatch.fnmatch(value or "", p) for p in patterns)')
    parts.append("")
    parts.append('events = values("events")')
    parts.append("if events and event not in events:")
    parts.append('    print("SKIP\\tevent_not_matched")')
    parts.append("    raise SystemExit(0)")
    parts.append('branches = values("branches")')
    parts.append("if branches and not match_any(base_branch, branches):")
    parts.append('    print("SKIP\\tbranch_not_matched")')
    parts.append("    raise SystemExit(0)")
    parts.append('refs = values("refs")')
    parts.append("if refs and not match_any(ref, refs):")
    parts.append('    print("SKIP\\tref_not_matched")')
    parts.append("    raise SystemExit(0)")
    parts.append(
        "# Woodpecker status conditions are only meaningful after previous pipeline"
    )
    parts.append(
        "# steps. ci-local executes selected checks directly, so status=success"
    )
    parts.append(
        "# does not exclude a check locally; other statuses are not modelled yet."
    )
    parts.append('print("RUN\\tmatched")')
    parts.append("CILOCAL_COND_PY")
    parts.append("}")
    parts.append("")
    parts.append("record_skip() {")
    parts.append(
        '  local idx="$1" category="$2" job="$3" source_file="$4" cmd_file="$5" reason="$6" conditions_json="$7"'
    )
    parts.append("  local cmd")
    parts.append('  cmd="$(cat "$cmd_file")"')
    parts.append('  echo "[ci-local] [$category] $source_file::$job"')
    parts.append('  echo "  ↷ SKIP ($reason)"')
    parts.append(
        '  CILOCAL_CONDITIONS_JSON="$conditions_json" python3 - "$RESULTS_TMP" "$idx" "$category" "$job" "$source_file" "$cmd_file" "$reason" "$EVENT" "$BASE_BRANCH" "$SOURCE_BRANCH" "$REF" <<\'CILOCAL_SKIP_PY\''
    )
    parts.append("import json, os, sys")
    parts.append(
        "results_path, idx, category, job, source_file, cmd_file, reason, event, base_branch, source_branch, ref = sys.argv[1:12]"
    )
    parts.append("entry = {")
    parts.append('    "idx": int(idx),')
    parts.append('    "category": category,')
    parts.append('    "job": job,')
    parts.append('    "source_file": source_file,')
    parts.append('    "command": open(cmd_file).read().rstrip(),')
    parts.append('    "exit_code": 0,')
    parts.append('    "status": "SKIP",')
    parts.append('    "reason": reason,')
    parts.append(
        '    "conditions": json.loads(os.environ.get("CILOCAL_CONDITIONS_JSON") or "{}"),'
    )
    parts.append(
        '    "context": {"event": event, "base_branch": base_branch, "source_branch": source_branch, "ref": ref},'
    )
    parts.append("}")
    parts.append('with open(results_path, "a") as f:')
    parts.append('    f.write(json.dumps(entry) + "\\n")')
    parts.append("CILOCAL_SKIP_PY")
    parts.append("}")
    parts.append("")
    parts.append("run_check() {")
    parts.append(
        '  local idx="$1" category="$2" job="$3" source_file="$4" cmd_file="$5" conditions_json=""'
    )
    parts.append('  conditions_json="${6:-}"')
    parts.append('  if [ -z "$conditions_json" ]; then conditions_json="{}"; fi')
    parts.append("  local decision reason")
    parts.append(
        "  IFS=$'\\t' read -r decision reason < <(condition_result \"$conditions_json\")"
    )
    parts.append('  if [ "$decision" = "SKIP" ]; then')
    parts.append(
        '    record_skip "$idx" "$category" "$job" "$source_file" "$cmd_file" "$reason" "$conditions_json"'
    )
    parts.append("    return 0")
    parts.append("  fi")
    parts.append("  local cmd_preview")
    parts.append('  cmd_preview="$(head -1 "$cmd_file")"')
    parts.append('  echo "[ci-local] [$category] $source_file::$job"')
    parts.append('  echo "  > $cmd_preview"')
    parts.append('  local out_file="$CMD_OUT_DIR/${idx}.out"')
    parts.append("  local rc=0")
    parts.append('  if [ -n "${CI_LOCAL_DEBUG+x}" ]; then')
    parts.append(
        '    CI="$COMMAND_CI" TZ="$COMMAND_TZ" DEBUG="$COMMAND_DEBUG" bash -lc "$(cat "$cmd_file")" >"$out_file" 2>&1 || rc=$?'
    )
    parts.append("  else")
    parts.append(
        '    env -u DEBUG CI="$COMMAND_CI" TZ="$COMMAND_TZ" bash -lc "$(cat "$cmd_file")" >"$out_file" 2>&1 || rc=$?'
    )
    parts.append("  fi")
    parts.append('  local classification_json=""')
    parts.append('  if [ $rc -ne 0 ] && [ -f "$CILOCAL_ENV_CLASSIFIER" ]; then')
    parts.append(
        '    classification_json="$(python3 "$CILOCAL_ENV_CLASSIFIER" --repo "$REPO_ROOT" --category "$category" --command "$(cat "$cmd_file")" --output-file "$out_file" 2>/dev/null || true)"'
    )
    parts.append("  fi")
    parts.append(
        '  CILOCAL_ENV_CLASSIFICATION_JSON="$classification_json" python3 - "$RESULTS_TMP" "$idx" "$category" "$job" "$source_file" "$cmd_file" "$out_file" "$rc" "$COMMAND_CI" "$COMMAND_TZ" <<\'CILOCAL_RC_PY\''
    )
    parts.append("import json, os, sys")
    parts.append(
        "results_path, idx, category, job, source_file, cmd_file, out_file, rc, command_ci, command_tz = sys.argv[1:11]"
    )
    parts.append("rc = int(rc)")
    parts.append("cmd = open(cmd_file).read().rstrip()")
    parts.append("try:")
    parts.append("    output = open(out_file).read()")
    parts.append("except Exception:")
    parts.append('    output = ""')
    parts.append("lines = output.strip().splitlines()")
    parts.append('tail = "\\n".join(lines[-40:])')
    parts.append("classification = {}")
    parts.append(
        'raw_classification = os.environ.get("CILOCAL_ENV_CLASSIFICATION_JSON") or ""'
    )
    parts.append("if raw_classification:")
    parts.append("    try: classification = json.loads(raw_classification)")
    parts.append("    except Exception: classification = {}")
    parts.append('status = "PASS" if rc == 0 else "FAIL"')
    parts.append("blocked_env = None")
    parts.append('if rc != 0 and classification.get("status") == "BLOCKED_ENV":')
    parts.append('    status = "BLOCKED_ENV"')
    parts.append("    blocked_env = {")
    parts.append('        "reason": classification.get("reason"),')
    parts.append('        "detail": classification.get("detail"),')
    parts.append('        "stage": classification.get("stage"),')
    parts.append('        "host": classification.get("host"),')
    parts.append('        "package_manager": classification.get("package_manager"),')
    parts.append(
        '        "registry_hosts": classification.get("registry_hosts") or [],'
    )
    parts.append('        "output_tail": classification.get("output_tail") or tail,')
    parts.append("    }")
    parts.append("entry = {")
    parts.append('    "idx": int(idx),')
    parts.append('    "category": category,')
    parts.append('    "job": job,')
    parts.append('    "source_file": source_file,')
    parts.append('    "command": cmd,')
    parts.append('    "exit_code": rc,')
    parts.append('    "status": status,')
    parts.append('    "environment": {"CI": command_ci, "TZ": command_tz},')
    parts.append('    "output_tail": tail,')
    parts.append("}")
    parts.append("if blocked_env:")
    parts.append('    entry["blocked_env"] = blocked_env')
    parts.append('with open(results_path, "a") as f:')
    parts.append('    f.write(json.dumps(entry) + "\\n")')
    parts.append("CILOCAL_RC_PY")
    parts.append("  if [ $rc -ne 0 ]; then")
    parts.append('    local classified_status=""')
    parts.append(
        '    if [ -n "$classification_json" ]; then classified_status="$(python3 -c "import json,sys; print(json.loads(sys.argv[1]).get(\'status\', \'\'))" "$classification_json" 2>/dev/null || true)"; fi'
    )
    parts.append('    if [ "$classified_status" = "BLOCKED_ENV" ]; then')
    parts.append("      BLOCKED_ENV=1")
    parts.append(
        '      echo "  ✗ BLOCKED_ENV (exit $rc) — dependency environment blocker" >&2'
    )
    parts.append(
        "      python3 -c \"import json,sys; d=json.loads(sys.argv[1]); print('    reason='+str(d.get('reason'))+' host='+str(d.get('host')))\" \"$classification_json\" >&2 || true"
    )
    parts.append("      FAILED=1")
    parts.append('      [ "$category" = "install" ] && INSTALL_ABORT=1')
    parts.append("      return 1")
    parts.append("    fi")
    parts.append('    if [ "$category" = "install" ]; then')
    parts.append(
        '      echo "  ✗ install FAIL (exit $rc) — aborting (downstream checks meaningless)" >&2'
    )
    parts.append('      tail -40 "$out_file" >&2 || true')
    parts.append("      FAILED=1")
    parts.append("      return 1")
    parts.append("    else")
    parts.append('      echo "  ✗ FAIL (exit $rc)"')
    parts.append('      tail -20 "$out_file" || true')
    parts.append("      FAILED=1")
    parts.append("    fi")
    parts.append("  else")
    parts.append('    echo "  ✓ PASS"')
    parts.append("  fi")
    parts.append("}")
    parts.append("")
    # Emit numbered command files
    idx = 0
    all_runs = []
    for c in checks + policy_checks:
        idx += 1
        cat = c.get("category", "policy")
        job = c.get("job", "")
        src = c.get("source_file", "")
        cmd_body = c.get("command", "").rstrip("\n")
        conditions = json.dumps(
            c.get("conditions") or {}, ensure_ascii=False, separators=(",", ":")
        )
        parts.append(f"# Check {idx}: [{cat}] {src}::{job}")
        parts.append(
            f'cat > "$CMD_OUT_DIR/{idx}.cmd" {heredoc_block("CILOCAL_CMD", cmd_body)}'
        )
        all_runs.append((idx, cat, job, src, conditions))
    for h in dev_hooks:
        idx += 1
        cat = h.get("category", "policy")
        ht = h.get("hook_type", "pre-commit")
        src = h.get("source_file", "")
        cmd_body = h.get("command", "").rstrip("\n")
        parts.append(f"# Dev hook {idx}: [{cat}] {src}::{ht}")
        parts.append(
            f'cat > "$CMD_OUT_DIR/{idx}.cmd" {heredoc_block("CILOCAL_HOOK", cmd_body)}'
        )
        all_runs.append((idx, cat, ht, src, "{}"))
    forced_skips = []
    for s in forced_skip_checks:
        idx += 1
        cat = s.get("category", "policy")
        job = s.get("job", "")
        src = s.get("source_file", "")
        cmd_body = s.get("command", "").rstrip("\n")
        conditions = json.dumps(
            s.get("conditions") or {}, ensure_ascii=False, separators=(",", ":")
        )
        reason = s.get("reason", "repo_override")
        parts.append(f"# Forced skip {idx}: [{cat}] {src}::{job}")
        parts.append(
            f'cat > "$CMD_OUT_DIR/{idx}.cmd" {heredoc_block("CILOCAL_SKIP_CMD", cmd_body)}'
        )
        forced_skips.append((idx, cat, job, src, conditions, reason))
    parts.append("")
    for idx_, cat, job, src, conditions, reason in forced_skips:
        parts.append(
            f'record_skip {idx_} {shell_quote(cat)} {shell_quote(job)} {shell_quote(src)} "$CMD_OUT_DIR/{idx_}.cmd" {shell_quote(reason)} {shell_quote(conditions)}'
        )
    for idx_, cat, job, src, conditions in all_runs:
        parts.append('if [ "$INSTALL_ABORT" = "0" ]; then')
        parts.append(
            f'run_check {idx_} {shell_quote(cat)} {shell_quote(job)} {shell_quote(src)} "$CMD_OUT_DIR/{idx_}.cmd" {shell_quote(conditions)} || true'
        )
        parts.append("fi")
    parts.append("")

    # ---------- Evidence write + final exit ----------
    parts.append("# --- Aggregate results, write evidence, exit")
    parts.append(
        'python3 - "$RESULTS_TMP" "$EVIDENCE_PATH" "$BRANCH" "$HEAD_SHA" "$FAILED" "$BLOCKED_ENV" "$EVENT" "$BASE_BRANCH" "$SOURCE_BRANCH" "$REF" "$CI_LOCAL_MIRROR_HASH" <<\'CILOCAL_FIN_PY\''
    )
    parts.append("import json, sys, datetime")
    parts.append(
        "results_path, ev_path, branch, sha, failed, blocked_env_flag, event, base_branch, source_branch, ref, mirror_hash = sys.argv[1:12]"
    )
    parts.append("failed = int(failed)")
    parts.append("blocked_env_flag = int(blocked_env_flag)")
    parts.append("checks = []")
    parts.append("try:")
    parts.append("    for line in open(results_path):")
    parts.append("        try: e = json.loads(line)")
    parts.append("        except: continue")
    parts.append("        checks.append(e)")
    parts.append("except FileNotFoundError:")
    parts.append("    pass")
    parts.append("summary = {")
    parts.append('    "executed_checks": len(checks),')
    parts.append(
        '    "failed_checks": sum(1 for c in checks if c.get("status") == "FAIL"),'
    )
    parts.append(
        '    "blocked_env_checks": sum(1 for c in checks if c.get("status") == "BLOCKED_ENV"),'
    )
    parts.append(
        '    "skipped_checks": sum(1 for c in checks if c.get("status") == "SKIP"),'
    )
    parts.append("}")
    parts.append(
        'overall = "BLOCKED_ENV" if blocked_env_flag or summary["blocked_env_checks"] else ("FAIL" if failed else "PASS")'
    )
    parts.append(
        'first_blocked = next((c.get("blocked_env") for c in checks if c.get("status") == "BLOCKED_ENV" and c.get("blocked_env")), None)'
    )
    parts.append("payload = {")
    parts.append('    "branch": branch, "head_sha": sha,')
    parts.append('    "ci_local_mirror_hash": mirror_hash,')
    parts.append(
        '    "context": {"event": event, "base_branch": base_branch, "source_branch": source_branch, "ref": ref},'
    )
    parts.append(
        '    "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),'
    )
    parts.append('    "status": overall,')
    parts.append('    "writer": "ci-local.sh",')
    parts.append('    "checks": checks,')
    parts.append('    "summary": summary,')
    parts.append("}")
    parts.append("if first_blocked:")
    parts.append('    payload["blocked_env"] = first_blocked')
    parts.append('with open(ev_path, "w") as f: json.dump(payload, f, indent=2)')
    # NOTE: single-quoted dict keys keep the f-string compatible with
    # Python <3.12 (PEP 701 lifted the backslash-in-expression restriction).
    parts.append(
        "print(f\"[ci-local] {overall}: {summary['failed_checks']} check failures (evidence: {ev_path})\")"
    )
    parts.append('sys.exit(0 if overall == "PASS" else 1)')
    parts.append("CILOCAL_FIN_PY")

content = "\n".join(parts) + "\n"

if dry_run:
    sys.stdout.write(content)
    sys.exit(0)

if out_path.exists() and not force:
    print(
        f"[ci-local-generate] ERROR: {out_path} already exists. Use --force to overwrite.",
        file=sys.stderr,
    )
    sys.exit(1)

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text(content, encoding="utf-8")
os.chmod(out_path, 0o755)
print(
    f"[ci-local-generate] wrote {out_path} ({len(content)} bytes, {len(parts)} lines)"
)
