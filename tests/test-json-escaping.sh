#!/bin/bash

# Test JSON escaping in data generators
source tests/test-data-common.sh

echo "=== JSON Escaping Test ==="
echo "Testing JSON escaping in data generators..."

PASS_COUNT=0
FAIL_COUNT=0

# Test function
test_json_valid() {
    local test_name="$1"
    local json_data="$2"
    
    echo -n "$test_name: "
    if echo "$json_data" | jq . > /dev/null 2>&1; then
        echo "✅ PASSED"
        ((PASS_COUNT++))
    else
        echo "❌ FAILED"
        echo "  Invalid JSON: $json_data"
        ((FAIL_COUNT++))
    fi
}

# Test 1: User message with quotes
test_json_valid "User message with quotes" \
    "$(generate_user_message 'Hello "world"')"

# Test 2: User message with backslashes
test_json_valid "User message with backslashes" \
    "$(generate_user_message 'Path: C:\Users\test')"

# Test 3: User message with newlines
test_json_valid "User message with newlines" \
    "$(generate_user_message $'First line\nSecond line')"

# Test 4: User message with tabs
test_json_valid "User message with tabs" \
    "$(generate_user_message $'Column1\tColumn2')"

# Test 5: Bash command with quotes
test_json_valid "Bash command with grep quotes" \
    "$(generate_bash_command 'grep "Final Result:" output.txt' 'Search results')"

# Test 6: Bash command with mixed special chars
test_json_valid "Bash command with newlines and tabs" \
    "$(generate_bash_command $'echo "Line1\nLine2\tTabbed"' 'Multi-line echo')"

# Test 7: Complex sed command
test_json_valid "Complex sed command" \
    "$(generate_bash_command 'sed "s/\"/\\\"/g" file.txt' 'Escape quotes')"

# Test 8: Empty content
test_json_valid "Empty content" \
    "$(generate_user_message '')"

# Test 9: Carriage return
test_json_valid "Carriage return" \
    "$(generate_user_message $'Text\rWith CR')"

# Test 10: All control characters
test_json_valid "All control characters" \
    "$(generate_user_message $'"\\\n\r\t\f\b')"

echo ""
echo "=== Test Summary ==="
echo "Tests passed: $PASS_COUNT"
echo "Tests failed: $FAIL_COUNT"
echo "Total tests: $((PASS_COUNT + FAIL_COUNT))"

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 All JSON escaping tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi