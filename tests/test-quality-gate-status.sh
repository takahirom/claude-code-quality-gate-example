#!/bin/bash
# Test for quality-gate-status.sh

set -e

# Source test data  
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/test-data-common.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test counter
test_count=0
pass_count=0

# Store original directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="$PROJECT_ROOT/.claude/scripts/quality-gate-status.sh"

# Test function
test_status() {
    local test_name="$1"
    local expected="$2"
    local setup_func="$3"
    
    ((test_count++))
    
    # Setup test environment
    rm -f test_transcript.jsonl
    $setup_func
    
    # Run the script
    local result
    result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH")
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name: $result"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} $test_name: expected '$expected', got '$result'"
    fi
    
    rm -f test_transcript.jsonl
}

# Setup functions for different states
setup_approved() {
    get_data "APPROVE_RESULT" > test_transcript.jsonl
}

setup_rejected() {
    get_data "REJECT_RESULT" > test_transcript.jsonl
}

setup_pending() {
    # No Final Result in transcript (just regular assistant response)
    get_data "ASSISTANT_RESPONSE" > test_transcript.jsonl
}

setup_empty() {
    # Empty transcript file
    touch test_transcript.jsonl
}

setup_no_file() {
    # No transcript file at all
    rm -f test_transcript.jsonl
}

setup_stale_approval() {
    # APPROVED but then file edited
    get_data "APPROVE_RESULT" > test_transcript.jsonl
    echo '{"message":{"content":[{"name":"Edit"}]}}' >> test_transcript.jsonl
}

# Additional setup functions for git-related tests
setup_disabled_no_changes() {
    # Simulate no git changes by using env variable
    # Since we can't cd to create a clean git repo, we'll test with env override
    touch test_transcript.jsonl
    # This test would require actual git state manipulation which is limited
    # So we'll skip this particular scenario in the test
}

setup_disabled_not_in_git() {
    # Test with QUALITY_GATE_RUN_OUTSIDE_GIT=false (default)
    # This should return DISABLED when not in git repo
    touch test_transcript.jsonl
}

setup_auto_approved() {
    # Create transcript with many stop hook attempts (>10)
    {
        get_data "USER_INPUT"
        for i in {1..11}; do
            get_data "STOP_HOOK_FEEDBACK"
        done
    } > test_transcript.jsonl
}

# Helper functions for git repo tests
setup_temp_git_repo() {
    local tmp_dir=$(mktemp -d) || return 1
    echo "$tmp_dir"
    cd "$tmp_dir" || return 1
    git init --quiet || return 1
    echo "test" > test.txt
    git add test.txt && git commit -m "Initial" --quiet || return 1
    echo "changed" >> test.txt
}

# Unified test function for git repo tests
test_in_git_repo() {
    local test_name="$1"
    local expected="$2"
    local setup_func="$3"
    local emoji_flag="$4"  # Optional: "--emoji" or ""
    
    ((test_count++))
    
    local original_dir=$(pwd)
    local tmp_dir=$(setup_temp_git_repo)
    if [[ -z "$tmp_dir" ]]; then
        local suffix=""
        [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
        echo -e "${RED}✗${NC} $test_name$suffix: Failed to setup test environment"
        return 1
    fi
    
    # Setup test environment
    rm -f test_transcript.jsonl
    $setup_func
    
    # Run the script with optional emoji flag
    local result
    if [[ -n "$emoji_flag" ]]; then
        result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" "$emoji_flag")
    else
        result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH")
    fi
    
    local suffix=""
    [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name$suffix: $result"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} $test_name$suffix: expected '$expected', got '$result'"
    fi
    
    cd "$original_dir"
    rm -rf "$tmp_dir"
}

# Wrapper functions for backward compatibility
test_status_in_git_repo() {
    test_in_git_repo "$1" "$2" "$3" ""
}

test_emoji_status_in_git_repo() {
    test_in_git_repo "$1" "$2" "$3" "--emoji"
}

# Test function for emoji mode
test_emoji_status() {
    local test_name="$1"
    local expected="$2"
    local setup_func="$3"
    
    ((test_count++))
    
    # Setup test environment
    rm -f test_transcript.jsonl
    $setup_func
    
    # Run the script with --emoji flag
    local result
    result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" --emoji)
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name (emoji): $result"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} $test_name (emoji): expected '$expected', got '$result'"
    fi
    
    rm -f test_transcript.jsonl
}

# Run tests
echo "Running quality-gate-status.sh tests..."
echo

# Test normal mode
echo "=== Normal mode tests ==="
test_status "APPROVED state" "APPROVED" setup_approved
test_status "REJECTED state" "REJECTED" setup_rejected
test_status "PENDING state (no result)" "PENDING" setup_pending
test_status "PENDING state (empty file)" "PENDING" setup_empty
test_status_in_git_repo "PENDING state (no file)" "PENDING" setup_no_file
test_status "PENDING state (stale approval)" "PENDING" setup_stale_approval
test_status "AUTO-APPROVED state (max attempts)" "APPROVED" setup_auto_approved

echo
echo "=== Emoji mode tests ==="
test_emoji_status "APPROVED state" "✅" setup_approved
test_emoji_status "REJECTED state" "❌" setup_rejected
test_emoji_status "PENDING state (no result)" "⏳" setup_pending
test_emoji_status "PENDING state (empty file)" "⏳" setup_empty
test_emoji_status_in_git_repo "PENDING state (no file)" "⏳" setup_no_file
test_emoji_status "PENDING state (stale approval)" "⏳" setup_stale_approval
test_emoji_status "AUTO-APPROVED state (max attempts)" "✅" setup_auto_approved

echo
echo "Tests completed: $pass_count/$test_count passed"

if [[ $pass_count -eq $test_count ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi