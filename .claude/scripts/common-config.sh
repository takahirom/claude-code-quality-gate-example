#!/bin/bash
# Common configuration for quality gate scripts

# Configurable pattern for file editing tools (for MCP compatibility)
EDIT_TOOLS_PATTERN="${EDIT_TOOLS_PATTERN:-^(Write|Edit|MultiEdit|NotebookEdit)$}"

# Check dependencies function
check_dependencies() {
    for cmd in jq git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ Required dependency '$cmd' not found" >&2
            exit 1
        fi
    done
}

# Get the most recent quality-gate-keeper result from transcript
# Returns: 0 if APPROVED, 1 if REJECTED, 2 if no result found
get_quality_result() {
    local transcript_path="$1"
    
    if [[ ! -f "$transcript_path" ]]; then
        return 2
    fi
    
    # Find all Final Result occurrences in sidechain messages
    local last_result=""
    local last_result_line=0
    local line_num=0
    
    while IFS= read -r line; do
        ((line_num++))
        # Check if line contains sidechain message with Final Result
        if echo "$line" | jq -e '.isSidechain == true' >/dev/null 2>&1; then
            local content=$(echo "$line" | jq -r '.message.content[]?.text // empty' 2>/dev/null)
            if [[ -n "$content" ]] && echo "$content" | grep -q "Final Result:"; then
                last_result="$content"
                last_result_line=$line_num
            fi
        fi
    done < "$transcript_path"
    
    # No Final Result found
    if [[ -z "$last_result" ]]; then
        return 2
    fi
    
    # Check result status
    if echo "$last_result" | grep -q "✅ APPROVED"; then
        # Check for file edits after approval
        if tail -n +$((last_result_line + 1)) "$transcript_path" | \
           jq -r 'select(.message.content[]?.name) | .message.content[]?.name' 2>/dev/null | \
           grep -qE "$EDIT_TOOLS_PATTERN"; then
            return 2  # Stale approval
        fi
        return 0  # APPROVED
    elif echo "$last_result" | grep -q "❌ REJECTED"; then
        return 1  # REJECTED
    else
        return 2  # No result
    fi
}
