#!/bin/bash

# Test script for get_quality_result function
# Tests various scenarios for quality gate result parsing

set +e

# Source the common config to get the function
source ./.claude/scripts/common-config.sh

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper function
run_test() {
    local test_name="$1"
    local expected_result="$2"
    local test_file="$3"
    
    echo "Running test: $test_name"
    
    get_quality_result "$test_file"
    local actual_result=$?
    
    if [[ $actual_result -eq $expected_result ]]; then
        echo "✅ PASS: $test_name (expected: $expected_result, got: $actual_result)"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL: $test_name (expected: $expected_result, got: $actual_result)"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# Create test directory
mkdir -p test-data
cd test-data

echo "=== Testing get_quality_result function ==="
echo ""

# Test 1: Missing file
echo "Test 1: Missing file should return 2"
run_test "Missing file" 2 "nonexistent.jsonl"

# Test 2: Empty file
echo "Test 2: Empty file should return 2"
touch empty.jsonl
run_test "Empty file" 2 "empty.jsonl"

# Test 3: File with no sidechain messages
echo "Test 3: No sidechain messages should return 2"
cat > no_sidechain.jsonl << 'EOF'
{"timestamp":"2025-08-04T11:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"timestamp":"2025-08-04T11:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi there"}]}}
EOF
run_test "No sidechain messages" 2 "no_sidechain.jsonl"

# Test 4: Sidechain message with APPROVED result
echo "Test 4: Sidechain with APPROVED should return 0"
cat > approved.jsonl << 'EOF'
{"parentUuid":"test-uuid","isSidechain":false,"userType":"external","sessionId":"test-session","type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"parentUuid":"test-uuid","isSidechain":true,"userType":"external","sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ✅ APPROVED - Code quality is good"}]}}
EOF
run_test "APPROVED result" 0 "approved.jsonl"

# Test 5: Sidechain message with REJECTED result
echo "Test 5: Sidechain with REJECTED should return 1"
cat > rejected.jsonl << 'EOF'
{"parentUuid":"test-uuid","isSidechain":false,"userType":"external","sessionId":"test-session","type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"parentUuid":"test-uuid","isSidechain":true,"userType":"external","sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ❌ REJECTED - Code has issues"}]}}
EOF
run_test "REJECTED result" 1 "rejected.jsonl"

# Test 6: Multiple sidechain messages, last one wins
echo "Test 6: Multiple results, last one should win"
cat > multiple_results.jsonl << 'EOF'
{"timestamp":"2025-08-04T11:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"timestamp":"2025-08-04T11:00:01Z","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ❌ REJECTED - First check"}]}}
{"timestamp":"2025-08-04T11:00:02Z","message":{"role":"user","content":[{"type":"text","text":"Fixed issues"}]}}
{"timestamp":"2025-08-04T11:00:03Z","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ✅ APPROVED - Now it looks good"}]}}
EOF
run_test "Multiple results - last wins" 0 "multiple_results.jsonl"

# Test 7: Stale approval detection - Edit after approval
echo "Test 7: Stale approval - Edit after APPROVED should return 2"
cat > stale_approval.jsonl << 'EOF'
{"parentUuid":"test-uuid","isSidechain":false,"userType":"external","sessionId":"test-session","type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"parentUuid":"test-uuid","isSidechain":true,"userType":"external","sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ✅ APPROVED - Code looks good"}]}}
{"parentUuid":"test-uuid","isSidechain":false,"userType":"external","sessionId":"test-session","type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit"}]}}
EOF
run_test "Stale approval detection" 2 "stale_approval.jsonl"

# Test 8: Valid approval with no edits after
echo "Test 8: Valid approval with no edits should return 0"
cat > valid_approval.jsonl << 'EOF'
{"timestamp":"2025-08-04T11:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"timestamp":"2025-08-04T11:00:01Z","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ✅ APPROVED - Code looks good"}]}}
{"timestamp":"2025-08-04T11:00:02Z","message":{"role":"assistant","content":[{"type":"text","text":"Just some text, no edits"}]}}
EOF
run_test "Valid approval no edits" 0 "valid_approval.jsonl"

# Test 9: Malformed JSON
echo "Test 9: Malformed JSON should be handled gracefully"
cat > malformed.jsonl << 'EOF'
{"timestamp":"2025-08-04T11:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{invalid json here
{"timestamp":"2025-08-04T11:00:01Z","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"Final Result: ✅ APPROVED"}]}}
EOF
run_test "Malformed JSON handling" 0 "malformed.jsonl"

# Test 10: Sidechain message without Final Result
echo "Test 10: Sidechain without Final Result should return 2"
cat > sidechain_no_result.jsonl << 'EOF'
{"timestamp":"2025-08-04T11:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
{"timestamp":"2025-08-04T11:00:01Z","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"This is a sidechain message but no Final Result"}]}}
EOF
run_test "Sidechain without Final Result" 2 "sidechain_no_result.jsonl"

# Cleanup
cd ..
rm -rf test-data

# Summary
echo "=== Test Summary ==="
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo "Total tests: $((TESTS_PASSED + TESTS_FAILED))"

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi