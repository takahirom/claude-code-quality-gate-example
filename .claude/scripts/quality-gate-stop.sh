#!/bin/bash
# Source common configuration
source "$(dirname "$0")/common-config.sh"
check_dependencies

# Quality Gate Trigger - Passphrase approach
# Continues until Claude says the magic phrase

LOG_FILE="/tmp/claude_quality_gate.log"

echo "=== Quality Gate Trigger ===" >> "$LOG_FILE"
echo "Time: $(date)" >> "$LOG_FILE"

# Read JSON input from stdin
input_json=$(cat)

# Log input JSON for debugging
echo "Input JSON: $input_json" >> "$LOG_FILE"

# Check if Claude said the magic passphrase in recent transcript
transcript_path=$(echo "$input_json" | jq -r '.transcript_path')
if [[ -f "$transcript_path" ]]; then
    # Check only the last line of transcript for the passphrase
    # Note: Using grep -q instead of grep -qw because -w doesn't work correctly with JSON content
    if tail -n 1 "$transcript_path" | grep -q "$PASSPHRASE"; then
        echo "Magic passphrase detected: '$PASSPHRASE'" >> "$LOG_FILE"
        echo "Quality gate completed successfully!" >> "$LOG_FILE"
        exit 0
    fi
fi

# Check git availability and changes
if ! command -v git >/dev/null 2>&1; then
    echo "Git not available - proceeding with quality gate" >> "$LOG_FILE"
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Not in git repository - proceeding with quality gate" >> "$LOG_FILE"
elif [[ -z $(git status --porcelain 2>/dev/null) ]]; then
    echo "No git changes detected - skipping quality gate" >> "$LOG_FILE"
    exit 0
else
    echo "Git changes detected - proceeding with quality gate" >> "$LOG_FILE"
fi

# Trigger quality intervention with automatic subagent launch
echo "✅ Work completion detected. Use Task tool with subagent_type='quality-gate-keeper' to perform quality inspection, fix issues, then say: '$PASSPHRASE'" >&2

echo "$(date): Quality gate intervention triggered" >> "$LOG_FILE"

# Exit with code 2 to provide feedback to Claude
exit 2