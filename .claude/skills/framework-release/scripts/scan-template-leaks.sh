#!/usr/bin/env bash
# Purpose: Scan a Polaris workspace (and/or the Polaris template) for company-specific
#          leaks (slugs, JIRA prefixes, domains, Slack IDs, GitHub org, active DP paths)
#          before sync-to-polaris. Scan scope converges to the sync copy set: gitignored
#          runtime state is the single "does NOT sync" authority and is exempt (DP-303 T3).
# Inputs:  --workspace <path> --template <path> --source <workspace|template|both>
#          --format <summary|markdown|json> --blocking
#          --only-path <rel> (repeatable, triage aid)
# Outputs: leak report on stdout; exit 0 clean, exit 1 with --blocking when hits exist,
#          exit 2 on usage / missing-input error. POLARIS_TEMPLATE_LEAK on stderr when blocked.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 沒有人告訴我們工作區在哪的時候，往上找第一個帶 `.claude/skills` 的祖先——這是
# run-gates.sh 已經在用的同一個判準，不是第二份答案。
#
# 以前這裡是 `cd "$SCRIPT_DIR/.."`，假設自己還住在 `{repo}/scripts/` 底下；DP-462 把它搬進
# skill 目錄之後，那一行算出來的是 `.claude/skills/framework-release`。實測：同一棵樹、同一
# 份注入的外洩，不帶 --workspace 印 `hits: 0` 並 exit 0，帶著正確的根印 `hits: 1` 並擋下來。
# 兩個呼叫端都明確帶 --workspace，所以它只在有人手動跑的時候咬人——而手動跑正是判定那一站
# 的量測會做的事。
resolve_workspace_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.claude/skills" ]] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}
WORKSPACE=""
TEMPLATE=""
SOURCE="workspace"
FORMAT="summary"
BLOCKING=0

usage() {
  cat >&2 <<'EOF'
usage: scan-template-leaks.sh [options]

Options:
  --workspace <path>   Workspace instance root (default: nearest ancestor with .claude/skills)
  --template <path>    Polaris template root (required for --source template)
  --source <mode>      workspace | template | both (default: workspace)
  --format <mode>      summary | markdown | json (default: summary)
  --blocking           Exit 1 when material leak hits exist
  --only-path <rel>    Limit the scan to this repo-relative path (repeatable)
  -h, --help           Show help
EOF
}

ONLY_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --template) TEMPLATE="${2:-}"; shift 2 ;;
    --source) SOURCE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --blocking) BLOCKING=1; shift ;;
    --only-path) ONLY_PATHS+=("${2:-}"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scan-template-leaks: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$WORKSPACE" ]]; then
  WORKSPACE="$(resolve_workspace_root)" || {
    echo "POLARIS_TEMPLATE_LEAK_SCAN_NO_ROOT" >&2
    echo "scan-template-leaks: 從 $SCRIPT_DIR 往上找不到帶 .claude/skills 的工作區根。" >&2
    echo "scan-template-leaks: 拿一個猜出來的根去掃會掃到 0 個檔案，而那個 0 讀起來像乾淨。修法：帶 --workspace <工作區根>。" >&2
    exit 2
  }
fi

python3 - "$WORKSPACE" "$TEMPLATE" "$SOURCE" "$FORMAT" "$BLOCKING" "${ONLY_PATHS[@]+"${ONLY_PATHS[@]}"}" <<'PY'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as exc:
    print(f"scan-template-leaks: PyYAML is required: {exc}", file=sys.stderr)
    sys.exit(2)

workspace = Path(sys.argv[1]).expanduser().resolve()
template_arg = sys.argv[2]
template = Path(template_arg).expanduser().resolve() if template_arg else None
source_mode = sys.argv[3]
output_format = sys.argv[4]
blocking = sys.argv[5] == "1"
only_paths = {p for p in sys.argv[6:] if p}

if source_mode not in {"workspace", "template", "both"}:
    print("scan-template-leaks: --source must be workspace, template, or both", file=sys.stderr)
    sys.exit(2)
if output_format not in {"summary", "markdown", "json"}:
    print("scan-template-leaks: --format must be summary, markdown, or json", file=sys.stderr)
    sys.exit(2)
if not workspace.exists():
    print(f"scan-template-leaks: workspace not found: {workspace}", file=sys.stderr)
    sys.exit(2)
if source_mode in {"template", "both"} and (template is None or not template.exists()):
    print("scan-template-leaks: --template is required for template source scan", file=sys.stderr)
    sys.exit(2)


def load_company_configs(root: Path):
    configs = []
    for child in sorted(root.iterdir()):
        if not child.is_dir():
            continue
        if child.name.startswith("_"):
            continue
        cfg = child / "workspace-config.yaml"
        if cfg.exists():
            configs.append((child.name, cfg))
    return configs


def load_company_configs_from_git_worktrees(root: Path):
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, OSError):
        return []
    if proc.returncode != 0:
        return []

    roots = []
    for line in proc.stdout.splitlines():
        if not line.startswith("worktree "):
            continue
        candidate = Path(line.split(" ", 1)[1]).expanduser()
        try:
            candidate = candidate.resolve()
        except OSError:
            continue
        if candidate == root:
            continue
        roots.append(candidate)

    for candidate in roots:
        if not candidate.exists():
            continue
        configs = load_company_configs(candidate)
        if configs:
            return configs
    return []


