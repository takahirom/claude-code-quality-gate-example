#!/bin/bash
# Common configuration for quality gate scripts

# Check for required commands
if ! command -v nl >/dev/null 2>&1; then
    echo "ERROR: nl command not found. Please install coreutils package." >&2
    exit 1
fi
# Determine reverse command (tac on GNU, tail -r on BSD/macOS)
if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
elif command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
else
    echo "ERROR: No reverse command found (tac or tail -r). Please install coreutils (tac) or ensure tail -r is available." >&2
    exit 1
fi

# Run quality gate outside git repositories (default: false)
# Set to true to enable quality gate checks in non-git directories
QUALITY_GATE_RUN_OUTSIDE_GIT="${QUALITY_GATE_RUN_OUTSIDE_GIT:-false}"

# Configurable pattern for file editing tools (for MCP compatibility)
# Support both old and new variable names for backward compatibility
# Includes standard tools and serena MCP tools
QUALITY_GATE_EDIT_TOOLS_PATTERN="${QUALITY_GATE_EDIT_TOOLS_PATTERN:-${EDIT_TOOLS_PATTERN:-(Write|Edit|MultiEdit|NotebookEdit|replace_regex|replace_symbol_body|insert_after_symbol|insert_before_symbol|mcp__serena__(replace_regex|replace_symbol_body|insert_after_symbol|insert_before_symbol))}}"

# Check dependencies function
check_dependencies() {
    for cmd in jq git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ Required dependency '$cmd' not found" >&2
            exit 1
        fi
    done
}

# Helper: Check for edits after given line number
has_edits_after_line() {
    local transcript_path="$1"
    local line_number="$2"
    
    tail -n +$((line_number + 1)) "$transcript_path" | \
        jq -r 'select(.message.content[]?.name) | .message.content[]?.name' 2>/dev/null | \
        grep -qE "$QUALITY_GATE_EDIT_TOOLS_PATTERN"
}

# Get the most recent quality-gate-keeper result from transcript
# Returns: 0 if APPROVED, 1 if REJECTED, 2 if no result found
get_quality_result() {
    local transcript_path="$1"
    
    if [[ ! -f "$transcript_path" ]]; then
        return 2
    fi
    
    # Find the most recent Final Result using reverse search (performance optimized)
    local last_result=""
    local last_result_line=0
    local total_lines
    total_lines=$(wc -l < "$transcript_path")
    
    # Find most recent Final Result from sidechain or toolUseResult only
    # This prevents interference from ongoing Bash commands containing "Final Result:"
    local result_info
    result_info=$($REVERSE_CMD "$transcript_path" | nl -nrn | grep "Final Result:" | while read -r line; do
        # Only check jq for lines that contain Final Result
        if echo "$line" | cut -f2- | jq -e '.isSidechain == true or (.toolUseResult | type == "string")' >/dev/null 2>&1; then
            echo "$line"
            break
        fi
    done | head -1)
    
    if [[ -n "$result_info" ]]; then
        local reverse_line_num
        reverse_line_num=$(echo "$result_info" | cut -f1)
        local line
        line=$(echo "$result_info" | cut -f2-)
        last_result_line=$((total_lines - reverse_line_num + 1))
        
        # Determine result type and extract content
        if echo "$line" | cut -f2- | jq -e '.isSidechain == true' >/dev/null 2>&1; then
            last_result=$(extract_message_content "$line")
        elif echo "$line" | cut -f2- | jq -e '.toolUseResult | type == "string"' >/dev/null 2>&1; then
            local tool_result_content
            tool_result_content=$(echo "$line" | jq -r '.toolUseResult' 2>/dev/null)
            if [[ -n "$tool_result_content" ]] && echo "$tool_result_content" | grep -q "Final Result:"; then
                last_result="$tool_result_content"
            fi
        fi
    fi
    
    # Check for user APPROVE message (optimized)
    local user_approve_line=0
    local user_approve
    user_approve=$($REVERSE_CMD "$transcript_path" | nl -nrn | while read -r line; do
        # Quick pre-check to avoid jq calls on non-user lines
        if [[ "$line" == *'"type":"user"'* ]]; then
            local json_data
            json_data=$(echo "$line" | cut -f2-)
            # Use the helper function to extract content
            local content
            content=$(extract_user_content "$json_data")
            
            # Check for explicit APPROVE token (case-insensitive, trimmed)
            # This prevents false positives like "I do not approve"
            if [[ -n "$content" ]] && echo "$content" | grep -qiE '^[[:space:]]*APPROVE[[:space:]]*$'; then
                echo "$line" | cut -f1
                break
            fi
        fi
    done | head -1)
    
    if [[ -n "$user_approve" ]]; then
        user_approve_line=$((total_lines - user_approve + 1))
        
        # User APPROVE is valid if: no Final Result OR it comes after Final Result
        if [[ -z "$last_result" ]] || [[ $user_approve_line -gt $last_result_line ]]; then
            # Check for stale approval (edits after user APPROVE)
            if has_edits_after_line "$transcript_path" "$user_approve_line"; then
                return 2  # Stale approval
            fi
            return 0  # User APPROVED
        fi
    fi
    
    # No Final Result found and no user APPROVE
    if [[ -z "$last_result" ]]; then
        # Check if any edits have been made in the session
        if ! jq -r 'select(.message.content[]?.name) | .message.content[]?.name' "$transcript_path" 2>/dev/null | \
           grep -qE "$QUALITY_GATE_EDIT_TOOLS_PATTERN"; then
            # No edits made, skip quality gate
            return 3  # New return code for "no edits"
        fi
        return 2
    fi
    
    # Check result status
    if echo "$last_result" | grep -q "✅ APPROVED"; then
        # Check for file edits after approval
        if has_edits_after_line "$transcript_path" "$last_result_line"; then
            return 2  # Stale approval
        fi
        return 0  # APPROVED
    elif echo "$last_result" | grep -q "❌ REJECTED"; then
        return 1  # REJECTED
    else
        return 2  # No result
    fi
}

