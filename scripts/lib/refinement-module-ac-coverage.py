#!/usr/bin/env python3
# Purpose: 驗證 refinement modules 已被 AC prose 或 task module intent fields 覆蓋，
#          且不讀取 task.md packaging fields。
# Inputs:  一個 refinement container path 或 refinement.json path。
# Outputs: module 未覆蓋時 stderr 輸出 POLARIS_MODULE_AC_MISSING；exit 0/2。
import sys
from pathlib import Path

from refinement_common import ac_blob, load_json, refinement_paths


def main():
    if len(sys.argv) != 2:
        print("usage: refinement-module-ac-coverage.py <container|refinement.json>", file=sys.stderr)
        return 2
    _, _, json_path = refinement_paths(sys.argv[1])
    data = load_json(json_path)
    blob = ac_blob(data).lower()
    task_blob = "\n".join(
        "\n".join(str(x) for x in (task.get("modules") or []))
        for task in data.get("tasks") or []
        if isinstance(task, dict)
    ).lower()
    missing = []
    for mod in data.get("modules") or []:
        if mod.get("action") not in {"create", "modify"}:
            continue
        p = str(mod.get("path") or "")
        if not p:
            continue
        token = Path(p).name.lower()
        if token and token not in blob and p.lower() not in blob and p.lower() not in task_blob:
            missing.append(p)
    if missing:
        print(f"POLARIS_MODULE_AC_MISSING: {', '.join(missing)}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