def collect_patterns(root: Path):
    patterns = []
    companies = []
    configs = load_company_configs(root)
    if not configs and source_mode == "workspace":
        configs = load_company_configs_from_git_worktrees(root)
    for company, cfg_path in configs:
        companies.append(company)
        patterns.append({
            "label": f"company-slug:{company}",
            "regex": rf"(?i)(?<![A-Za-z0-9_]){re.escape(company)}(?![A-Za-z0-9_])",
            "raw": company,
        })
        try:
            data = yaml.safe_load(cfg_path.read_text()) or {}
        except Exception:
            continue

        for project in (data.get("jira") or {}).get("projects") or []:
            key = str(project.get("key") or "").strip()
            if len(key) >= 2:
                patterns.append({
                    "label": f"jira:{key}",
                    "regex": rf"{re.escape(key)}-[0-9]+",
                    "raw": f"{key}-[0-9]+",
                })

        web_urls = data.get("web_urls") or {}
        for value in web_urls.values():
            if not isinstance(value, str) or "." not in value:
                continue
            match = re.search(r"://([^/]+)", value)
            if match:
                domain = match.group(1)
                patterns.append({
                    "label": f"domain:{domain}",
                    "regex": re.escape(domain),
                    "raw": domain,
                })

        jira_instance = str((data.get("jira") or {}).get("instance") or "").strip()
        if jira_instance:
            patterns.append({
                "label": f"jira-instance:{jira_instance}",
                "regex": re.escape(jira_instance),
                "raw": jira_instance,
            })

        channels = (data.get("slack") or {}).get("channels") or {}
        for value in channels.values():
            if isinstance(value, str) and value.startswith("C"):
                patterns.append({
                    "label": f"slack:{value}",
                    "regex": re.escape(value),
                    "raw": value,
                })

        org = str((data.get("github") or {}).get("org") or "").strip()
        if org:
            patterns.append({
                "label": f"github-org:{org}",
                "regex": re.escape(org),
                "raw": org,
            })

    deduped = {}
    for item in patterns:
        deduped[(item["label"], item["regex"])] = item
    return list(deduped.values()), companies


patterns, companies = collect_patterns(workspace)


def declared_no_companies(root: Path) -> bool:
    """根目錄那份 workspace-config.yaml 有沒有明講「這裡按設計沒有公司」。

    宣告放在那一份是因為**它不會被同步出去**（gitignored）。放進任何一支 skill 的話，
    這個工作區的宣告會跟著跑到 template，而一份寫著公司名的宣告本身就是一次外洩。
    """
    cfg = root / "workspace-config.yaml"
    if not cfg.exists():
        return False
    try:
        data = yaml.safe_load(cfg.read_text()) or {}
    except Exception:
        return False
    return data.get("companies") == "none"


