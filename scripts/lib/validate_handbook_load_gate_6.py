"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

import json
import os
import sys
import tempfile

path, repo, session, project, index = sys.argv[1:]
data = {
    "schema_version": 1,
    "marker_kind": "handbook_load",
    "repo": os.path.realpath(repo),
    "session_id": session,
    "project": project,
    "index_path": os.path.realpath(index),
}
directory = os.path.dirname(path)
fd, tmp = tempfile.mkstemp(prefix=".handbook-load.", dir=directory)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
