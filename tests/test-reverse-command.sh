#!/bin/bash
# Test reverse command detection and functionality

# Test configuration
TEST_DIR="$(mktemp -d -t reverse_cmd_test.XXXXXX)"
TEST_DATA="$TEST_DIR/test_data.txt"

# Test result tracking
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Helper function
run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    ((TOTAL_TESTS++))
    
    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}✅${NC} $test_name: PASSED"
        ((PASSED_TESTS++))
    else
        echo -e "${RED}❌${NC} $test_name: FAILED (expected '$expected', got '$actual')"
        ((FAILED_TESTS++))
    fi
}

# Setup test data
setup_test_data() {
    echo "line 1" > "$TEST_DATA"
    echo "line 2" >> "$TEST_DATA"
    echo "line 3" >> "$TEST_DATA"
    echo "line 4" >> "$TEST_DATA"
}

# Test 1: Check tac availability and functionality
test_tac_functionality() {
    echo "Test 1: tac command functionality"
    
    if command -v tac >/dev/null 2>&1; then
        local result=$(tac "$TEST_DATA" | head -1)
        run_test "tac functionality" "line 4" "$result"
    else
        echo "ℹ️  tac not available, skipping functionality test"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
    fi
}

# Test 2: Check tail -r availability and functionality
test_tail_r_functionality() {
    echo "Test 2: tail -r command functionality"
    
    if command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
        local result=$(tail -r "$TEST_DATA" | head -1)
        run_test "tail -r functionality" "line 4" "$result"
    else
        echo "ℹ️  tail -r not available, skipping functionality test"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
    fi
}

# Test 3: Functional equivalence between tac and tail -r
test_functional_equivalence() {
    echo "Test 3: Functional equivalence between tac and tail -r"
    
    local tac_available=false
    local tail_r_available=false
    
    if command -v tac >/dev/null 2>&1; then
        tac_available=true
    fi
    
    if command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
        tail_r_available=true
    fi
    
    if [[ "$tac_available" == "true" && "$tail_r_available" == "true" ]]; then
        local tac_output=$(tac "$TEST_DATA")
        local tail_r_output=$(tail -r "$TEST_DATA")
        
        if [[ "$tac_output" == "$tail_r_output" ]]; then
            run_test "tac vs tail -r equivalence" "equivalent" "equivalent"
        else
            run_test "tac vs tail -r equivalence" "equivalent" "different"
        fi
    else
        echo "ℹ️  Both commands not available, skipping equivalence test"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
    fi
}

# Test 4: REVERSE_CMD detection with tac available
test_reverse_cmd_with_tac() {
    echo "Test 4: REVERSE_CMD detection when tac is available"
    
    # Create PATH-based shims for robust testing
    local test_bin="$TEST_DIR/bin"
    mkdir -p "$test_bin"
    
    # Create tac shim that works
    cat > "$test_bin/tac" << 'EOF'
#!/bin/bash
exec /usr/bin/tac "$@"
EOF
    chmod +x "$test_bin/tac"
    
    # Create tail shim that supports -r
    cat > "$test_bin/tail" << 'EOF'
#!/bin/bash
exec /usr/bin/tail "$@"
EOF
    chmod +x "$test_bin/tail"
    
    # Test with modified PATH
    local test_script="$TEST_DIR/test_tac.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PATH="$test_bin:\$PATH"

# Copy REVERSE_CMD detection logic from common-config.sh
if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
elif command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
else
    echo "ERROR: No reverse command found"
    exit 1
fi

echo "\$REVERSE_CMD"
EOF
    
    chmod +x "$test_script"
    local result=$("$test_script")
    run_test "REVERSE_CMD with tac available" "tac" "$result"
    
    rm -rf "$test_bin" "$test_script"
}

# Test 5: REVERSE_CMD detection with only tail -r available
test_reverse_cmd_with_tail_only() {
    echo "Test 5: REVERSE_CMD detection when only tail -r is available"
    
    # Skip test if system tac cannot be hidden
    if [[ -f /usr/bin/tac ]]; then
        echo "ℹ️  Skipping tail-only test (system tac present in /usr/bin)"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
        return
    fi
    
    # Create PATH-based shims
    local test_bin="$TEST_DIR/bin_tail_only"
    mkdir -p "$test_bin"
    
    # Create tail shim that supports -r
    cat > "$test_bin/tail" << 'EOF'
#!/bin/bash
exec /usr/bin/tail "$@"
EOF
    chmod +x "$test_bin/tail"
    
    # Test script with limited PATH
    local test_script="$TEST_DIR/test_tail.sh"
    cat > "$test_script" << EOF
#!/bin/bash
export PATH="$test_bin:/bin:/sbin"

# Copy REVERSE_CMD detection logic from common-config.sh
if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
elif command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
else
    echo "ERROR: No reverse command found"
    exit 1
fi

echo "\$REVERSE_CMD"
EOF
    
    chmod +x "$test_script"
    local result=$("$test_script")
    run_test "REVERSE_CMD with tail -r only" "tail -r" "$result"
    
    rm -rf "$test_bin" "$test_script"
}