# 樣式是空的時候，這一趟什麼都沒量到。它跟「量過了、乾淨」在輸出與結束狀態上必須不一樣
# ——2026-08-10 之前兩者都是 exit 0 加一行 `hits: 0`，而消費它的 gate-template-leaks 兩種
# 都印 ✅。一個掃不到東西而回綠的掃描，跟一個掃過了沒問題的掃描長得一樣，是這道閘失效
# 最安靜的方式。
#
# 走得完的那一條路是宣告，不是零這個數字：一個剛 clone 下來的 template 按設計就沒有公司，
# 它在自己的 workspace-config.yaml 裡說出來。反過來，把公司目錄刪掉讓樣式變空**買不到綠**，
# 因為這個工作區的那份設定不會憑空長出那句宣告。
NO_COMPANIES_DECLARED = declared_no_companies(workspace)
if companies and NO_COMPANIES_DECLARED:
    print("scan-template-leaks: workspace-config.yaml 宣告 `companies: none`，"
          f"但實際解出 {', '.join(companies)}。宣告與實際對不上，掃描不判定。",
          file=sys.stderr)
    sys.exit(2)
if not patterns and not NO_COMPANIES_DECLARED:
    print("POLARIS_TEMPLATE_LEAK_SCAN_VACUOUS", file=sys.stderr)
    print("scan-template-leaks: 一個樣式都沒有——這一趟什麼都沒掃，不是掃過而且乾淨。",
          file=sys.stderr)
    print(f"scan-template-leaks: 修法：{workspace} 底下要有 {{公司}}/workspace-config.yaml；"
          "這個環境按設計就沒有公司的話，在根目錄的 workspace-config.yaml 寫 `companies: none`。",
          file=sys.stderr)
    sys.exit(2)

compiled = [(item, re.compile(item["regex"])) for item in patterns]
ACTIVE_DP_PATH_RE = re.compile(r"docs-manager/src/content/docs/specs/design-plans/(?!archive/)(DP-[0-9]{3,}[^\\s'\"`)]*)")

TEXT_SUFFIXES = {
    ".md", ".mdx", ".sh", ".py", ".js", ".mjs", ".cjs", ".ts", ".tsx",
    ".json", ".yaml", ".yml", ".txt", ".example", ".toml",
}
TEXT_NAMES = {"CLAUDE.md", "README.md", "README.zh-TW.md", "VERSION", "CHANGELOG.md", "AGENTS.md"}


def is_text_file(path: Path):
    return path.name in TEXT_NAMES or path.suffix in TEXT_SUFFIXES


def skill_scope(root: Path, skill_name: str):
    """Read what a skill declares its scope to be.

    Returns the declared scope string, or "" when the skill has no SKILL.md, no
    frontmatter, or no scope line. Callers compare against a specific scope
    rather than inferring one from where the directory sits: company skills used
    to be identified by living under .claude/skills/{company}/, a depth the
    runtime never registers, so the path could not be both the exclusion key and
    a reachable location.
    """
    skill_md = root / ".claude" / "skills" / skill_name / "SKILL.md"
    if not skill_md.exists():
        return ""
    try:
        text = skill_md.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""
    frontmatter = text.split("---", 2)
    if len(frontmatter) < 3:
        return ""
    # Indentation-tolerant: scope may be declared at the top level or nested
    # under metadata:, and both are in use.
    match = re.search(r"(?m)^\s*scope:\s*(\S+)\s*$", frontmatter[1])
    return match.group(1) if match else ""


def resolve_gitignored(root: Path, rel_paths):
    """Return the subset of rel_paths that git considers ignored.

    DP-305 D5: uses `git check-ignore --stdin` so any git-ignored local
    session-state file (e.g. .claude/active-thread.md) is auto-exempt from the
    scan, replacing per-path hardcoded exception lists. Tracked files are never
    returned here, so tracked-file leak detection stays fail-closed (AC-NEG3).

    Fails open (returns empty set) when the workspace is not a git repo or git
    is unavailable: the scanner then keeps its non-gitignore skip rules, and no
    legitimate leak is silently dropped.
    """
    rel_paths = list(rel_paths)
    if not rel_paths:
        return set()
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "--stdin"],
            input="\n".join(rel_paths) + "\n",
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, OSError):
        return set()
    # git check-ignore exits 0 (some ignored), 1 (none ignored), 128 (error,
    # e.g. not a git repo). Only 0/1 carry a usable path list on stdout.
    if proc.returncode not in (0, 1):
        return set()
    return {line.strip() for line in proc.stdout.splitlines() if line.strip()}


