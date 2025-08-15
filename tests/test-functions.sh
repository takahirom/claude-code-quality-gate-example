#!/bin/bash
# Function test script - Uses refactored common test data

# Load common test data
source "$(dirname "$0")/test-data-common.sh"
source "$(dirname "$0")/../.claude/scripts/common-config.sh"

echo "=== Quality Gate Functions Test ==="

# Test configuration
TEST_TRANSCRIPT="/tmp/test-functions-transcript.jsonl"
LOG_FILE="/tmp/test-functions.log"

# Test result tracking
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Helper functions
run_test() {
    local test_name="$1"
    local expected_result="$2"
    local actual_result="$3"
    
    ((TOTAL_TESTS++))
    
    if [[ "$actual_result" == "$expected_result" ]]; then
        echo "✅ $test_name: PASSED"
        ((PASSED_TESTS++))
    else
        echo "❌ $test_name: FAILED (expected $expected_result, got $actual_result)"
        ((FAILED_TESTS++))
    fi
}

create_transcript_with() {
    local output_file="$1"
    shift
    
    echo "# Test transcript" > "$output_file"
    for data_type in "$@"; do
        get_data "$data_type" >> "$output_file"
    done
}

# Test 1: Basic APPROVE detection
test_approve_detection() {
    echo "Test 1: APPROVE detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "APPROVE_RESULT"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "APPROVE detection" "0" "$?"
}

# Test 2: Basic REJECT detection  
test_reject_detection() {
    echo "Test 2: REJECT detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "REJECT_RESULT"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "REJECT detection" "1" "$?"
}

# Test 3: toolUseResult format APPROVE detection
test_tool_result_approve() {
    echo "Test 3: toolUseResult APPROVE detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "TOOL_USE_RESULT_APPROVE"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "toolUseResult APPROVE" "0" "$?"
}

# Test 4: toolUseResult format REJECT detection
test_tool_result_reject() {
    echo "Test 4: toolUseResult REJECT detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "TOOL_USE_RESULT_REJECT"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "toolUseResult REJECT" "1" "$?"
}

# Test 5: Latest result detection with multiple results
test_latest_result() {
    echo "Test 5: Latest result detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "REJECT_RESULT" "APPROVE_RESULT"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "Latest result detection" "0" "$?"
}

# Test 6: Stop hook attempt counting
test_stop_hook_counting() {
    echo "Test 6: Stop hook counting"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "STOP_HOOK_FEEDBACK" "STOP_HOOK_FEEDBACK" "STOP_HOOK_FEEDBACK"
    
    if count_attempts_since_last_reset_point "$TEST_TRANSCRIPT" 5; then
        run_test "Stop hook counting" "1" "0"  # Expected to continue (return 1), but got 0 (stop)
    else
        run_test "Stop hook counting" "1" "1"  # Expected to continue (return 1), got 1 (continue)
    fi
}

# Test 7: Stop hook limit reached
test_stop_hook_limit() {
    echo "Test 7: Stop hook limit reached"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT"
    
    # Add 6 Stop hooks (exceeds 5 attempt limit)
    for i in {1..6}; do
        get_data "STOP_HOOK_FEEDBACK" >> "$TEST_TRANSCRIPT"
    done
    
    if count_attempts_since_last_reset_point "$TEST_TRANSCRIPT" 5; then
        run_test "Stop hook limit" "0" "0"  # Expected to stop (return 0), got 0 (stop)
    else
        run_test "Stop hook limit" "0" "1"  # Expected to stop (return 0), but got 1 (continue)
    fi
}

# Test 8: Stale approval detection after file edits
test_stale_approval() {
    echo "Test 8: Stale approval detection"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "APPROVE_RESULT"
    
    # Add file edit after APPROVE to invalidate approval
    echo '{
      "type": "assistant",
      "message": {
        "content": [
          {
            "type": "tool_use",
            "name": "Edit",
            "input": {"file_path": "/test/file.js"}
          }
        ]
      }
    }' >> "$TEST_TRANSCRIPT"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "Stale approval detection" "2" "$?"
}

# Test 9: No result found
test_no_result() {
    echo "Test 9: No result found"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "ASSISTANT_RESPONSE"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "No result found" "3" "$?"  # No edits detected
}

# Test 10: Mixed results with toolUseResult override
test_mixed_results() {
    echo "Test 10: Mixed results with toolUseResult override"
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "REJECT_RESULT" "TOOL_USE_RESULT_APPROVE"
    
    get_quality_result "$TEST_TRANSCRIPT"
    run_test "Mixed results override" "0" "$?"
}

