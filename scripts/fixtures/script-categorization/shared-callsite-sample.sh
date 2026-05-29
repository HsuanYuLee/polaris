#!/usr/bin/env bash
# shared-callsite-sample.sh — fixture for validate-script-categorization.sh.
#
# Purpose: simulate a root script with consumers in two or more skills, so
# the categorization gate must classify it as `shared_reference_keep` (or
# `keep_root_with_reason`) and PASS.
#
# Selftest populates synthetic skill references pointing at this fixture
# from two different .claude/skills/{skill}/ paths.
set -euo pipefail
echo "shared callsite fixture"
