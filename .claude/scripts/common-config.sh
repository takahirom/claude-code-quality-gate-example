#!/bin/bash
# Common configuration for quality gate scripts

# Configuration: Two operational modes for quality gate
PASSPHRASE="I have launched the quality gate keeper subagent and received approval"  # Approval mode: continues until manual approval
# PASSPHRASE="I have launched the quality gate keeper subagent and addressed all requests"  # Self-fix mode: continues until self-reported completion

# Check dependencies function
check_dependencies() {
    for cmd in jq git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ Required dependency '$cmd' not found" >&2
            exit 1
        fi
    done
}