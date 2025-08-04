#!/bin/bash
# Debug script to check actual transcript format

# Use provided path or default
transcript_path="${1:-~/.claude/projects/*/hook-experiment/*.jsonl}"

if [[ ! -f "$transcript_path" ]]; then
    echo "Usage: $0 [transcript_path]"
    echo "Error: Transcript file not found: $transcript_path"
    exit 1
fi

echo "Analyzing transcript: $transcript_path"

echo "=== Checking for any messages containing APPROVED ==="
grep -n "APPROVED" "$transcript_path" | head -5

echo -e "\n=== Checking actual message structure around APPROVED ==="
grep -A3 -B3 "APPROVED" "$transcript_path" | head -15 | jq -s '.[0] // empty' 2>/dev/null || echo "Not valid JSON"

echo -e "\n=== Checking for Task tool usage patterns ==="
grep -n "quality-gate-keeper" "$transcript_path" | wc -l
echo "quality-gate-keeper mentions found"

echo -e "\n=== Looking for Final Result patterns ==="
grep -n "Final Result" "$transcript_path" | head -3

echo -e "\n=== Check if there are any sidechain messages ==="
grep -c "\"isSidechain\":true" "$transcript_path"

echo -e "\n=== get_quality_result Function Debug ==="
source "$(dirname "$0")/.claude/scripts/common-config.sh"

echo "Testing get_quality_result function..."
get_quality_result "$transcript_path"
result_code=$?
echo "Result code: $result_code (0=APPROVED, 1=REJECTED, 2=No result)"

echo -e "\n=== Most Recent Final Result Analysis ==="
echo "Finding most recent 'Final Result:' line..."
result_info=$(tac "$transcript_path" | nl -nrn | grep -m1 "Final Result:" | head -1)
if [[ -n "$result_info" ]]; then
    line_num=$(echo "$result_info" | cut -f1)
    echo "Most recent Final Result found at reverse line: $line_num"
    echo "JSON line:"
    echo "$result_info" | cut -f2- | jq '.'
    
    echo -e "\nChecking if it's sidechain:"
    echo "$result_info" | cut -f2- | jq -r '.isSidechain // "not set"'
    
    echo -e "\nChecking if it has toolUseResult string:"
    echo "$result_info" | cut -f2- | jq -e '.toolUseResult | type == "string"' >/dev/null 2>&1 && echo "Yes, has string toolUseResult" || echo "No string toolUseResult"
    
    echo -e "\nContent analysis:"
    if echo "$result_info" | cut -f2- | jq -e '.isSidechain == true' >/dev/null 2>&1; then
        echo "This is a SIDECHAIN message"
        content=$(echo "$result_info" | cut -f2- | jq -r '.message.content[]?.text // empty' 2>/dev/null | tr '\n' ' ')
        echo "Content: $content"
    elif echo "$result_info" | cut -f2- | jq -e '.toolUseResult | type == "string"' >/dev/null 2>&1; then
        echo "This is a TOOL RESULT message"
        content=$(echo "$result_info" | cut -f2- | jq -r '.toolUseResult' 2>/dev/null)
        echo "Content: $content"
    else
        echo "This is a REGULAR message (should be ignored by fixed implementation)"
        echo "Command/Description contains 'Final Result:' but not actual quality result"
    fi
    
    echo -e "\nResult status check:"
    if echo "$content" | grep -q "✅ APPROVED"; then
        echo "Contains: ✅ APPROVED"
    elif echo "$content" | grep -q "❌ REJECTED"; then
        echo "Contains: ❌ REJECTED"
    else
        echo "No clear APPROVED/REJECTED status found"
    fi
else
    echo "No 'Final Result:' found in transcript"
fi

echo -e "\n=== Recent Sidechain Messages with Final Result ==="
echo "Looking for sidechain messages with Final Result..."
tac "$transcript_path" | jq -r 'select(.isSidechain == true) | select(.message.content[]?.text | test("Final Result:")) | "Line: \(.uuid // "unknown") | Content: \(.message.content[]?.text)"' 2>/dev/null | head -3 || echo "No sidechain Final Result messages found"