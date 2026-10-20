#!/usr/bin/env bash
# ==============================================================================
# ConstructAMe Test Runner with Per-Test Timeouts & Hang Prevention
# ==============================================================================

set -uo pipefail

GODOT_BIN="/home/agy1/.gemini/antigravity-cli/bin/godot"
TIMEOUT_SEC=15
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_DIR"

if [ ! -x "$GODOT_BIN" ]; then
    echo "ERROR: Godot binary not found at $GODOT_BIN"
    exit 1
fi

SPECIFIC_TEST="${1:-}"

if [ -n "$SPECIFIC_TEST" ]; then
    TESTS=("$SPECIFIC_TEST")
else
    TESTS=($(ls -1 scripts/core/test_*.gd | sort))
fi

TOTAL=${#TESTS[@]}
PASSED=0
FAILED=0
FAILED_NAMES=()

echo "=========================================================="
echo "  Running ConstructAMe Test Suite (${TOTAL} suites)"
echo "  Per-test timeout: ${TIMEOUT_SEC}s"
echo "=========================================================="

for test in "${TESTS[@]}"; do
    START_TS=$(date +%s%N)
    OUTPUT=$(timeout --kill-after=2s "${TIMEOUT_SEC}s" "$GODOT_BIN" --headless -s "$test" 2>&1)
    RET=$?
    END_TS=$(date +%s%N)
    DURATION=$(awk "BEGIN {printf \"%.2f\", ($END_TS - $START_TS) / 1000000000}")

    if [ $RET -eq 124 ]; then
        echo "✗ [TIMEOUT] $test (${DURATION}s - exceeded ${TIMEOUT_SEC}s)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$test (TIMEOUT)")
    elif [ $RET -ne 0 ]; then
        echo "✗ [FAIL]    $test (${DURATION}s, exit $RET)"
        echo "$OUTPUT" | tail -n 12
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$test (EXIT $RET)")
    else
        echo "✓ [PASS]    $test (${DURATION}s)"
        PASSED=$((PASSED + 1))
    fi
done

echo "=========================================================="
echo "  Test Summary: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "=========================================================="

if [ $FAILED -gt 0 ]; then
    echo "Failed suites:"
    for name in "${FAILED_NAMES[@]}"; do
        echo "  - $name"
    done
    exit 1
else
    echo "All tests passed successfully!"
    exit 0
fi
