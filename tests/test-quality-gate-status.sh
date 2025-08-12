#!/bin/bash
# Test for quality-gate-status.sh

# Don't use set -e in test scripts as it prevents proper error reporting
set -uo pipefail

# Debug info for CI (only in CI environment)
if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "Debug: Running in CI environment"
    echo "Debug: Current directory: $(pwd)"
    echo "Debug: Script location: ${BASH_SOURCE[0]}"
fi

# Source test data  
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$TESTS_DIR/test-data-common.sh" ]]; then
    echo "ERROR: test-data-common.sh not found at $TESTS_DIR"
    echo "Directory contents:"
    ls -la "$TESTS_DIR" || true
    exit 1
fi

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

if [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    echo "Debug: Project root: $PROJECT_ROOT"
    echo "Debug: Script path: $SCRIPT_PATH"
fi

if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: quality-gate-status.sh not found at $SCRIPT_PATH"
    echo "Directory contents of $PROJECT_ROOT/.claude/scripts:"
    ls -la "$PROJECT_ROOT/.claude/scripts" || true
    exit 1
fi

# Test function
test_status() {
    local test_name="$1"
    local expected="$2"
    local setup_func="$3"
    
    ((test_count++))
    
    # Setup test environment
    rm -f test_transcript.jsonl
    if ! $setup_func; then
        echo -e "${RED}✗${NC} $test_name: Setup function failed"
        return 0
    fi
    
    # Run the script
    local result
    result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗${NC} $test_name: Script failed with exit code $exit_code"
        echo "  Output: $result"
        return 0
    fi
    
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
    if ! get_data "APPROVE_RESULT" > test_transcript.jsonl; then
        echo "ERROR: Failed to get APPROVE_RESULT data"
        return 1
    fi
}

setup_rejected() {
    if ! get_data "REJECT_RESULT" > test_transcript.jsonl; then
        echo "ERROR: Failed to get REJECT_RESULT data"
        return 1
    fi
}

setup_pending() {
    # No Final Result in transcript (just regular assistant response)
    if ! get_data "ASSISTANT_RESPONSE" > test_transcript.jsonl; then
        echo "ERROR: Failed to get ASSISTANT_RESPONSE data"
        return 1
    fi
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
    if ! get_data "APPROVE_RESULT" > test_transcript.jsonl; then
        echo "ERROR: Failed to get APPROVE_RESULT data for stale approval"
        return 1
    fi
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
    if ! {
        get_data "USER_INPUT"
        for _ in {1..11}; do
            get_data "STOP_HOOK_FEEDBACK"
        done
    } > test_transcript.jsonl; then
        echo "ERROR: Failed to create auto-approved transcript"
        return 1
    fi
}

# Helper functions for git repo tests
setup_temp_git_repo() {
    local tmp_dir
    tmp_dir=$(mktemp -d) || return 1
    (
        cd "$tmp_dir" || exit 1
        git init --quiet || exit 1
        # Ensure commits work in CI without global git identity
        git config user.email "test@example.com" || exit 1
        git config user.name "Test User" || exit 1
        git config commit.gpgsign false || exit 1
        echo "test" > test.txt
        git add test.txt || exit 1
        git commit -m "Initial" --quiet || exit 1
        echo "changed" >> test.txt
    ) || return 1
    echo "$tmp_dir"
}

# Unified test function for git repo tests
test_in_git_repo() {
    local test_name="$1"
    local expected="$2"
    local setup_func="$3"
    local emoji_flag="$4"  # Optional: "--emoji" or ""
    
    ((test_count++))
    
    local original_dir
    original_dir=$(pwd)
    local tmp_dir
    local setup_rc
    tmp_dir=$(setup_temp_git_repo)
    setup_rc=$?
    if [[ $setup_rc -ne 0 || -z "$tmp_dir" ]]; then
        local suffix=""
        [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
        echo -e "${RED}✗${NC} $test_name$suffix: Failed to setup test environment"
        ((test_count--))
        # Cleanup temp dir if it exists
        [[ -n "$tmp_dir" && -d "$tmp_dir" ]] && rm -rf "$tmp_dir"
        return 0
    fi
    if ! cd "$tmp_dir"; then
        local suffix=""
        [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
        echo -e "${RED}✗${NC} $test_name$suffix: Failed to cd into temp repo"
        ((test_count--))
        rm -rf "$tmp_dir"
        return 0
    fi
    
    # Setup test environment
    rm -f test_transcript.jsonl
    if ! $setup_func; then
        local suffix=""
        [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
        echo -e "${RED}✗${NC} $test_name$suffix: Setup function failed"
        # Cleanup and restore cwd before returning
        rm -rf "$tmp_dir"
        cd "$original_dir" || true
        return 0
    fi
    
    # Run the script with optional emoji flag, capture stderr and exit code
    local result
    local exit_code
    if [[ -n "$emoji_flag" ]]; then
        result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" "$emoji_flag" 2>&1)
        exit_code=$?
    else
        result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" 2>&1)
        exit_code=$?
    fi
    
    local suffix=""
    [[ -n "$emoji_flag" ]] && suffix=" (emoji)"
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗${NC} $test_name$suffix: Script failed with exit code $exit_code"
        echo "  Output: $result"
        rm -rf "$tmp_dir"
        cd "$original_dir" || true
        return 0
    fi
    
    if [[ "$result" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name$suffix: $result"
        ((pass_count++))
    else
        echo -e "${RED}✗${NC} $test_name$suffix: expected '$expected', got '$result'"
    fi
    
    # Remove temp repo first, then attempt to restore cwd
    rm -rf "$tmp_dir"
    cd "$original_dir" || {
        echo -e "${RED}✗${NC} $test_name$suffix: Failed to cd back to $original_dir"
        return 0
    }
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
    if ! $setup_func; then
        echo -e "${RED}✗${NC} $test_name: Setup function failed"
        return 0
    fi
    
    # Run the script with --emoji flag
    local result
    result=$(TRANSCRIPT_PATH=test_transcript.jsonl "$SCRIPT_PATH" --emoji 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}✗${NC} $test_name (emoji): Script failed with exit code $exit_code"
        echo "  Output: $result"
        return 0
    fi
    
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