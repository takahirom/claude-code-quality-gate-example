#!/bin/bash
# Source common configuration
source "$(dirname "$0")/common-config.sh"
check_dependencies

input_json=$(cat)
command=$(echo "$input_json" | jq -r '.tool_input.command')

if [[ "$command" =~ (^|[[:space:];&|])git[[:space:]]+.*commit([[:space:]]|$) ]]; then
    transcript_path=$(echo "$input_json" | jq -r '.transcript_path')
    
    # Use common function to get quality result
    get_quality_result "$transcript_path"
    result_status=$?
    
    case $result_status in
        0)  # APPROVED
            echo "✅ Quality gate approved - allowing commit" >&2
            exit 0
            ;;
        1)  # REJECTED
            echo "❌ Quality gate REJECTED - commit blocked due to critical issues" >&2
            echo "Step 1: Use Task tool with subagent_type='quality-gate-keeper' to review and identify issues" >&2
            echo "Step 2: Fix any issues identified by the quality gate keeper" >&2
            echo "Step 3: Use Task tool with subagent_type='quality-gate-keeper' to review the fixes" >&2
            echo "Step 4: Commit when you get APPROVED status" >&2
            exit 2
            ;;
        2)  # No verdict found
            echo "🔍 Quality check required:" >&2
            echo "Step 1: Use Task tool with subagent_type='quality-gate-keeper' to perform quality inspection" >&2
            echo "Step 2: Fix any issues identified by the quality gate keeper" >&2
            echo "Step 3: Use Task tool with subagent_type='quality-gate-keeper' to review the fixes" >&2
            echo "Step 4: Commit when you get APPROVED status" >&2
            exit 2
            ;;
        3)  # No edits made
            echo "✅ No edits detected - allowing commit" >&2
            exit 0
            ;;
    esac
fi

exit 0
