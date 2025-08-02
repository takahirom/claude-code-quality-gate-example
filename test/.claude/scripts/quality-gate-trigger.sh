#!/bin/bash

# Quality Gate Trigger - Passphrase approach
# Continues until Claude says the magic phrase

LOG_FILE="/tmp/claude_quality_gate.log"

echo "=== Quality Gate Trigger ===" >> "$LOG_FILE"
echo "Time: $(date)" >> "$LOG_FILE"

# Magic passphrase to stop quality gate
PASSPHRASE="I've addressed all the quality gatekeeper requests"

# Read JSON input from stdin
input_json=$(cat)
session_id=$(echo "$input_json" | jq -r '.session_id')

# Log input JSON for debugging
echo "Input JSON: $input_json" >> "$LOG_FILE"

# Check if Claude said the magic passphrase in recent transcript
transcript_path=$(echo "$input_json" | jq -r '.transcript_path')
if [[ -f "$transcript_path" ]]; then
    # Check only the last line of transcript for the passphrase
    if tail -n 1 "$transcript_path" | grep -q "$PASSPHRASE"; then
        echo "Magic passphrase detected: '$PASSPHRASE'" >> "$LOG_FILE"
        echo "Quality gate completed successfully!" >> "$LOG_FILE"
        exit 0
    fi
fi

# Check if git is available and we're in a git repo
if ! command -v git >/dev/null 2>&1 || ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Git not available or not in git repository - proceeding with quality gate" >> "$LOG_FILE"
else
    # Check if there are any git changes
    if ! git diff --quiet HEAD 2>/dev/null || ! git diff --quiet --cached 2>/dev/null; then
        echo "Git changes detected - proceeding with quality gate" >> "$LOG_FILE"
    else
        echo "No git changes detected - skipping quality gate" >> "$LOG_FILE"
        exit 0
    fi
fi

# Trigger quality intervention
echo "✅ Work completion detected. Please launch quality-gate-keeper Agent to perform quality inspection." >&2
echo "🔧 Then implement all recommended fixes immediately without asking." >&2
echo "💡 When all fixes are complete, please say: '$PASSPHRASE'" >&2

echo "$(date): Quality gate intervention triggered" >> "$LOG_FILE"

# Exit with code 2 to provide feedback to Claude
exit 2