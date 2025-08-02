#!/bin/bash

input_json=$(cat)
command=$(echo "$input_json" | jq -r '.tool_input.command')

if [[ "$command" =~ git[[:space:]]+commit ]]; then
    if echo "$command" | grep -q '🤖 Generated with'; then
        echo "Error: Commit message contains AI signature. Please remove it before committing." >&2
        exit 2
    fi
    
    echo "🔍 Pre-commit quality check triggered. Please launch quality-gate-keeper Agent to inspect staged changes." >&2
    echo "🔧 Fix any issues before committing." >&2
    echo "💡 When fixes are complete, say: 'I've addressed all the quality gatekeeper requests'" >&2
    exit 2
fi

exit 0