def skip_path(root: Path, path: Path, source_name: str, gitignored=frozenset()):
    rel = path.relative_to(root).as_posix()
    parts = rel.split("/")
    if any(part in {".git", "node_modules", "dist", ".astro", "e2e-results", "test-results"} for part in parts):
        return True
    # DP-303 T3 (AC4): gitignore is the SINGLE source of truth for the
    # "does NOT sync" runtime-state set. sync-to-polaris.sh never copies
    # gitignored files, so any gitignored path (e.g. .claude/active-thread.md,
    # .claude/settings.local.json, .claude/polaris-backlog.md,
    # .claude/checkpoints/**, .claude/worktrees/**, workspace-config.yaml,
    # docs-manager/src/content/docs/specs/**) is exempt here via this one
    # check — no parallel hardcoded path list that could drift from .gitignore.
    # Tracked files never appear in this set, so tracked-file leak detection
    # stays fail-closed (a runtime-state file that is NOT gitignored is still
    # scanned, because sync would copy it). DP-305 D5 established the gitignore
    # mechanism; DP-303 T3 removed the redundant duplicate skip entries.
    if rel in gitignored:
        return True
    if rel == "scripts/selftests/scan-template-leaks-selftest.sh":
        return True
    # DP-230 D21: workspace-owned selftest fixtures legitimately stage live
    # company-shaped slugs (JIRA prefixes, repo names) to exercise downstream
    # validators. Carve out the fixture subtree so authored test inputs do not
    # block sync-to-polaris while still flagging the same prefix anywhere
    # outside the fixture path.
    if rel.startswith("scripts/selftests/fixtures/"):
        return True
    # 一個目錄要能限得住整棵子樹。只比全等的話，`--only-path .claude/skills/swe-knowledge`
    # 一個檔案都比不到而回 0 hits——那個綠只代表沒有任何檔案叫那個名字。
    if only_paths and not any(
            rel == p or rel.startswith(p.rstrip("/") + "/") for p in only_paths):
        return True
    if rel.startswith(".agents/skills"):
        return True
    # The company carve-outs mirror the sync copy set, same as the gitignore rule
    # above: sync copies .claude/rules/*.md at one level only and skips skills
    # declaring company-only, so neither surface can reach the template no matter
    # where the delivery is headed. v3.85.0 made these conditional on the delivery
    # destination, on the reasoning that a template-bound source invalidates them.
    # Measured afterwards, that reasoning was wrong: the set of paths sync copies
    # and the set carved out here do not intersect, and sync re-scans the template
    # tree itself after copying. The condition only ever produced false positives
    # on a delivery that legitimately touched company files, so it is gone.
    if rel.startswith(".claude/skills/"):
        # Resolve through the owning skill, not through the directory's name. A
        # skill lives either at .claude/skills/{name}/ or, under the repo's
        # namespace convention, at .claude/skills/{ns}/{name}/ — and the files
        # that sit beside SKILL.md (scripts, references, fixtures) declare
        # nothing themselves, so their scope has to come from the skill that
        # owns them. Asking "is this directory named after a company" would put
        # the answer back in the path, which is what broke the last time the
        # layout moved.
        for depth in (2, 3):
            if len(parts) > depth:
                scope = skill_scope(root, "/".join(parts[2:depth + 1]))
                if scope in {"maintainer-only", "company-only"}:
                    return True
    if rel.startswith(".claude/rules/"):
        rule_scope = parts[2] if len(parts) > 2 else ""
        if rule_scope in companies:
            return True
        if len(parts) > 3:
            return True
    if rel.startswith("docs-manager/src/content/docs/specs/"):
        return True
    return False


def scan_roots(root: Path, source_name: str):
    candidates = [
        ".claude",
        ".codex",
        ".github",
        "scripts",
        "docs",
        "docs-manager",
        "_template",
        "CLAUDE.md",
        "AGENTS.md",
        "README.md",
        "README.zh-TW.md",
        "CHANGELOG.md",
    ]
    # Gather text-file candidates first (cheap path/suffix filters only), then
    # resolve git-ignored paths in a single batched `git check-ignore` call so
    # DP-305 D5 gitignore-aware skip stays O(1) git invocations per root.
    candidate_files = []
    for rel in candidates:
        item = root / rel
        if not item.exists():
            continue
        if item.is_file():
            if is_text_file(item):
                candidate_files.append(item)
            continue
        for path in item.rglob("*"):
            if path.is_file() and is_text_file(path):
                candidate_files.append(path)

    gitignored = resolve_gitignored(
        root, [p.relative_to(root).as_posix() for p in candidate_files]
    )

    files = [
        p
        for p in candidate_files
        if not skip_path(root, p, source_name, gitignored)
    ]
    return sorted(set(files))


