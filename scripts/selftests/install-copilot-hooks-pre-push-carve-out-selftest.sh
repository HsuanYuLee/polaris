#!/usr/bin/env bash
# Purpose: Verify the generated .git/hooks/pre-push from install-copilot-hooks.sh
#          mirrors the pre-push-quality-gate.sh delete/tags carve-out (DP-305 D4).
# Inputs:  none (builds an isolated temp git repo + installs the hook)
# Outputs: exit 0 + "PASS" on success; non-zero + diagnostic on failure
# Side effects: creates and removes a temp dir under $TMPDIR
#
# Contract under test (AC4 / AC-NEG2):
#   - delete-only push (stdin all-zero local SHA) -> hook exits 0 BEFORE gates run
#   - tags-only push (remote refs all refs/tags/*) -> hook exits 0 BEFORE gates run
#   - content-bearing push (real local SHA on a branch ref) -> gates RUN; when a
#     gate fails the hook propagates the non-zero exit (carve-out must not leak
#     content pushes through).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-copilot-hooks.sh"

tmp="$(mktemp -d -t install-copilot-hooks-pre-push-carve-out.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/scripts/gates"
git init -b main "$repo" >/dev/null
git -C "$repo" config user.email selftest@example.test
git -C "$repo" config user.name "Self Test"
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -m "base" >/dev/null

cp "$INSTALLER" "$repo/scripts/install-copilot-hooks.sh"
chmod +x "$repo/scripts/install-copilot-hooks.sh"

# Plant a sentinel gate that always fails. Any pre-push run that reaches the
# gate phase will exit non-zero through this gate. A passing carve-out short-
# circuits before reaching it; a content-bearing push must hit it.
sentinel="$repo/.gates-ran"
cat > "$repo/scripts/gates/gate-template-leaks.sh" <<'SENTINEL'
#!/usr/bin/env bash
set -euo pipefail
repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    *) shift ;;
  esac
done
touch "${repo:-.}/.gates-ran"
echo "[sentinel gate] FAIL (gates reached)" >&2
exit 1
SENTINEL
chmod +x "$repo/scripts/gates/gate-template-leaks.sh"

bash "$repo/scripts/install-copilot-hooks.sh" >/dev/null

pre_push="$repo/.git/hooks/pre-push"
[[ -x "$pre_push" ]] || { echo "[selftest] pre-push hook was not installed" >&2; exit 1; }

base_sha="$(git -C "$repo" rev-parse HEAD)"
zero_sha="0000000000000000000000000000000000000000"

# run_hook <stdin-payload> -> prints exit code, leaves $sentinel iff gates ran.
# The generated pre-push hook resolves REPO_ROOT via `git rev-parse --show-toplevel`
# from its cwd, so the hook must run with cwd inside the temp repo (not the host
# workspace). Invoke it in a subshell anchored at $repo. The hook contract is:
# arg1=remote-name, arg2=remote-url, refs on stdin.
run_hook() {
  local payload="$1"
  rm -f "$sentinel"
  set +e
  ( cd "$repo" && printf '%s' "$payload" | "$pre_push" origin "https://example.test/repo.git" )
  local rc=$?
  set -e
  echo "$rc"
}

# --- AC4: delete-only push -> exit 0, gates NOT run ---------------------------
# git delete-ref stdin form: "(delete) <zero> <remote-ref> <remote-sha>"
delete_payload="(delete) ${zero_sha} refs/heads/task/foo ${base_sha}
"
rc="$(run_hook "$delete_payload")"
if [[ "$rc" != "0" ]]; then
  echo "[selftest][AC4] delete-only push expected exit 0, got $rc" >&2
  exit 1
fi
if [[ -e "$sentinel" ]]; then
  echo "[selftest][AC4] delete-only push reached gates (sentinel present)" >&2
  exit 1
fi

# --- AC4: tags-only push -> exit 0, gates NOT run -----------------------------
tags_payload="refs/tags/v1.2.3 ${base_sha} refs/tags/v1.2.3 ${zero_sha}
"
rc="$(run_hook "$tags_payload")"
if [[ "$rc" != "0" ]]; then
  echo "[selftest][AC4] tags-only push expected exit 0, got $rc" >&2
  exit 1
fi
if [[ -e "$sentinel" ]]; then
  echo "[selftest][AC4] tags-only push reached gates (sentinel present)" >&2
  exit 1
fi

# --- AC4: multi-ref delete-only push -> exit 0, gates NOT run -----------------
multi_delete_payload="(delete) ${zero_sha} refs/heads/task/a ${base_sha}
(delete) ${zero_sha} refs/heads/task/b ${base_sha}
"
rc="$(run_hook "$multi_delete_payload")"
if [[ "$rc" != "0" ]]; then
  echo "[selftest][AC4] multi delete-only push expected exit 0, got $rc" >&2
  exit 1
fi
if [[ -e "$sentinel" ]]; then
  echo "[selftest][AC4] multi delete-only push reached gates (sentinel present)" >&2
  exit 1
fi

# --- AC-NEG2: content-bearing push -> gates RUN, non-zero propagates ----------
# Real branch ref with a real local SHA: this is a content push and must NOT be
# carved out. The sentinel gate fails, so the hook must exit non-zero.
content_payload="refs/heads/task/DP-305-T3 ${base_sha} refs/heads/task/DP-305-T3 ${zero_sha}
"
rc="$(run_hook "$content_payload")"
if [[ "$rc" == "0" ]]; then
  echo "[selftest][AC-NEG2] content-bearing push leaked through carve-out (exit 0)" >&2
  exit 1
fi
if [[ ! -e "$sentinel" ]]; then
  echo "[selftest][AC-NEG2] content-bearing push did not reach gates (no sentinel)" >&2
  exit 1
fi

# --- AC-NEG2: mixed delete + content push -> gates RUN ------------------------
# A push that deletes one ref AND updates another (content) must NOT be carved
# out — only an all-deletions / all-tags push is exempt.
mixed_payload="(delete) ${zero_sha} refs/heads/task/old ${base_sha}
refs/heads/task/DP-305-T3 ${base_sha} refs/heads/task/DP-305-T3 ${zero_sha}
"
rc="$(run_hook "$mixed_payload")"
if [[ "$rc" == "0" ]]; then
  echo "[selftest][AC-NEG2] mixed delete+content push leaked through carve-out (exit 0)" >&2
  exit 1
fi
if [[ ! -e "$sentinel" ]]; then
  echo "[selftest][AC-NEG2] mixed delete+content push did not reach gates (no sentinel)" >&2
  exit 1
fi

echo "[install-copilot-hooks-pre-push-carve-out-selftest] PASS"