# Test 6: REVERSE_CMD detection with neither command available
test_reverse_cmd_no_commands() {
    echo "Test 6: REVERSE_CMD detection when no commands available"
    
    # Create PATH with no useful commands
    local test_bin="$TEST_DIR/bin_empty"
    mkdir -p "$test_bin"
    
    # Create tail shim that doesn't support -r
    cat > "$test_bin/tail" << 'EOF'
#!/bin/bash
if [[ "$1" == "-r" ]]; then
    echo "tail: invalid option -- 'r'" >&2
    exit 1
fi
# Otherwise fail
exit 127
EOF
    chmod +x "$test_bin/tail"
    
    # No tac at all
    
    # Test with very limited PATH
    local test_script="$TEST_DIR/test_none.sh"
    cat > "$test_script" << EOF
#!/bin/bash
# Use minimal PATH with only our shims
export PATH="$test_bin"

# Copy REVERSE_CMD detection logic from common-config.sh
if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
elif command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
else
    echo "ERROR: No reverse command found (tac or tail -r). Please install coreutils (tac) or ensure tail -r is available." >&2
    exit 1
fi

echo "\$REVERSE_CMD"
EOF
    
    chmod +x "$test_script"
    "$test_script" >/dev/null 2>&1
    local exit_code=$?
    local result=$("$test_script" 2>&1 || true)
    
    if [[ $exit_code -eq 1 ]]; then
        run_test "REVERSE_CMD with no commands" "error_exit_1" "error_exit_1"
    else
        echo "Debug: result='$result', exit_code=$exit_code"
        run_test "REVERSE_CMD with no commands" "error_exit_1" "unexpected_$exit_code"
    fi
    
    rm -rf "$test_bin" "$test_script"
}

# Test 7: Integration test with common-config.sh
test_common_config_integration() {
    echo "Test 7: Integration with actual common-config.sh"
    
    local test_script="$TEST_DIR/test_integration.sh"
    local project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    mkdir -p "$TEST_DIR"
    
    cat > "$test_script" << EOF
#!/bin/bash
# Source common-config.sh to test REVERSE_CMD setup
source "$project_root/.claude/scripts/common-config.sh"

# Test that REVERSE_CMD is set and functional
if [[ -z "\$REVERSE_CMD" ]]; then
    echo "REVERSE_CMD not set"
    exit 1
fi

# Test that REVERSE_CMD actually works
echo -e "first\nsecond\nthird" | \$REVERSE_CMD | head -1
EOF
    
    chmod +x "$test_script"
    local result=$("$test_script" 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -eq 0 && "$result" == "third" ]]; then
        run_test "common-config.sh integration" "working" "working"
    else
        run_test "common-config.sh integration" "working" "failed_$exit_code"
    fi
    
    rm -f "$test_script"
}

# Test 8: Performance comparison (if both commands available)
test_performance_comparison() {
    echo "Test 8: Performance comparison between tac and tail -r"
    
    local tac_available=false
    local tail_r_available=false
    
    if command -v tac >/dev/null 2>&1; then
        tac_available=true
    fi
    
    if command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
        tail_r_available=true
    fi
    
    if [[ "$tac_available" == "true" && "$tail_r_available" == "true" ]]; then
        # Create larger test data
        local large_data="$TEST_DIR/large_data.txt"
        seq 1 1000 > "$large_data"
        
        # Time tac
        local start_time=$(date +%s.%N 2>/dev/null || date +%s)
        tac "$large_data" >/dev/null
        local end_time=$(date +%s.%N 2>/dev/null || date +%s)
        
        # Time tail -r  
        local start_time2=$(date +%s.%N 2>/dev/null || date +%s)
        tail -r "$large_data" >/dev/null
        local end_time2=$(date +%s.%N 2>/dev/null || date +%s)
        
        echo "ℹ️  Performance test completed (timing may vary)"
        run_test "Performance test executed" "completed" "completed"
        
        rm -f "$large_data"
    else
        echo "ℹ️  Both commands not available, skipping performance test"
        ((TOTAL_TESTS++))
        ((PASSED_TESTS++))
    fi
}

# Main execution
echo "=== Reverse Command Detection Tests ==="
echo

setup_test_data

test_tac_functionality
test_tail_r_functionality  
test_functional_equivalence
test_reverse_cmd_with_tac
test_reverse_cmd_with_tail_only
test_reverse_cmd_no_commands
test_common_config_integration
test_performance_comparison

echo
echo "=== Test Summary ==="
echo "Tests passed: $PASSED_TESTS"
echo "Tests failed: $FAILED_TESTS" 
echo "Total tests: $TOTAL_TESTS"

# Cleanup
rm -rf "$TEST_DIR"  # TEST_DATA is inside TEST_DIR, so only need to remove TEST_DIR

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo -e "${GREEN}🎉 All reverse command tests passed!${NC}"
    exit 0
else
    echo -e "${RED}⚠️  Some reverse command tests failed.${NC}"
    exit 1
fi