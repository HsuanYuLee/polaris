#!/usr/bin/env bash
# compliant-sample.sh — fixture for validate-script-header-comment.sh.
#
# Purpose: demonstrate the minimum acceptable header comment for the D26
# multi-language script header gate. The validator scans the first 20 lines
# for at least one non-shebang `#` comment line with real content.
#
# This file MUST pass validate-script-header-comment.sh in diff and audit
# modes. Selftest references it; do not delete without updating the
# selftest matrix.

set -euo pipefail
echo "compliant sample (header present)"