def classify(rel: str, line: str, labels):
    if any(label.startswith("framework-dp-active-path:") for label in labels):
        return "framework-context-leak", "use-synthetic-fixture-or-active-archive-resolver"
    if "cross-session-learnings" in rel or "review-lesson" in line or '"company"' in line:
        return "real-company-lesson", "anonymize-or-move-to-company-surface"
    if "genericize" in rel:
        return "company-config-leak", "replace-source-or-map"
    if "regex" in line.lower() or "pattern" in line.lower() or "grep" in line.lower():
        return "false-positive-candidate", "prefer-abstract-regex-or-allowlist"
    return "example-placeholder", "replace-with-neutral-placeholder"


def framework_context_labels(rel: str, line: str):
    if not rel.startswith("scripts/"):
        return []
    # DP-216: selftest fixtures legitimately reference placeholder DP slugs
    # (e.g. DP-999, DP-NNN) for synthetic test inputs. Path-based skip avoids
    # false-positive blocking sync-to-polaris when a selftest builds fake
    # docs-manager paths. Real DP slugs in non-selftest scripts are still flagged.
    if "/selftests/" in rel or rel.endswith("-selftest.sh"):
        return []
    labels = []
    for match in ACTIVE_DP_PATH_RE.finditer(line):
        prefix = line[max(0, match.start() - 48):match.start()]
        if "$" in prefix or "tmp" in prefix.lower() or "fixture" in prefix.lower():
            continue
        slug = match.group(1).split("/")[0]
        if re.search(r"(fixture|example|demo|selftest|proof|sample|parity|completion|finalize|closeout|follow-up)", slug, re.I):
            continue
        # DP-216: placeholder DP slug enum used in non-selftest spec docs
        if slug.upper() in {"DP-999", "DP-NNN", "DP-XXX", "DP-000"}:
            continue
        labels.append(f"framework-dp-active-path:{slug}")
    return labels


scanned = {}


def scan_source(root: Path, source_name: str):
    hits = []
    files = scan_roots(root, source_name)
    # 掃了幾個檔案是這一趟與「什麼都沒掃」唯一的差別——0 hits 與 0 個檔案在輸出上長得一樣，
    # 而後者是一個假的綠。這個數字每一趟都印，綠的那一趟也印。
    scanned[source_name] = len(files)
    for file_path in files:
        rel = file_path.relative_to(root).as_posix()
        path_labels = [item["label"] for item, regex in compiled if regex.search(rel)]
        if path_labels:
            classification, action = classify(rel, rel, path_labels)
            hits.append({
                "source": source_name,
                "file": rel,
                "line": 0,
                "patterns": sorted(set(path_labels)),
                "classification": classification,
                "action": "rename-path-or-move-out-of-template",
                "text": rel,
            })
        try:
            text = file_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for line_no, line in enumerate(text.splitlines(), 1):
            labels = [item["label"] for item, regex in compiled if regex.search(line)]
            labels.extend(framework_context_labels(rel, line))
            if not labels:
                continue
            classification, action = classify(rel, line, labels)
            hits.append({
                "source": source_name,
                "file": rel,
                "line": line_no,
                "patterns": sorted(set(labels)),
                "classification": classification,
                "action": action,
                "text": line.strip(),
            })
    return hits


hits = []
if source_mode in {"workspace", "both"}:
    hits.extend(scan_source(workspace, "workspace"))
if source_mode in {"template", "both"}:
    hits.extend(scan_source(template, "template"))

total_scanned = sum(scanned.values())
scanned_detail = ", ".join(f"{name} {count}" for name, count in scanned.items())

