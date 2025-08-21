#!/bin/bash
# Fail fast and surface unexpected issues (but allow controlled non-zero exits)
set -uo pipefail
# Integration test for quality gate scripts using real transcript files

echo "=== Quality Gate Integration Test ==="

# Script directory detection for universal path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Go up one level from tests/ to find .claude/scripts/ (relative to script location)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUALITY_GATE_DIR="$PROJECT_ROOT/.claude/scripts"

# Load common test data
source "$SCRIPT_DIR/test-data-common.sh"

# Verify quality gate scripts exist
if [[ ! -f "$QUALITY_GATE_DIR/quality-gate-stop.sh" ]]; then
    echo "❌ Error: quality-gate-stop.sh not found at $QUALITY_GATE_DIR"
    exit 1
fi
if [[ ! -f "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" ]]; then
    echo "❌ Error: quality-gate-pre-commit.sh not found at $QUALITY_GATE_DIR"
    exit 1
fi

# Test configuration with unique temporary directory
TEST_DIR="/tmp/quality-gate-test-$$-$(date +%s)"
TEST_TRANSCRIPT="$TEST_DIR/test-transcript.jsonl"
mkdir -p "$TEST_DIR"

# Create a temporary file under the repo root to ensure git detects changes
TEST_DUMMY_FILE="$PROJECT_ROOT/.test-dummy-$$"
touch "$TEST_DUMMY_FILE"

# Ensure cleanup even on early exits
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

# Create test transcript with APPROVED result
create_approved_transcript() {
    echo "# Test transcript" > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "APPROVE_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
}

# Create test transcript with REJECTED result
create_rejected_transcript() {
    echo "# Test transcript" > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "REJECT_RESULT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
}

# Create test transcript with no quality result
create_no_result_transcript() {
    echo "# Test transcript" > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "ASSISTANT_RESPONSE" >> "$TEST_TRANSCRIPT"
}

# quality-gate-stop.sh with APPROVED result
test_stop_approved() {
    echo "quality-gate-stop.sh with APPROVED result"
    create_approved_transcript
    
    # Create input JSON for the script
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "stop script with APPROVED" "0" "$exit_code" "$stderr_output"
}

# quality-gate-stop.sh with REJECTED result  
test_stop_rejected() {
    echo "quality-gate-stop.sh with REJECTED result"
    create_rejected_transcript
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "stop script with REJECTED" "2" "$exit_code" "$stderr_output"
}

# quality-gate-stop.sh with no result
test_stop_no_result() {
    echo "quality-gate-stop.sh with no result"
    create_no_result_transcript
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "stop script with no result (no edits)" "0" "$exit_code" "$stderr_output"
}

# quality-gate-pre-commit.sh with APPROVED result
test_precommit_approved() {
    echo "quality-gate-pre-commit.sh with APPROVED result"
    create_approved_transcript
    
    # Create input JSON for pre-commit with git commit command
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"git commit -m \"test commit\""},"files_changed":["test.js"]}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "pre-commit with APPROVED" "0" "$exit_code" "$stderr_output"
}

# quality-gate-pre-commit.sh with REJECTED result
test_precommit_rejected() {
    echo "quality-gate-pre-commit.sh with REJECTED result"
    create_rejected_transcript
    
    # Create input JSON for pre-commit with git commit command
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"git commit -m \"test commit\""},"files_changed":["test.js"]}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "pre-commit with REJECTED" "2" "$exit_code" "$stderr_output"
}

# Bug reproduction - nl -nrn + jq issue
test_nl_jq_bug() {
    echo "nl -nrn + jq bug reproduction"
    
    # Create transcript that would trigger the bug (toolUseResult format)
    echo "# Test transcript" > "$TEST_TRANSCRIPT"
    get_data "USER_INPUT" >> "$TEST_TRANSCRIPT"
    get_data "TOOL_USE_RESULT_APPROVE" >> "$TEST_TRANSCRIPT"
    
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'"}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-stop.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    # With the fix, this should detect APPROVED and exit 0
    run_test "nl -nrn bug fix verification" "0" "$exit_code" "$stderr_output"
}

