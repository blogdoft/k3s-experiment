#!/usr/bin/env bash
# Aponta o git para os hooks versionados em .githooks/
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chmod +x .githooks/pre-commit
git config core.hooksPath .githooks
echo "core.hooksPath = .githooks (pre-commit com gitleaks ativo)"
