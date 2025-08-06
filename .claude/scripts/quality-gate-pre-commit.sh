#!/bin/bash
# Source common configuration
source "$(dirname "$0")/common-config.sh"
check_dependencies

input_json=$(cat)
command=$(echo "$input_json" | jq -r '.tool_input.command')

if [[ "$command" =~ git[[:space:]]+commit ]]; then
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
            echo "Please use the Task tool with subagent_type='quality-gate-keeper' to address and fix the issues" >&2
            exit 2
            ;;
        2)  # No verdict found
            echo "🔍 Quality check required. Please use the Task tool with subagent_type='quality-gate-keeper' to perform quality inspection" >&2
            exit 2
            ;;
    esac
fi

exit 0
