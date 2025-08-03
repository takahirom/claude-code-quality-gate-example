#!/bin/bash
# Source common configuration
source "$(dirname "$0")/common-config.sh"
check_dependencies

input_json=$(cat)
command=$(echo "$input_json" | jq -r '.tool_input.command')

if [[ "$command" =~ git[[:space:]]+commit ]]; then
    # PASSPHRASE defined at top of file
    
    # Check if Claude said the magic passphrase in recent transcript
    transcript_path=$(echo "$input_json" | jq -r '.transcript_path')
    if [[ -f "$transcript_path" ]]; then
        # Check the last 2 lines - the last line will be the commit command, so passphrase is in the 2nd to last
        # Note: Using grep -q instead of grep -qw because -w doesn't work correctly with JSON content
        if tail -n 2 "$transcript_path" | grep -q "$PASSPHRASE"; then
            echo "Magic passphrase detected - allowing commit" >&2
            exit 0
        fi
    fi
    
    echo "🔍 Quality check required. Use Task tool with subagent_type='quality-gate-keeper', fix issues, then say: '$PASSPHRASE' and retry commit" >&2
    exit 2
fi

exit 0