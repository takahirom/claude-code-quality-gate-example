#!/bin/bash
# Test for edit tool detection in quality gate
# Tests that quality gate skips when no edits are made
set -uo pipefail

echo "=== Edit Tool Detection Test ==="

# Script directory detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUALITY_GATE_DIR="$PROJECT_ROOT/.claude/scripts"

# Load common test data
source "$SCRIPT_DIR/test-data-common.sh"

# Test configuration
TEST_DIR="$(mktemp -d -t edit_tool_test.XXXXXX)"
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

# Test 1: No tools used - should skip quality gate
test_no_tools() {
    echo "Test: No tools used"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "No tools used" "0" "$exit_code" "$stderr_output"
}

# Test 2: Read tool only - should skip quality gate
test_read_tool_only() {
    echo "Test: Read tool only"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "READ_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        # If READ_TOOL_USE doesn't exist yet, create minimal version
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/test.txt"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Read tool only" "0" "$exit_code" "$stderr_output"
}

# Test 3: Edit tool used - should trigger quality gate
test_edit_tool() {
    echo "Test: Edit tool used"
    > "$TEST_TRANSCRIPT"  # Empty transcript, no comment
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Edit tool used" "2" "$exit_code" "$stderr_output"
}

# Test 4: Write tool used - should trigger quality gate
test_write_tool() {
    echo "Test: Write tool used"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "WRITE_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        # If WRITE_TOOL_USE doesn't exist yet, create minimal version
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/test.txt","content":"new content"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "Write tool used" "2" "$exit_code" "$stderr_output"
}

# Test 5: MCP serena replace_regex - should trigger quality gate
test_mcp_serena_replace_regex() {
    echo "Test: MCP serena replace_regex"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "MCP_SERENA_REPLACE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        # If MCP_SERENA_REPLACE doesn't exist yet, create minimal version
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__serena__replace_regex","input":{"relative_path":"test.txt","regex":"old","repl":"new"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "MCP serena replace_regex" "2" "$exit_code" "$stderr_output"
}

# Test 6: APPROVED then no edit - should pass
test_approved_then_no_edit() {
    echo "Test: APPROVED then no edit"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/test.txt","old_string":"old","new_string":"new"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "APPROVE_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "APPROVED then no edit" "0" "$exit_code" "$stderr_output"
}

# Test 7: APPROVED then edit (stale approval) - should trigger quality gate
test_approved_then_edit() {
    echo "Test: APPROVED then edit (stale)"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/test.txt","old_string":"old","new_string":"new"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "APPROVE_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    # Add another edit after approval
    get_data "WRITE_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/test2.txt","content":"more changes"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "APPROVED then edit (stale)" "2" "$exit_code" "$stderr_output"
}

# Test 8: APPROVED then MCP edit (stale) - should trigger quality gate
test_approved_then_mcp_edit() {
    echo "Test: APPROVED then MCP edit (stale)"
    > "$TEST_TRANSCRIPT"  # Empty transcript
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "EDIT_TOOL_USE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/test.txt","old_string":"old","new_string":"new"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    get_data "APPROVE_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
    # Add MCP edit after approval
    get_data "MCP_SERENA_REPLACE" >> "$TEST_TRANSCRIPT" 2>/dev/null || {
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__serena__replace_regex","input":{"relative_path":"test.txt","regex":"old","repl":"new"}}]}}' >> "$TEST_TRANSCRIPT"
    }
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "APPROVED then MCP edit (stale)" "2" "$exit_code" "$stderr_output"
}

# Execute all tests
echo "Starting edit tool detection tests..."
echo

test_no_tools
test_read_tool_only
test_edit_tool
test_write_tool
test_mcp_serena_replace_regex
test_approved_then_no_edit
test_approved_then_edit
test_approved_then_mcp_edit

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