#!/bin/bash
# Source common configuration
source "$(dirname "$0")/common-config.sh"
check_dependencies

# Quality Gate Trigger - Direct verdict approach
# Continues until quality-gate-keeper provides APPROVED verdict

LOG_FILE="/tmp/claude_quality_gate.log"

echo "=== Quality Gate Trigger ===" >> "$LOG_FILE"
echo "Time: $(date)" >> "$LOG_FILE"

# Read JSON input from stdin
input_json=$(cat)

# Log input JSON for debugging
echo "Input JSON: $input_json" >> "$LOG_FILE"

# Check if quality-gate-keeper has provided a result
transcript_path=$(echo "$input_json" | jq -r '.transcript_path')
if [[ -f "$transcript_path" ]]; then
    # Check retry limit first
    if count_attempts_since_last_reset_point "$transcript_path" 10; then
        echo "Maximum attempts reached after last reset point - auto-approving" >> "$LOG_FILE"
        echo "🔄 Quality gate auto-approved after 10 attempts. Consider reviewing the quality standards." >&2
        exit 0
    fi
    
    # Use common function to get quality result
    get_quality_result "$transcript_path"
    result_status=$?
    
    echo "Quality result status: $result_status" >> "$LOG_FILE"
    
    case $result_status in
        0)  # APPROVED
            echo "Quality gate APPROVED detected" >> "$LOG_FILE"
            echo "Quality gate completed successfully!" >> "$LOG_FILE"
            exit 0
            ;;
        1)  # REJECTED
            echo "Quality gate REJECTED detected - intervention required" >> "$LOG_FILE"
            # Don't exit 0, continue to prompt for fixes
            ;;
        2)  # No result
            echo "No quality result found - proceeding with quality gate" >> "$LOG_FILE"
            ;;
        3)  # No edits made
            echo "No edits detected - skipping quality gate" >> "$LOG_FILE"
            exit 0
            ;;
    esac
fi

# Check git availability and changes
if ! command -v git >/dev/null 2>&1; then
    echo "Git not available - proceeding with quality gate" >> "$LOG_FILE"
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    if [[ "${QUALITY_GATE_RUN_OUTSIDE_GIT}" == "true" ]]; then
        echo "Not in git repository - proceeding with quality gate (QUALITY_GATE_RUN_OUTSIDE_GIT=true)" >> "$LOG_FILE"
    else
        echo "Not in git repository - skipping quality gate (set QUALITY_GATE_RUN_OUTSIDE_GIT=true to run)" >> "$LOG_FILE"
        exit 0
    fi
elif [[ -z $(git status --porcelain 2>/dev/null) ]]; then
    echo "No git changes detected - skipping quality gate" >> "$LOG_FILE"
    exit 0
else
    echo "Git changes detected - proceeding with quality gate" >> "$LOG_FILE"
fi

# Trigger quality intervention with automatic subagent launch
echo "❌ STOP: Quality gate blocking session completion.
➡️ Step 1: Use Task tool with subagent_type='quality-gate-keeper' to review code quality
➡️ Step 2: Fix any issues identified by the quality gate keeper 
🔍 Purpose: Thorough code quality inspection required
🔄 This message repeats until proper quality review completed" >&2

echo "$(date): Quality gate intervention triggered" >> "$LOG_FILE"

# Exit with code 2 to provide feedback to Claude
exit 2
