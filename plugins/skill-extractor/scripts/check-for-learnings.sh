#!/bin/bash

# Read input from stdin
input=$(cat)

# Check if this is already a continuation from previous stop hook (prevent infinite loop)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')
if [ "$stop_hook_active" = "true" ]; then
    # Already ran skill extraction, allow stop
    exit 0
fi

# Get transcript path
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    # No transcript available, allow stop
    exit 0
fi

# Check if transcript has meaningful content (more than just a few exchanges)
line_count=$(wc -l < "$transcript_path" | tr -d ' ')
if [ "$line_count" -lt 10 ]; then
    # Too short, probably not worth extracting
    exit 0
fi

# Check if skill extraction was already done in this session
if grep -q "skill-extractor" "$transcript_path" 2>/dev/null; then
    # Already extracted skills, allow stop
    exit 0
fi

# Suggest skill extraction with transcript path
echo "{\"decision\": \"block\", \"reason\": \"Consider extracting learnings from this session. Use the skill-extractor agent to analyze the conversation at $transcript_path and save valuable patterns as skills.\"}"
