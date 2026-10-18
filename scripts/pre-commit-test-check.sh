#!/bin/bash

# pre-commit-test-check.sh
# Optional pre-commit hook: warns when staged files under MemoriesIOS/Sources/ have no
# matching test file (MemoriesIOS/Tests/<Folder>/<Name>Tests.swift), and fails when
# a staged source file has no test file at all.
#
# Install: ln -sf ../../scripts/pre-commit-test-check.sh .git/hooks/pre-commit

set -euo pipefail

SOURCES_DIR="MemoriesIOS/Sources/"
TESTS_DIR="MemoriesIOS/Tests/"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# `|| true`: grep exits 1 when nothing matches, which is not an error here.
STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.swift$' || true)
SOURCES=$(echo "$STAGED" | grep "^$SOURCES_DIR" || true)

if [ -z "$SOURCES" ]; then
    exit 0
fi

ERRORS=0
WARNINGS=0

while read -r source_file; do
    relative=${source_file#"$SOURCES_DIR"}
    test_file="$TESTS_DIR${relative%.swift}Tests.swift"

    if echo "$STAGED" | grep -qxF "$test_file"; then
        echo -e "${GREEN}✓ $source_file: test updated${NC}"
    elif [ -f "$test_file" ]; then
        echo -e "${YELLOW}⚠ $source_file: $test_file exists but is not staged${NC}"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${RED}✗ $source_file: no test file ($test_file)${NC}"
        ERRORS=$((ERRORS + 1))
    fi
done <<< "$SOURCES"

if [ "$ERRORS" -gt 0 ]; then
    echo -e "${RED}$ERRORS source file(s) without tests. Add them, or commit with --no-verify if the code is not unit-testable.${NC}"
    exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
    echo -e "${YELLOW}$WARNINGS source file(s) changed without test changes: check the tests still cover them.${NC}"
fi
exit 0
