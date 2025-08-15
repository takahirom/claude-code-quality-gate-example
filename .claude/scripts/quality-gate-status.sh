#!/bin/bash
# Quality gate status reporter for shell integration
# Returns: APPROVED, REJECTED, PENDING, or DISABLED
# With --emoji: ✅, ❌, ⏳, or 🔒
# Exit codes: 0 for success, 1 for errors

# Parse command line arguments
EMOJI_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --emoji)
            EMOJI_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--emoji]" >&2
            exit 1
            ;;
    esac
done

# Default transcript path
TRANSCRIPT_PATH="${TRANSCRIPT_PATH:-/tmp/claude_transcript.jsonl}"

# Source common configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-config.sh"

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not found" >&2
    exit 1
fi

# Check if transcript file exists (takes precedence for status reporting)
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
    if [[ "$EMOJI_MODE" == "true" ]]; then
        echo "⏳"
    else
        echo "PENDING"
    fi
    exit 0
fi

# Check git status (same logic as quality-gate-stop.sh)
if ! command -v git >/dev/null 2>&1; then
    # Git not available - quality gate is active
    :
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    # Not in git repository
    if [[ "${QUALITY_GATE_RUN_OUTSIDE_GIT}" != "true" ]]; then
        if [[ "$EMOJI_MODE" == "true" ]]; then
            echo "🔒"
        else
            echo "DISABLED"
        fi
        exit 0
    fi
elif [[ -z $(git status --porcelain 2>/dev/null) ]]; then
    # No git changes - quality gate disabled
    if [[ "$EMOJI_MODE" == "true" ]]; then
        echo "🔒"
    else
        echo "DISABLED"
    fi
    exit 0
fi

# Check retry limit
if count_attempts_since_last_reset_point "$TRANSCRIPT_PATH" 10; then
    # Auto-approved after max attempts
    if [[ "$EMOJI_MODE" == "true" ]]; then
        echo "✅"
    else
        echo "APPROVED"
    fi
    exit 0
fi

# Get quality result from transcript
get_quality_result "$TRANSCRIPT_PATH"
result=$?

# Output status based on result
if [[ "$EMOJI_MODE" == "true" ]]; then
    case $result in
        0)
            echo "✅"
            ;;
        1)
            echo "❌"
            ;;
        2)
            echo "⏳"
            ;;
        3)
            echo "🔒"  # No edits - disabled
            ;;
        *)
            echo "⏳"
            ;;
    esac
else
    case $result in
        0)
            echo "APPROVED"
            ;;
        1)
            echo "REJECTED"
            ;;
        2)
            echo "PENDING"
            ;;
        3)
            echo "DISABLED"  # No edits
            ;;
        *)
            echo "PENDING"
            ;;
    esac
fi

exit 0