#!/bin/bash
# Test for user APPROVE functionality
# Tests that user can manually approve quality gate
set -uo pipefail

echo "=== User APPROVE Test ==="

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUALITY_GATE_DIR="$PROJECT_ROOT/.claude/scripts"

# Load common test data
source "$SCRIPT_DIR/test-data-common.sh"

# Verify quality gate scripts exist
if [[ ! -f "$QUALITY_GATE_DIR/quality-gate-stop.sh" ]]; then
    echo "❌ Error: quality-gate-stop.sh not found at $QUALITY_GATE_DIR"
    exit 1
fi

# Test configuration
TEST_DIR="$(mktemp -d -t user_approve_test.XXXXXX)"
TEST_TRANSCRIPT="$TEST_DIR/test-transcript.jsonl"

# Create a temporary file to ensure git detects changes
TEST_DUMMY_FILE="$PROJECT_ROOT/.test-dummy-$$"
touch "$TEST_DUMMY_FILE"

# Cleanup trap
trap 'rm -f "$TEST_DUMMY_FILE"; rm -rf "$TEST_DIR"' EXIT

# Test result tracking
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

run_test() {
    local test_name="$1"
    local expected_exit_code="$2"
    local actual_exit_code="$3"
    local stderr_output="$4"
    
    ((TOTAL_TESTS++))
    
    # Check for unexpected errors in stderr
    if [[ -n "$stderr_output" ]]; then
        if [[ $expected_exit_code -ne 0 ]] && ! echo "$stderr_output" | \
           grep -qE '(Quality gate|STOP:|Action required|blocking session)'; then
            echo "❌ $test_name: UNEXPECTED ERROR in stderr: $stderr_output"
            ((FAILED_TESTS++))
            return
        fi
    fi
    
    if [[ "$actual_exit_code" == "$expected_exit_code" ]]; then
        echo "✅ $test_name: PASSED (exit code $actual_exit_code)"
        ((PASSED_TESTS++))
    else
        echo "❌ $test_name: FAILED (expected $expected_exit_code, got $actual_exit_code)"
        if [[ -n "$stderr_output" ]]; then
            echo "   stderr: $stderr_output"
        fi
        ((FAILED_TESTS++))
    fi
}

# Test 1: User types "APPROVE" - should be approved
test_user_approve_simple() {
    echo "Test: User types APPROVE"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User APPROVE" "0" "$exit_code" "$stderr_output"
}

# Test 2: User types "approve" (lowercase) - should be approved
test_user_approve_lowercase() {
    echo "Test: User types approve (lowercase)"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE_LOWERCASE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User approve (lowercase)" "0" "$exit_code" "$stderr_output"
}

# Test 3: User types "Approve" (mixed case) - should be approved
test_user_approve_mixed_case() {
    echo "Test: User types Approve (mixed case)"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE_MIXED" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User Approve (mixed case)" "0" "$exit_code" "$stderr_output"
}

# Test 4: User APPROVE then edit (stale) - should trigger quality gate
test_user_approve_then_edit() {
    echo "Test: User APPROVE then edit (stale)"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    # Add another edit after approval
    get_data "WRITE_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/test2.txt","content":"more changes"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User APPROVE then edit (stale)" "2" "$exit_code" "$stderr_output"
}

# Test 5: User message with APPROVE in context - should be approved
test_user_approve_in_context() {
    echo "Test: User says 'please APPROVE this change'"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE_IN_CONTEXT" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User APPROVE in context" "0" "$exit_code" "$stderr_output"
}

# Test 6: User types something else - should trigger quality gate
test_user_no_approve() {
    echo "Test: User types something else"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_LOOKS_GOOD" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User no APPROVE" "2" "$exit_code" "$stderr_output"
}

# Test 7: Multiple user messages, last one is APPROVE - should be approved
test_multiple_messages_last_approve() {
    echo "Test: Multiple user messages, last is APPROVE"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Multiple messages, last APPROVE" "0" "$exit_code" "$stderr_output"
}

# Test 8: User APPROVE overrides previous REJECTED - should be approved
test_user_approve_overrides_rejected() {
    echo "Test: User APPROVE overrides REJECTED"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "REJECT_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "USER_APPROVE_IN_CONTEXT" >> "$TEST_TRANSCRIPT"  # Uses "please APPROVE this change" which contains APPROVE
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User APPROVE overrides REJECTED" "0" "$exit_code" "$stderr_output"
}

# Test 9: Empty user message - should not be approved
test_empty_user_message() {
    echo "Test: Empty user message"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    # Empty message needs custom implementation since test-data-common doesn't have it
    echo '{"type":"user","message":{"role":"user","content":""}}' >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Empty user message" "2" "$exit_code" "$stderr_output"
}

# Test 10: User types "LGTM" (common approval abbreviation) - should NOT be approved (strict)
test_user_lgtm_not_approved() {
    echo "Test: User types LGTM (not APPROVE)"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "USER_LGTM" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "User LGTM (not APPROVE)" "2" "$exit_code" "$stderr_output"
}

# Test 11: Tool result with "APPROVED" should not be detected as user APPROVE
test_tool_result_approved_not_user_approve() {
    echo "Test: Tool result with APPROVED (not user APPROVE)"
    : > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    # Add tool result with APPROVED text
    echo '{"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_test","type":"tool_result","content":"Result code: 0\nAPPROVED"}]}}' >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Tool result APPROVED (not user)" "2" "$exit_code" "$stderr_output"
}

# Execute all tests
echo "Starting user APPROVE tests..."
echo

# Execute all test functions automatically
for test_func in $(compgen -A function | grep '^test_'); do
    $test_func
done

echo
echo "=== Test Summary ==="
echo "Tests passed: $PASSED_TESTS"
echo "Tests failed: $FAILED_TESTS"
echo "Total tests: $TOTAL_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "⚠️  Some tests failed. Please review the results above."
    exit 1
fi