# Test Edit tool false positive detection
test_edit_false_positive() {
    echo "Test 12: Edit tool false positive (BUG REPRODUCTION)"  
    create_transcript_with "$TEST_TRANSCRIPT" "USER_INPUT" "EDIT_TOOL_FALSE_POSITIVE"
    
    get_quality_result "$TEST_TRANSCRIPT"
    local actual_result=$?
    
    if [[ $actual_result -eq 0 ]]; then
        echo "🐛 Edit tool false positive BUG: REPRODUCED (incorrectly returns APPROVED)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    elif [[ $actual_result -eq 2 ]]; then
        echo "✅ Edit tool false positive: FIXED (correctly returns No Result)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    elif [[ $actual_result -eq 3 ]]; then
        echo "✅ Edit tool false positive: FIXED (correctly returns No Edits)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❓ Edit tool false positive: UNEXPECTED (returns $actual_result)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Test 13: Ongoing session interference bug  
test_ongoing_session_bug() {
    echo "Test 13: Ongoing session interference (BUG REPRODUCTION)"
    
    # Create transcript that simulates current issue:
    # 1. USER_INPUT
    # 2. SIDECHAIN APPROVED result (should be detected)  
    # 3. Ongoing Bash command with "Final Result:" in command/description (should be ignored)
    
    cat > "$TEST_TRANSCRIPT" << 'EOF'
# Test transcript
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Please review the code"}]},"uuid":"user-1"}
{"parentUuid":"parent-1","isSidechain":true,"userType":"external","message":{"id":"msg_approved","type":"message","role":"assistant","content":[{"type":"text","text":"Quality analysis complete.\n\n**Final Result: ✅ APPROVED - All quality standards met.**"}]},"uuid":"approved-result"}
{"parentUuid":"parent-2","isSidechain":false,"userType":"external","message":{"id":"msg_ongoing","type":"message","role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"tac \"/some/transcript.jsonl\" | grep -m1 \"Final Result:\" | head -1","description":"Find Final Result in transcript"}}]},"uuid":"ongoing-bash"}
EOF

    get_quality_result "$TEST_TRANSCRIPT"
    local actual_result=$?
    
    if [[ $actual_result -eq 0 ]]; then
        echo "✅ Ongoing session interference: FIXED (correctly detects APPROVED from sidechain)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "🐛 Ongoing session interference BUG: REPRODUCED (ongoing Bash interferes with detection)"
        echo "   Expected: APPROVED (0) from sidechain message"
        echo "   Actual: $actual_result (ongoing command interference)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Test 15: Debug script scenario - realistic interference pattern
test_debug_script_scenario() {
    echo "Test 15: Debug script scenario (REAL WORLD BUG)"
    
    # Based on actual debug-transcript.sh output - most recent Final Result is in Bash command
    # but actual APPROVED is in earlier sidechain message
    
    cat > "$TEST_TRANSCRIPT" << 'EOF'
# Test transcript - debug script scenario
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"debug issue"}]},"uuid":"user-debug"}
{"parentUuid":"quality-parent","isSidechain":true,"userType":"external","message":{"id":"quality-result","type":"message","role":"assistant","content":[{"type":"text","text":"## Final Result: ✅ APPROVED - High-quality bug fix implementation\n\n**Rationale:**\n- Root cause properly identified and addressed"}]},"uuid":"quality-approved"}
{"parentUuid":"debug-parent","isSidechain":false,"userType":"external","message":{"id":"debug-cmd","type":"message","role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"tac \"/transcript.jsonl\" | nl -nrn | grep -m1 \"Final Result:\" | head -1","description":"Get the most recent Final Result line"}}]},"uuid":"debug-bash"}
EOF

    get_quality_result "$TEST_TRANSCRIPT"
    local actual_result=$?
    
    if [[ $actual_result -eq 0 ]]; then
        echo "✅ Debug scenario: FIXED (correctly ignores Bash command, finds sidechain APPROVED)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "🐛 Debug scenario BUG: REPRODUCED (Bash command with 'Final Result:' interferes)"
        echo "   Expected: APPROVED (0) from sidechain quality result"
        echo "   Actual: $actual_result (debug command interference)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Performance test
performance_test() {
    echo "Performance Test: Large transcript processing"
    local large_transcript="/tmp/large-test-transcript.jsonl"
    
    # Create large transcript (1000 entries) 
    echo "# Large test transcript" > "$large_transcript"
    for i in {1..200}; do
        get_data "USER_INPUT" >> "$large_transcript"
        get_data "ASSISTANT_RESPONSE" >> "$large_transcript"
        get_data "STOP_HOOK_FEEDBACK" >> "$large_transcript"
        get_data "INTERVENTION_MESSAGE" >> "$large_transcript"
        get_data "REJECT_RESULT" >> "$large_transcript"
    done
    get_data "APPROVE_RESULT" >> "$large_transcript"  # Final approval
    
    # Test get_quality_result performance
    local start_time=$(date +%s.%N)
    get_quality_result "$large_transcript"
    local result=$?
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)
    echo "get_quality_result: Processed 1001 entries in ${duration}s"
    run_test "Large transcript processing" "0" "$result"
    
    # Test count_attempts_since_last_reset_point performance
    start_time=$(date +%s.%N)
    count_attempts_since_last_reset_point "$large_transcript" 10
    local count_result=$? 
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    echo "count_attempts_since_last_reset_point: Processed 1001 entries in ${duration}s"
    run_test "Large transcript attempt counting" "1" "$count_result"  # Should continue (return 1)
    
    rm -f "$large_transcript"
}

# Execute all tests
echo "Starting function tests..."
echo

# Automatic test discovery - run all test_ functions
for test_func in $(compgen -A function | grep '^test_'); do
    $test_func
done

# Optional performance test
if command -v bc >/dev/null 2>&1; then
    performance_test
else
    echo "Skipping performance test (bc not available)"
fi

echo
echo "=== Test Summary ==="
echo "Tests passed: $PASSED_TESTS"
echo "Tests failed: $FAILED_TESTS"
echo "Total tests: $TOTAL_TESTS"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo "🎉 All tests passed!"
    exit_code=0
else
    echo "⚠️  Some tests failed. Please review the results above."
    exit_code=1
fi

# Cleanup
rm -f "$TEST_TRANSCRIPT" "$LOG_FILE"

exit $exit_code