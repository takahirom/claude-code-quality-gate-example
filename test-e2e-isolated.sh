#!/bin/bash

echo "=== Isolated E2E Test for Claude Code Work Completion Detection ==="
echo "Date: $(date)"
echo ""

# Setup
TEST_DIR="$(cd "$(dirname "$0")/test" && pwd)"
cd "$TEST_DIR"

# Step 1: Doctor check with isolated settings
echo "Step 1: Doctor check with isolated settings"
timeout 5 claude "/doctor" > /tmp/e2e-doctor-check.txt 2>&1
echo "✓ Doctor result:"
cat /tmp/e2e-doctor-check.txt
echo ""

# Step 2: Cleanup
echo "Step 2: Cleanup previous test"
rm -f Test.js /tmp/claude_test_session_state* /tmp/intervention_in_progress
rm -f /tmp/claude_work_completion.log /tmp/claude_session_tracker.log
echo "✓ Cleanup complete"
echo ""

# Step 3: Baseline measurement
echo "Step 3: Baseline measurement"
echo "Test files in test directory:"
find . -name "*.test.*" -o -name "*.spec.*" -o -name "Test.js" | wc -l
echo ""

# Step 4: The critical test - single Claude command
echo "Step 4: Critical test - Single Claude command execution"
echo "Command: 'I am building a Claude Code Hook system with Gate Keeper functionality. Please create Test.js that calls Calculator.add() but does not execute any assertions. Expected behavior: Hook will tell you to call a SubAgent. (Do not call SubAgent yourself until told to do so) When prompted, follow the SubAgent's instructions to add assertions. Only modify Test.js, nothing else.'"
echo ""

# Execute the main test
timeout 300 echo "I am building a Claude Code Hook system with Gate Keeper functionality. Please create Test.js that calls Calculator.add() but does not execute any assertions. Expected behavior: Hook will tell you to call a SubAgent. (Do not call SubAgent yourself until told to do so) When prompted, follow the SubAgent's instructions to add assertions. Only modify Test.js, nothing else.\n" | claude -p

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
fi
echo ""

# Step 6: Hook execution verification
echo "Step 6: Hook execution verification"
echo "Quality gate log:"
if [[ -f "/tmp/claude_quality_gate.log" ]]; then
    cat /tmp/claude_quality_gate.log
else
    echo "❌ No quality gate log found"
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
    assert_count=$(grep -c "expect(\|assert(\|should\." Test.js 2>/dev/null)
    
    # Ensure numeric values
    console_count=${console_count:-0}
    assert_count=${assert_count:-0}
    
    echo "Console.log count: $console_count"
    echo "Assertion count: $assert_count"
    
    if [[ $console_count -gt 0 && $assert_count -eq 0 ]]; then
        echo "🚨 DETECTED: Console-only test (should trigger intervention)"
    elif [[ $assert_count -gt 0 ]]; then
        echo "✅ SUCCESS: Assertions found (intervention worked!)"
    else
        echo "❓ UNCLEAR: No console.log or assertions found"
    fi
else
    echo "❌ FAILED: No Test.js file created"
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

if [[ -f "Test.js" ]] && [[ -f "/tmp/claude_quality_gate.log" ]]; then
    echo "🎉 E2E TEST SUCCESSFUL: Complete workflow detected!"
else
    echo "⚠️ E2E TEST INCOMPLETE: Check logs for issues"
fi
