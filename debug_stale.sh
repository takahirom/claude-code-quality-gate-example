#!/bin/bash
# Debug stale approval detection
source .claude/scripts/common-config.sh

transcript_path="$1"
if [[ ! -f "$transcript_path" ]]; then
    echo "Transcript not found: $transcript_path"
    exit 1
fi

echo "=== Debugging stale approval ==="

# Find the most recent Final Result
total_lines=$(wc -l < "$transcript_path")
result_info=$($REVERSE_CMD "$transcript_path" | nl -nrn | grep "Final Result:" | head -10 | while read -r line; do
    if echo "$line" | cut -f2- | jq -e '.isSidechain == true or .toolUseResult' >/dev/null 2>&1; then
        echo "$line"
        break
    fi
done | head -1)

if [[ -n "$result_info" ]]; then
    reverse_line_num=$(echo "$result_info" | cut -f1)
    line=$(echo "$result_info" | cut -f2-)
    last_result_line=$((total_lines - reverse_line_num + 1))
    
    echo "Found Final Result at line: $last_result_line"
    
    # Extract the result content
    if echo "$line" | jq -e '.isSidechain == true' >/dev/null 2>&1; then
        last_result=$(extract_message_content "$line")
    elif echo "$line" | jq -e '.toolUseResult' >/dev/null 2>&1; then
        tool_result_content=$(extract_tool_use_result_content "$line")
        if [[ -n "$tool_result_content" ]] && echo "$tool_result_content" | grep -q "Final Result:"; then
            last_result="$tool_result_content"
        fi
    fi
    
    echo "Result content: $last_result"
    
    if echo "$last_result" | grep -qE "✅.*APPROVED"; then
        echo "✅ APPROVED found"
        
        # Check for edits after this line
        if has_edits_after_line "$transcript_path" "$last_result_line"; then
            echo "❌ STALE: Edits found after approval line $last_result_line"
            
            echo "=== Edit tools found after line $last_result_line ==="
            tail -n +$((last_result_line + 1)) "$transcript_path" | \
                jq -r '
                  select((.message.content | type) == "array")               
                  | .message.content[]
                  | select(.type == "tool_use" and (.name // empty) != "")   
                  | .name
                ' 2>/dev/null | grep -E "$QUALITY_GATE_EDIT_TOOLS_PATTERN"
        else
            echo "✅ FRESH: No edits after approval"
        fi
    else
        echo "No APPROVED status found"
    fi
else
    echo "No Final Result found"
fi