# Helper function to extract user content from a JSON line
# Handles both string and array formats
# Input: JSON line (from transcript)
# Output: extracted text content or empty string
extract_user_content() {
    local json_line="$1"
    echo "$json_line" | jq -r '
        if (.message.content | type) == "string" then
            .message.content
        elif (.message.content | type) == "array" then
            .message.content[] | select(.type == "text") | .text // empty
        else
            empty
        end' 2>/dev/null
}

# Helper function to extract content from transcript line (deprecated - use extract_user_content)
# Returns extracted content or empty string
extract_message_content() {
    local line="$1"
    echo "$line" | jq -r '.message.content[]?.text // empty' 2>/dev/null | tr '\n' ' '
}

# Count attempts since last reset point (approval or user input) in transcript
# Returns: 0 if max attempts reached, 1 otherwise
count_attempts_since_last_reset_point() {
    local transcript_path="$1"
    local max_attempts="${2:-10}"  # Default 10 attempts
    
    if [[ ! -f "$transcript_path" ]]; then
        return 1  # Continue if no transcript file
    fi
    
    # Find last APPROVED result and user input using reverse search
    # Find last APPROVED result line number using reverse search
    local last_approved_line=0
    local approved_result
    approved_result=$($REVERSE_CMD "$transcript_path" | nl -nrn | grep "Final Result: ✅ APPROVED" | while read -r line; do
        if echo "$line" | cut -f2- | jq -e '.isSidechain == true or (.toolUseResult | type == "string")' >/dev/null 2>&1; then
            echo "$line" | cut -f1  # Return line number
            break
        fi
    done | head -1)
    
    if [[ -n "$approved_result" ]]; then
        local total_lines
        total_lines=$(wc -l < "$transcript_path")
        last_approved_line=$((total_lines - approved_result + 1))
    fi
    
    # Find last user input line number using reverse search (optimized)
    local last_user_input_line=0
    local user_result
    user_result=$($REVERSE_CMD "$transcript_path" | nl -nrn | while read -r line; do
        # Quick pre-check to avoid processing non-user lines
        if [[ "$line" == *'"type":"user"'* ]]; then
            local json_data
            json_data=$(echo "$line" | cut -f2-)
            local content
            content=$(extract_user_content "$json_data")
            if [[ -n "$content" ]] && ! echo "$content" | grep -q "Quality gate blocking session completion"; then
                echo "$line" | cut -f1  # Return line number
                break
            fi
        fi
    done | head -1)
    
    if [[ -n "$user_result" ]]; then
        local total_lines
        total_lines=$(wc -l < "$transcript_path")
        last_user_input_line=$((total_lines - user_result + 1))
    fi
    
    # Determine start line: MAX(last_approved_line, last_user_input_line)
    local start_line=0
    if [[ $last_approved_line -gt $last_user_input_line ]]; then
        start_line=$last_approved_line
    else
        start_line=$last_user_input_line
    fi
    
    # Count Stop hook messages after start line
    # Stop hook messages appear in tool_use commands within assistant messages
    local attempt_count=0
    local temp_transcript="/tmp/filtered_transcript.jsonl"
    
    if [[ $start_line -gt 0 ]]; then
        # Extract lines after start_line
        tail -n +$((start_line + 1)) "$transcript_path" > "$temp_transcript"
    else
        # No APPROVED or user input found, use entire transcript
        cp "$transcript_path" "$temp_transcript"
    fi
    
    # Count Stop hook messages - use simple grep approach (most reliable)
    local raw_count
    raw_count=$(grep -c "Quality gate blocking session completion" "$temp_transcript" 2>/dev/null || echo 0)
    attempt_count=$(echo "$raw_count" | head -1 | tr -d ' \n\r')
    
    rm -f "$temp_transcript"
    
    # Log only if LOG_FILE is set
    if [[ -n "$LOG_FILE" ]]; then
        echo "Attempt count since MAX(last_approved_line=$last_approved_line, last_user_input_line=$last_user_input_line): [$attempt_count] (max: $max_attempts)" >> "$LOG_FILE"
    fi
    
    if [[ $attempt_count -ge $max_attempts ]]; then
        return 0  # Max attempts reached
    else
        return 1  # Can continue
    fi
}
