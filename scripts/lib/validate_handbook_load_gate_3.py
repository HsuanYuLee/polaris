"""Structured validator authority extracted from scripts/validate-handbook-load-gate.sh."""

import hashlib
import os
import sys

directory, repo, session = sys.argv[1:]
digest = hashlib.sha256((os.path.realpath(repo) + "\0" + session).encode()).hexdigest()[
    :24
]
print(os.path.join(directory, digest + ".json"))
