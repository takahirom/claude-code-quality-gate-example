#!/bin/bash

# Test suite for check-for-learnings.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/../scripts/check-for-learnings.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Create temp directory for test files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

run_test() {
    local name="$1"
    local input="$2"
    local expected_exit="$3"
    local expected_output="$4"  # optional, regex pattern

    TESTS_RUN=$((TESTS_RUN + 1))

    output=$(echo "$input" | "$SCRIPT_PATH" 2>&1)
    exit_code=$?

    local passed=true

    if [ "$exit_code" != "$expected_exit" ]; then
        passed=false
    fi

    if [ -n "$expected_output" ] && ! echo "$output" | grep -qE "$expected_output"; then
        passed=false
    fi

    if [ "$passed" = true ]; then
        echo -e "${GREEN}✓${NC} $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $name"
        echo "  Expected exit: $expected_exit, got: $exit_code"
        if [ -n "$expected_output" ]; then
            echo "  Expected output matching: $expected_output"
            echo "  Got: $output"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo "=== check-for-learnings.sh Tests ==="
echo ""

# Test 1: stop_hook_active is true → allow stop
run_test "stop_hook_active=true allows stop" \
    '{"stop_hook_active": true, "transcript_path": "/tmp/test.jsonl"}' \
    0 \
    ""

# Test 2: No transcript_path → allow stop
run_test "Missing transcript_path allows stop" \
    '{"stop_hook_active": false}' \
    0 \
    ""

# Test 3: Empty transcript_path → allow stop
run_test "Empty transcript_path allows stop" \
    '{"stop_hook_active": false, "transcript_path": ""}' \
    0 \
    ""

# Test 4: Non-existent transcript file → allow stop
run_test "Non-existent transcript file allows stop" \
    '{"stop_hook_active": false, "transcript_path": "/nonexistent/file.jsonl"}' \
    0 \
    ""

# Test 5: Short transcript (< 10 lines) → allow stop
SHORT_TRANSCRIPT="$TEMP_DIR/short.jsonl"
for i in {1..5}; do
    echo '{"type": "message"}' >> "$SHORT_TRANSCRIPT"
done

run_test "Short transcript (< 10 lines) allows stop" \
    "{\"stop_hook_active\": false, \"transcript_path\": \"$SHORT_TRANSCRIPT\"}" \
    0 \
    ""

# Test 6: Transcript already contains skill-extractor → allow stop
ALREADY_EXTRACTED="$TEMP_DIR/already.jsonl"
for i in {1..15}; do
    echo '{"type": "message"}' >> "$ALREADY_EXTRACTED"
done
echo '{"type": "tool_use", "name": "skill-extractor"}' >> "$ALREADY_EXTRACTED"

run_test "Transcript with skill-extractor already used allows stop" \
    "{\"stop_hook_active\": false, \"transcript_path\": \"$ALREADY_EXTRACTED\"}" \
    0 \
    ""

# Test 7: Long transcript without skill-extractor → block and suggest extraction
LONG_TRANSCRIPT="$TEMP_DIR/long.jsonl"
for i in {1..20}; do
    echo '{"type": "message", "content": "Some conversation"}' >> "$LONG_TRANSCRIPT"
done

run_test "Long transcript without skill-extractor blocks and suggests extraction" \
    "{\"stop_hook_active\": false, \"transcript_path\": \"$LONG_TRANSCRIPT\"}" \
    0 \
    '"decision":\s*"block"'

# Test 8: Verify block response contains reason
run_test "Block response contains reason" \
    "{\"stop_hook_active\": false, \"transcript_path\": \"$LONG_TRANSCRIPT\"}" \
    0 \
    '"reason":'

# Test 9: Verify block response contains transcript_path in reason
run_test "Block response includes transcript_path in reason" \
    "{\"stop_hook_active\": false, \"transcript_path\": \"$LONG_TRANSCRIPT\"}" \
    0 \
    "$LONG_TRANSCRIPT"

echo ""
echo "=== Results ==="
echo "Total: $TESTS_RUN, Passed: $TESTS_PASSED, Failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
