import hashlib
import json
import sys

try:
    data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
except Exception:
    sys.exit(0)

context = data.get("context") or {}
raw = "|".join(
    str(context.get(k) or "") for k in ("event", "base_branch", "source_branch", "ref")
)
context_hash = hashlib.sha1(raw.encode()).hexdigest()[:12]
print(
    "|".join(
        [
            str(data.get("branch") or ""),
            str(data.get("head_sha") or ""),
            context_hash,
        ]
    )
)
