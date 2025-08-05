#!/bin/bash

# Check dependencies
for cmd in claude node jq git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Required dependency '$cmd' not found" >&2
        exit 1
    fi
done

echo "=== Isolated E2E Test for Claude Code Work Completion Detection ==="
echo "Date: $(date)"
echo ""

# Setup
TEST_DIR="$(cd "$(dirname "$0")/e2e-test-sandbox" && pwd)"
cd "$TEST_DIR" || exit 1

# Step 1: Cleanup
echo "Step 1: Cleanup previous test"
rm -f Test.js /tmp/claude_test_session_state* /tmp/intervention_in_progress
rm -f /tmp/claude_work_completion.log /tmp/claude_session_tracker.log
rm -rf .claude  # Remove previous test .claude directory
echo "✓ Cleanup complete"
echo ""

# Step 1.5: Copy .claude directory for test
echo "Step 1.5: Setting up test .claude directory"  
cp -r ../../.claude .
echo "✓ .claude directory copied for test"
echo ""

# Step 2: Baseline measurement
echo "Step 2: Baseline measurement"
echo "Test files in test directory:"
find . -name "*.test.*" -o -name "*.spec.*" -o -name "Test.js" | wc -l
echo ""

# Step 3: The critical test - single Claude command
echo "Step 3: Critical test - Single Claude command execution"
echo "Command: 'I am building a Claude Code Hook system with Gate Keeper functionality. Please create Test.js that requires ./Calculator, creates a new Calculator instance, and calls the add() method but does not execute any assertions. Expected behavior: Hook will tell you to call a SubAgent. (Do not call SubAgent yourself until told to do so) When prompted, follow the SubAgent's instructions to add assertions. Only modify Test.js, nothing else.'"
echo ""

# Execute the main test
timeout 300 claude -p << 'EOF'
I am building a Claude Code Hook system with Gate Keeper functionality. Please create Test.js that requires ./Calculator, creates a new Calculator instance, and calls the add() method but does not execute any assertions. Expected behavior: Hook will tell you to call a SubAgent. (Do not call SubAgent yourself until told to do so) When prompted, follow the SubAgent's instructions to add assertions. Only modify Test.js, nothing else.
EOF

echo "✓ Claude execution completed"
echo ""

# Step 5: Immediate verification
echo "Step 5: Immediate post-execution verification"
echo "Test.js exists:"
if [[ -f "Test.js" ]]; then
    echo "✅ YES"
    echo "Test.js content:"
    cat Test.js
else
    echo "❌ NO"
    echo "Debugging - Current directory contents:"
    ls -la
    exit 1
fi
echo ""

# Step 5.5: Test execution verification
echo "Step 5.5: Test execution verification"
if [[ -f "Test.js" ]]; then
    echo "Executing Test.js:"
    node Test.js > /tmp/test-execution-output.txt 2>&1
    test_exit_code=$?
    cat /tmp/test-execution-output.txt
    echo "Test exit code: $test_exit_code"
    
    # Validate test execution success
    if [[ $test_exit_code -eq 0 ]]; then
        echo "✅ Test executed successfully"
        
        # Verify test actually contains assertions (anti-cheat)
        # Calculate assertion count now
        assert_count=$(grep -c "expect(\|assert(\|assert\.\|should\." Test.js 2>/dev/null)
        
        # If test exits with 0 and contains assertions in the code, it's valid
        if [[ $assert_count -gt 0 ]]; then
            echo "✅ Test contains real assertions and passed verification"
        else
            echo "❌ Test lacks proper assertions"
            echo "Test output analysis:"
            head -5 /tmp/test-execution-output.txt
        fi
    else
        echo "❌ Test execution failed with exit code: $test_exit_code"
        exit 1
    fi
else
    echo "❌ Cannot execute test - file missing"
    exit 1
fi
echo ""

# Step 6: Hook execution verification
echo "Step 6: Hook execution verification"
echo "Quality gate log:"
if [[ -f "/tmp/claude_quality_gate.log" ]]; then
    cat /tmp/claude_quality_gate.log
else
    echo "❌ No quality gate log found"
    exit 1
fi
echo ""

# Step 7: Quality intervention verification
echo "Step 7: Quality intervention verification"
echo "Quality intervention request:"
if [[ -f "/tmp/quality_intervention_request.txt" ]]; then
    echo "✅ Quality intervention triggered!"
    cat /tmp/quality_intervention_request.txt
else
    echo "❌ No quality intervention request found"
fi
echo ""

# Step 8: Assertion verification
echo "Step 8: Final assertion verification"
if [[ -f "Test.js" ]]; then
    console_count=$(grep -c "console\.log" Test.js 2>/dev/null)
    assert_count=$(grep -c "expect(\|assert(\|assert\.\|should\." Test.js 2>/dev/null)
    
    echo "Console.log count: $console_count"
    echo "Assertion count: $assert_count"
    
    if [[ $assert_count -gt 0 ]]; then
        echo "✅ SUCCESS: Assertions found (intervention worked!)"
        if [[ $console_count -gt 0 ]]; then
            echo "ℹ️ INFO: Test also contains console.log statements"
        fi
    elif [[ $console_count -gt 0 ]]; then
        echo "🚨 DETECTED: Console-only test (should trigger intervention)"
    else
        echo "❓ UNCLEAR: No console.log or assertions found"
    fi
else
    echo "❌ FAILED: No Test.js file created"
    exit 1
fi

echo ""
echo "=== E2E Test Summary ==="
echo "Test execution logs: /tmp/e2e-main-execution.txt"
echo "Quality gate log: /tmp/claude_quality_gate.log"
echo ""
echo "Expected workflow:"
echo "1. Claude creates Test.js with minimal assertions"
echo "2. Stop hook triggers quality gate on completion"
echo "3. Quality intervention message appears"
echo "4. (SubAgent would execute in real scenario)"
echo ""

if [[ -f "Test.js" ]] && [[ -f "/tmp/claude_quality_gate.log" ]] && [[ -f "/tmp/test-execution-output.txt" ]]; then
    echo "🎉 E2E TEST SUCCESSFUL: Complete workflow with test execution detected!"
    test_result=0
else
    echo "⚠️ E2E TEST INCOMPLETE: Missing test execution verification"
    test_result=1
fi

# Finally: Cleanup generated Test.js to avoid git tracking issues
echo ""
echo "=== Cleanup ==="
if [[ -f "Test.js" ]]; then
    echo "Removing generated Test.js file..."
    rm -f Test.js
    echo "✓ Test.js cleaned up"
else
    echo "No Test.js to clean up"
fi

exit $test_result