# 第二個空掃軸。第一個是零樣式（上面那一段），這一個是零檔案：範圍限到一個不存在的路徑、
# 或根解錯，都會走到這裡。兩者的共同點是 `hits: 0` 加 exit 0——跟一趟掃過而且乾淨的執行
# 完全相同。
if total_scanned == 0:
    print("POLARIS_TEMPLATE_LEAK_SCAN_NO_FILES", file=sys.stderr)
    print("scan-template-leaks: 一個檔案都沒掃到——這一趟什麼都沒讀，不是讀過而且乾淨。",
          file=sys.stderr)
    print(f"scan-template-leaks: 掃的根是 {workspace}"
          + (f"；範圍限在 {', '.join(sorted(only_paths))}" if only_paths else "")
          + "。", file=sys.stderr)
    print("scan-template-leaks: 修法：確認 --workspace 指的是工作區根，"
          "以及 --only-path 指的路徑真的存在。", file=sys.stderr)
    sys.exit(2)


def emit_summary():
    print("Template leak scan")
    print(f"source: {source_mode}")
    print(f"workspace: {workspace}")
    if template:
        print(f"template: {template}")
    print(f"companies: {', '.join(companies) if companies else 'none'}")
    print(f"patterns: {', '.join(item['raw'] for item in patterns) if patterns else 'none'}")
    print(f"scanned: {total_scanned}" + (f" ({scanned_detail})" if len(scanned) > 1 else ""))
    print(f"hits: {len(hits)}")
    if not patterns:
        # 這一行是這一趟與「量過了、乾淨」唯一的差別，除了它不會有 hits 之外。讀的人不需要
        # 知道這支腳本怎麼寫也分得出來是哪一種。
        print("note: 零樣式，由 workspace-config.yaml 的 `companies: none` 宣告放行——"
              "這一趟沒有量任何東西。")
    if hits:
        by_pattern = {}
        by_file = {}
        by_class = {}
        for hit in hits:
            by_file[f"{hit['source']}:{hit['file']}"] = by_file.get(f"{hit['source']}:{hit['file']}", 0) + 1
            by_class[hit["classification"]] = by_class.get(hit["classification"], 0) + 1
            for label in hit["patterns"]:
                by_pattern[label] = by_pattern.get(label, 0) + 1
        print("\nby pattern:")
        for key, count in sorted(by_pattern.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {count:4} {key}")
        print("\nby classification:")
        for key, count in sorted(by_class.items(), key=lambda item: (-item[1], item[0])):
            print(f"  {count:4} {key}")
        print("\ntop files:")
        for key, count in sorted(by_file.items(), key=lambda item: (-item[1], item[0]))[:20]:
            print(f"  {count:4} {key}")
        print("\nexamples:")
        for hit in hits[:20]:
            print(f"  {hit['source']}:{hit['file']}:{hit['line']} [{','.join(hit['patterns'])}] {hit['text'][:160]}")


def emit_markdown():
    print("# Template Leak Scan")
    print()
    print(f"- Source: `{source_mode}`")
    print(f"- Workspace: `{workspace}`")
    if template:
        print(f"- Template: `{template}`")
    print(f"- Companies: `{', '.join(companies) if companies else 'none'}`")
    print(f"- Scanned: `{total_scanned}`")
    print(f"- Hits: `{len(hits)}`")
    print()
    print("| Source | File | Line | Patterns | Class | Action | Text |")
    print("|--------|------|------|----------|-------|--------|------|")
    for hit in hits:
        text = hit["text"].replace("|", "\\|")
        print(f"| {hit['source']} | `{hit['file']}` | {hit['line']} | `{', '.join(hit['patterns'])}` | `{hit['classification']}` | `{hit['action']}` | {text} |")


if output_format == "json":
    print(json.dumps({"patterns": patterns, "companies": companies,
                      "scanned": scanned, "hits": hits}, indent=2, ensure_ascii=False))
elif output_format == "markdown":
    emit_markdown()
else:
    emit_summary()

if blocking and hits:
    # DP-230 D21: stable structured token so PR-time / push-time gates can
    # surface this signal in CI logs without parsing the prose summary.
    print(f"POLARIS_TEMPLATE_LEAK: {len(hits)} hit(s)", file=sys.stderr)
    print(f"scan-template-leaks: BLOCKED: {len(hits)} material leak hit(s)", file=sys.stderr)
    sys.exit(1)
PY
