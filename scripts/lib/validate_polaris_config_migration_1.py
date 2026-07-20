"""Validate closure of the workspace-owned polaris-config migration."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
VALIDATOR_PATHS = {
    Path("scripts/validate-polaris-config-migration.sh"),
    Path("scripts/lib/validate_polaris_config_migration_1.py"),
}
SEARCH_EXCLUDED_PARTS = {"node_modules", ".git", ".worktrees"}


class MigrationValidator:
    """Collect every migration closure violation before returning."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.failures = 0

    def fail(self, message: str) -> None:
        """Record and emit one legacy failure line."""
        print(f"[polaris-config-migration] FAIL: {message}", file=sys.stderr)
        self.failures += 1

    @staticmethod
    def info(message: str) -> None:
        """Emit one legacy informational line."""
        print(f"[polaris-config-migration] {message}", file=sys.stderr)

    def depth_two_entries(self, name: str, *, directories: bool) -> list[Path]:
        """Match find -mindepth 2 -maxdepth 2 for files or directories."""
        entries: list[Path] = []
        try:
            first_level = sorted(self.root.iterdir(), key=lambda path: str(path))
        except OSError:
            return entries
        for parent in first_level:
            if not parent.is_dir() or parent.name in {".git", ".worktrees"}:
                continue
            if parent == self.root / ".claude" / "worktrees":
                continue
            try:
                children = sorted(parent.iterdir(), key=lambda path: str(path))
            except OSError:
                continue
            for child in children:
                if child.name != name:
                    continue
                if directories and child.is_dir():
                    entries.append(child)
                elif not directories and child.is_file():
                    entries.append(child)
        return entries

    def workspace_configs(self) -> list[Path]:
        """Return active depth-two workspace configs, excluding template config."""
        return [
            path
            for path in self.depth_two_entries("workspace-config.yaml", directories=False)
            if path.parent.name != "_template"
        ]

    def active_targets(self, include_configs: bool) -> list[Path]:
        """Return the same runtime surfaces scanned by the legacy rg command."""
        targets = [
            self.root / "CLAUDE.md",
            self.root / "AGENTS.md",
            self.root / ".codex",
            self.root / ".github",
            self.root / ".claude" / "instructions",
            self.root / ".claude" / "hooks",
            self.root / ".claude" / "rules",
            self.root / ".claude" / "skills",
            self.root / "scripts",
            self.root / "README.md",
            self.root / "README.zh-TW.md",
        ]
        if include_configs:
            targets.extend(self.workspace_configs())
        return targets

    def iter_target_files(self, targets: list[Path]) -> list[Path]:
        """Enumerate target files without following ignored runtime trees."""
        files: list[Path] = []
        seen: set[Path] = set()
        for target in targets:
            if target.is_file():
                resolved = target.resolve()
                if resolved not in seen:
                    seen.add(resolved)
                    files.append(target)
                continue
            if not target.is_dir():
                continue
            for directory, dir_names, file_names in os.walk(target, followlinks=False):
                directory_path = Path(directory)
                try:
                    relative_directory = directory_path.relative_to(self.root)
                except ValueError:
                    relative_directory = directory_path
                dir_names[:] = sorted(
                    name
                    for name in dir_names
                    if name not in SEARCH_EXCLUDED_PARTS
                    and not (
                        relative_directory == Path(".claude") and name == "worktrees"
                    )
                )
                for file_name in sorted(file_names):
                    path = directory_path / file_name
                    resolved = path.resolve()
                    if resolved not in seen:
                        seen.add(resolved)
                        files.append(path)
        return files

    def search(self, pattern: re.Pattern[str], *, include_configs: bool) -> list[str]:
        """Search active text files and return rg-compatible hit rows."""
        hits: list[str] = []
        for path in self.iter_target_files(self.active_targets(include_configs)):
            try:
                relative = path.relative_to(self.root)
            except ValueError:
                relative = path
            if relative in VALIDATOR_PATHS:
                continue
            try:
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            for line_number, line in enumerate(lines, 1):
                if pattern.search(line):
                    hits.append(f"{path}:{line_number}:{line}")
        return hits

    def git(self, *args: str) -> subprocess.CompletedProcess[str]:
        """Run a repository-scoped Git query without invoking a shell."""
        return subprocess.run(
            ["git", "-C", str(self.root), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def git_for_repo(self, repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
        """Run a Git query against a discovered product repository."""
        return subprocess.run(
            ["git", "-C", str(repo), *args],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def check_no_ai_config_root(self) -> None:
        """Reject legacy company/ai-config directories."""
        legacy = self.depth_two_entries("ai-config", directories=True)
        if legacy:
            self.fail(f"legacy ai-config directories remain: {' '.join(map(str, legacy))}")

    def check_no_active_ai_config_references(self) -> None:
        """Reject active runtime references to the legacy config name."""
        hits = self.search(re.compile(r"ai-config"), include_configs=True)
        if hits:
            self.fail("active runtime files still reference ai-config:")
            print("\n".join(hits), file=sys.stderr)

    def check_no_runtime_polaris_sync_references(self) -> None:
        """Reject active runtime references to the transitional sync script."""
        hits = self.search(re.compile(r"polaris-sync\.sh"), include_configs=False)
        if hits:
            self.fail("active runtime files still reference transitional polaris-sync.sh:")
            print("\n".join(hits), file=sys.stderr)

    def check_polaris_config_git_policy(self) -> None:
        """Require local polaris-config directories to be ignored and untracked."""
        tracked_result = self.git(
            "ls-files", "--", "*/polaris-config", "*/polaris-config/*"
        )
        tracked = [
            line
            for line in tracked_result.stdout.splitlines()
            if line and not line.startswith("scripts/fixtures/")
        ]
        if tracked:
            self.fail("polaris-config must be local-only and not git tracked:")
            print("\n".join(tracked), file=sys.stderr)

        for directory in self.depth_two_entries("polaris-config", directories=True):
            relative = str(directory.relative_to(self.root))
            ignored = self.git("check-ignore", "-q", relative)
            if ignored.returncode != 0:
                self.fail(f"polaris-config directory is not ignored: {relative}")

    def company_dirs(self) -> list[Path]:
        """Return company roots discovered from active workspace configs."""
        return sorted({config.parent for config in self.workspace_configs()}, key=str)

    def check_company_dir_git_policy(self) -> None:
        """Require discovered company roots to remain local-only and ignored."""
        for company_dir in self.company_dirs():
            relative = str(company_dir.relative_to(self.root))
            tracked_result = self.git("ls-files", "--", relative, f"{relative}/*")
            tracked = tracked_result.stdout.strip()
            if tracked:
                self.fail(
                    f"company directory must be local-only and not git tracked: {relative}"
                )
                print(tracked, file=sys.stderr)
            ignored = self.git("check-ignore", "-q", relative)
            if ignored.returncode != 0:
                self.fail(f"company directory is not ignored: {relative}")

    @staticmethod
    def projects_from_config(config: Path) -> list[str]:
        """Parse the legacy projects/name YAML subset without adding a YAML dependency."""
        projects: list[str] = []
        in_projects = False
        for line in config.read_text(encoding="utf-8").splitlines():
            if line == "projects:":
                in_projects = True
                continue
            if re.match(r"^[a-z_]+:", line) and not line.startswith("  "):
                in_projects = False
            if not in_projects:
                continue
            match = re.match(r'^  - name:\s*"?([^"\n]+?)"?\s*$', line)
            if match:
                projects.append(match.group(1))
        return projects

    def ignored_in_repo(self, repo: Path, relative: str) -> bool:
        """Return whether an existing repo-local artifact is ignored."""
        if not (repo / relative).exists():
            return False
        result = self.git_for_repo(repo, "check-ignore", "-q", relative)
        return result.returncode == 0

    def check_company_config(self, company_dir: Path) -> None:
        """Validate one active company's product-repo migration state."""
        config = company_dir / "workspace-config.yaml"
        if not config.is_file():
            return
        for project in self.projects_from_config(config):
            repo = company_dir / project
            source_of_truth = company_dir / "polaris-config" / project
            if not (repo / ".git").is_dir():
                continue
            if not source_of_truth.is_dir():
                self.fail(f"{project} has no workspace-owned polaris-config directory")
            if self.ignored_in_repo(repo, ".claude/rules/handbook"):
                self.fail(
                    f"{project} still has ignored repo-local handbook overlay: "
                    f"{repo}/.claude/rules/handbook"
                )
            if self.ignored_in_repo(repo, ".claude/scripts/ci-local.sh"):
                self.fail(
                    f"{project} still has ignored repo-local ci-local legacy script: "
                    f"{repo}/.claude/scripts/ci-local.sh"
                )
            if self.ignored_in_repo(repo, ".claude/settings.local.json"):
                self.fail(
                    f"{project} still has ignored repo-local settings overlay: "
                    f"{repo}/.claude/settings.local.json"
                )
            skills = repo / ".claude" / "skills"
            if skills.is_dir() and self.ignored_in_repo(repo, ".claude/skills"):
                self.fail(
                    f"{project} still has ignored repo-local skills overlay: {skills}"
                )
            legacy_ci = repo / ".claude" / "scripts" / "ci-local.sh"
            canonical_ci = source_of_truth / "generated-scripts" / "ci-local.sh"
            if legacy_ci.is_file() and not canonical_ci.is_file():
                self.fail(f"{project} has legacy ci-local without canonical generated script")

    def run(self) -> int:
        """Execute all migration closure checks."""
        self.check_no_ai_config_root()
        self.check_no_active_ai_config_references()
        self.check_no_runtime_polaris_sync_references()
        self.check_company_dir_git_policy()
        self.check_polaris_config_git_policy()
        for company_dir in self.company_dirs():
            self.check_company_config(company_dir)
        if self.failures:
            count = self.failures
            self.fail(f"{count} migration issue(s) detected")
            return 1
        self.info("PASS")
        return 0


def build_parser() -> argparse.ArgumentParser:
    """Build an argparse surface while retaining the legacy ignored-args behavior."""
    return argparse.ArgumentParser(add_help=False, allow_abbrev=False)


def main(argv: list[str]) -> int:
    """Run the polaris-config migration closure gate."""
    build_parser().parse_known_args(argv)
    return MigrationValidator(ROOT_DIR).run()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