# pre-commit with git -c option
test_precommit_git_c_option() {
    echo "quality-gate-pre-commit.sh with git -c option"
    create_approved_transcript
    
    # Create input JSON for pre-commit with git -c command
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"git -c user.name=\"Test User\" -c user.email=\"test@example.com\" commit -m \"test commit\""},"files_changed":["test.js"]}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "pre-commit with git -c option" "0" "$exit_code" "$stderr_output"
}

# pre-commit with git --no-verify option
test_precommit_double_dash_option() {
    echo "quality-gate-pre-commit.sh with git --no-verify option"
    create_approved_transcript
    
    # Create input JSON for pre-commit with git --no-verify command
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"git --no-verify commit -m \"test commit\""},"files_changed":["test.js"]}'
    
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    
    run_test "pre-commit with --no-verify option" "0" "$exit_code" "$stderr_output"
}

# Test that non-git-commit commands are not matched
test_precommit_false_positives() {
    echo "quality-gate-pre-commit.sh false positive tests"
    create_approved_transcript
    
    # Test 1: mygit commit should NOT match
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"mygit commit -m \"test\""},"files_changed":["test.js"]}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    run_test "mygit commit should not trigger" "0" "$exit_code" "$stderr_output"
    
    # Test 2: echo && git commit SHOULD match
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"echo foo && git commit -m \"test\""},"files_changed":["test.js"]}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    run_test "echo && git commit should trigger" "0" "$exit_code" "$stderr_output"
    
    # Test 3: git status should NOT match
    input_json='{"transcript_path":"'$TEST_TRANSCRIPT'","tool_input":{"command":"git status"},"files_changed":["test.js"]}'
    stderr_output=$(echo "$input_json" | "$QUALITY_GATE_DIR/quality-gate-pre-commit.sh" 2>&1 >/dev/null)
    exit_code=$?
    run_test "git status should not trigger" "0" "$exit_code" "$stderr_output"
}

# Performance test - ensure quality gate scripts handle large transcripts efficiently
test_performance_large_transcript() {
    echo "Performance test with large transcript (900+ user messages)"
    
    # Create large transcript similar to real-world scenario
    local large_transcript="$TEST_DIR/large-transcript.jsonl"
    echo "# Large test transcript" > "$large_transcript"
    
    # Add many user messages (simulate real scenario with ~900 user messages)
    for i in {1..900}; do
        generate_user_message "User message $i" "user-$i" >> "$large_transcript"
        # Add some assistant responses periodically
        if (( i % 30 == 0 )); then
            get_data "ASSISTANT_RESPONSE" >> "$large_transcript"
        fi
    done
    
    # Add multiple "Final Result:" entries in various contexts
    for i in {1..30}; do
        generate_bash_command 'grep "Final Result:" /tmp/test.jsonl' "Search for Final Result" "bash-$i" >> "$large_transcript"
    done
    
    # Add actual Final Result at the end
    get_data "APPROVE_RESULT" >> "$large_transcript"
    
    local user_count=$(grep -c '"type":"user"' "$large_transcript")
    local final_result_count=$(grep -c "Final Result:" "$large_transcript")
    echo "  Created test file with $user_count user messages and $final_result_count 'Final Result:' occurrences"
    
    # Test quality-gate-stop.sh with timeout
    input_json='{"transcript_path":"'$large_transcript'"}'
    
    # Use timeout to detect performance issues
    local start_time=$(date +%s)
    timeout 5 bash -c "echo '$input_json' | '$QUALITY_GATE_DIR/quality-gate-stop.sh' 2>&1 >/dev/null"
    local timeout_exit=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $timeout_exit -eq 124 ]]; then
        echo "❌ Performance test: FAILED (timed out after 5 seconds)"
        echo "   Processing $user_count user messages caused timeout"
        echo "   This indicates a performance regression in quality gate scripts"
        ((FAILED_TESTS++))
    elif [[ $duration -gt 3 ]]; then
        echo "⚠️  Performance test: WARNING (took ${duration}s, >3s threshold)"
        echo "   Consider optimizing for large transcript files"
        ((FAILED_TESTS++))
    else
        echo "✅ Performance test: PASSED (completed in ${duration}s)"
        ((PASSED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    rm -f "$large_transcript"
}

# Execute all tests
echo "Starting integration tests..."
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
    echo "🎉 All integration tests passed!"
    exit_code=0
else
    echo "⚠️  Some integration tests failed. Please review the results above."
    exit_code=1
fi

# Cleanup is handled by trap
exit $exit_code