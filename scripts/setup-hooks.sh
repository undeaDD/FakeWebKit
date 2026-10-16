#!/bin/zsh
# Enables the git hooks from .githooks/ for this clone (run once after cloning).
set -euo pipefail
cd "${0:A:h:h}"
chmod +x .githooks/* scripts/*.sh scripts/check_text.py
git config core.hooksPath .githooks
print "ok Git hooks active: pre-commit (text rules, SwiftLint, tests), commit-msg (message rules)"
