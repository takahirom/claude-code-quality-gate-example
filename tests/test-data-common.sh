#!/bin/bash
# Common test data - Production-like JSONL line definitions

# Common fields
SESSION_ID="test-session-12345"
CWD="/Users/test/git/project"
VERSION="1.0.67"
GIT_BRANCH="main"
BASE_TIMESTAMP="2025-08-04T13:00:00.000Z"

# UUID generation function
generate_uuid() {
    echo "test-uuid-$(date +%s)-$((RANDOM))"
}

# Helper function to create compact JSON
to_compact_json() {
    echo "$1" | jq -c '.'
}

# 1. Regular assistant response
get_assistant_response() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "assistant",
  "timestamp": "'$BASE_TIMESTAMP'",
  "message": {
    "id": "msg_'$(generate_uuid)'",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [
      {
        "type": "text",
        "text": "Code fixes implemented. Files have been updated."
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 150,
      "output_tokens": 25,
      "service_tier": "standard"
    }
  },
  "requestId": "req_'$(generate_uuid)'",
  "uuid": "'$(generate_uuid)'"
}'
}

# 2. Regular user input
get_user_input() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "Please fix the code"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

# 3. Stop hook feedback
get_stop_hook_feedback() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,  
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "Stop hook feedback:\n- ['$CWD'/.claude/scripts/quality-gate-stop.sh]: ❌ STOP: Quality gate blocking session completion.\n➡️  Action required: Use Task tool with subagent_type='\''quality-gate-keeper'\''\n🔍 Purpose: Thorough code quality inspection required\n🔄 This message repeats until proper quality review completed"
      }
    ]
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

# 4. Intervention message (Task tool usage with quality-gate-keeper)
get_intervention_message() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external", 
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "assistant",
  "timestamp": "'$BASE_TIMESTAMP'",
  "message": {
    "id": "msg_'$(generate_uuid)'",
    "type": "message",
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [
      {
        "type": "tool_use",
        "id": "toolu_'$(generate_uuid)'",
        "name": "Task",
        "input": {
          "description": "Quality gate keeper inspection",
          "prompt": "Please review the current code changes for quality issues",
          "subagent_type": "quality-gate-keeper"
        }
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 200,
      "output_tokens": 80,
      "service_tier": "standard"
    }
  },
  "requestId": "req_'$(generate_uuid)'",
  "uuid": "'$(generate_uuid)'"
}'
}

# 5. REJECT result (sidechain message)
get_reject_result() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": true,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "assistant",
  "timestamp": "'$BASE_TIMESTAMP'",
  "message": {
    "id": "msg_'$(generate_uuid)'",
    "type": "message", 
    "role": "assistant",
    "model": "claude-sonnet-4-20250514",
    "content": [
      {
        "type": "text",
        "text": "## Code Quality Analysis\n\n### Issues Found:\n1. Missing error handling in function\n2. Inconsistent naming conventions\n3. Performance bottleneck in loop\n\n**Final Result: ❌ REJECTED**\n\nThe code requires improvements before it can be approved."
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 500,
      "output_tokens": 120,
      "service_tier": "standard"
    }
  },
  "requestId": "req_'$(generate_uuid)'",
  "uuid": "'$(generate_uuid)'"
}'
}

# 6. APPROVE result (sidechain message)
get_approve_result() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": true,
  "userType": "external", 
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "assistant",
  "timestamp": "'$BASE_TIMESTAMP'",
  "message": {
    "id": "msg_'$(generate_uuid)'",
    "type": "message",
    "role": "assistant", 
    "model": "claude-sonnet-4-20250514",
    "content": [
      {
        "type": "text",
        "text": "## Code Quality Analysis\n\n### Analysis Results:\n✅ Error handling properly implemented\n✅ Consistent coding standards followed\n✅ Performance optimizations in place\n✅ Security best practices applied\n\n**Final Result: ✅ APPROVED**\n\nThe code meets all quality standards and is ready for integration."
      }
    ],
    "stop_reason": null,
    "stop_sequence": null,
    "usage": {
      "input_tokens": 500,
      "output_tokens": 100,  
      "service_tier": "standard"
    }
  },
  "requestId": "req_'$(generate_uuid)'",
  "uuid": "'$(generate_uuid)'"
}'
}

# 7. toolUseResult patterns (Task tool results)
get_tool_use_result_reject() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_'$(generate_uuid)'",
        "type": "tool_result",
        "content": "Analysis complete. Multiple code quality issues detected that require attention.\n\n**Final Result: ❌ REJECTED**",
        "is_error": false
      }
    ]
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'",
  "toolUseResult": "Quality inspection failed. Multiple critical issues detected.\n\n**Final Result: ❌ REJECTED**"
}'
}

get_tool_use_result_approve() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_'$(generate_uuid)'",
        "type": "tool_result", 
        "content": [
          {
            "type": "text",
            "text": "Code quality analysis completed successfully.\\n\\n## Final Result: ✅ **APPROVED** - Implementation meets all quality standards"
          }
        ],
        "is_error": false
      }
    ]
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'",
  "toolUseResult": {
    "content": [
      {
        "type": "text",
        "text": "Quality inspection passed. All standards met.\\n\\n## Final Result: ✅ **APPROVED** - Implementation meets all quality standards"
      }
    ],
    "totalDurationMs": 96818,
    "totalTokens": 95363,
    "totalToolUseCount": 11
  }
}'
}

# Create a version with toolUseResult in object format (like real transcript)
get_tool_use_result_approve_object_format() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external", 
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_'$(generate_uuid)'",
        "type": "tool_result",
        "content": [
          {
            "type": "text",
            "text": "Quality inspection complete.\\n\\n**Final Result: ✅ APPROVED** - All quality standards met."
          }
        ],
        "is_error": false
      }
    ]
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'",
  "toolUseResult": {
    "content": [
      {
        "type": "text",
        "text": "Quality inspection complete.\\n\\n**Final Result: ✅ APPROVED** - All quality standards met."
      }
    ],
    "totalDurationMs": 96818,
    "totalTokens": 95363,
    "totalToolUseCount": 11
  }
}'
}


# Function to generate Edit tool false positive test data
get_edit_tool_false_positive() {
to_compact_json '{
  "type": "user",
  "message": {
    "role": "user",
    "content": [
      {
        "tool_use_id": "toolu_'$(generate_uuid)'",
        "type": "tool_result",
        "content": "File updated successfully"
      }
    ]
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'",
  "toolUseResult": {
    "filePath": "/test/quality-check.sh",
    "oldString": "old code", 
    "newString": "new code",
    "originalFile": "#!/bin/bash\n# Quality check script\nif check_quality; then\n    echo \"Final Result: ✅ APPROVED - Quality check passed\"\nelse\n    echo \"Final Result: ❌ REJECTED - Quality check failed\"\nfi\necho \"System works correctly\"",
    "structuredPatch": [{"oldStart": 1, "oldLines": 2, "newStart": 1, "newLines": 2, "lines": ["-old code", "+new code"]}],
    "userModified": false,
    "replaceAll": false
  }
}'
}

# User SKIP QG variations
get_user_skip_qg() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "SKIP QG"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

get_user_skip_qg_lowercase() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "skip qg"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

get_user_skip_qg_mixed() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "Skip QG"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

get_user_skip_qg_in_context() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "please SKIP QG for this change"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

get_user_lgtm() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "LGTM"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

# Parameterized generators for test data
generate_user_message() {
    local content="${1:-Test message}"
    local uuid="${2:-user-$(generate_uuid)}"
    # Comprehensive JSON escaping for all required characters
    local esc_content=${content//\\/\\\\}  # Escape backslash first
    esc_content=${esc_content//\"/\\\"}     # Escape double quote
    esc_content=${esc_content//$'\n'/\\n}   # Escape newline
    esc_content=${esc_content//$'\r'/\\r}   # Escape carriage return
    esc_content=${esc_content//$'\t'/\\t}   # Escape tab
    esc_content=${esc_content//$'\f'/\\f}   # Escape form feed
    esc_content=${esc_content//$'\b'/\\b}   # Escape backspace
    
    local esc_uuid=${uuid//\\/\\\\}
    esc_uuid=${esc_uuid//\"/\\\"}
    echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"'"$esc_content"'"}]},"uuid":"'"$esc_uuid"'"}'
}

generate_bash_command() {
    local command="${1:-echo test}"
    local description="${2:-Test command}"
    local uuid="${3:-bash-$(generate_uuid)}"
    # Comprehensive JSON escaping for all required characters
    local esc_cmd=${command//\\/\\\\}      # Escape backslash first
    esc_cmd=${esc_cmd//\"/\\\"}            # Escape double quote
    esc_cmd=${esc_cmd//$'\n'/\\n}          # Escape newline
    esc_cmd=${esc_cmd//$'\r'/\\r}          # Escape carriage return
    esc_cmd=${esc_cmd//$'\t'/\\t}          # Escape tab
    esc_cmd=${esc_cmd//$'\f'/\\f}          # Escape form feed
    esc_cmd=${esc_cmd//$'\b'/\\b}          # Escape backspace
    
    local esc_desc=${description//\\/\\\\}
    esc_desc=${esc_desc//\"/\\\"}
    esc_desc=${esc_desc//$'\n'/\\n}
    esc_desc=${esc_desc//$'\r'/\\r}
    esc_desc=${esc_desc//$'\t'/\\t}
    esc_desc=${esc_desc//$'\f'/\\f}
    esc_desc=${esc_desc//$'\b'/\\b}
    
    local esc_uuid=${uuid//\\/\\\\}
    esc_uuid=${esc_uuid//\"/\\\"}
    echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"'"$esc_cmd"'","description":"'"$esc_desc"'"}}]},"uuid":"'"$esc_uuid"'"}'
}

get_user_looks_good() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "looks good to me"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

# 11. User message saying "I will not skip qg" - should NOT match
get_user_not_skip_qg() {
    to_compact_json '{
  "parentUuid": "'$(generate_uuid)'",
  "isSidechain": false,
  "userType": "external",
  "cwd": "'$CWD'",
  "sessionId": "'$SESSION_ID'",
  "version": "'$VERSION'",
  "gitBranch": "'$GIT_BRANCH'",
  "type": "user",
  "message": {
    "role": "user",
    "content": "I will not skip qg"
  },
  "uuid": "'$(generate_uuid)'",
  "timestamp": "'$BASE_TIMESTAMP'"
}'
}

# Initialize variables using lazy loading
ASSISTANT_RESPONSE=""
USER_INPUT=""
STOP_HOOK_FEEDBACK=""
INTERVENTION_MESSAGE=""
REJECT_RESULT=""
APPROVE_RESULT=""
TOOL_USE_RESULT_REJECT=""
TOOL_USE_RESULT_APPROVE=""
EDIT_TOOL_FALSE_POSITIVE=""
USER_SKIP_QG=""
USER_SKIP_QG_LOWERCASE=""
USER_SKIP_QG_MIXED=""
USER_SKIP_QG_IN_CONTEXT=""
USER_NOT_SKIP_QG=""
USER_LGTM=""
USER_LOOKS_GOOD=""

# Lazy loading functions
get_data() {
    case $1 in
        "ASSISTANT_RESPONSE")
            [ -z "$ASSISTANT_RESPONSE" ] && ASSISTANT_RESPONSE=$(get_assistant_response)
            echo "$ASSISTANT_RESPONSE"
            ;;
        "USER_INPUT")
            [ -z "$USER_INPUT" ] && USER_INPUT=$(get_user_input)
            echo "$USER_INPUT"
            ;;
        "STOP_HOOK_FEEDBACK")
            [ -z "$STOP_HOOK_FEEDBACK" ] && STOP_HOOK_FEEDBACK=$(get_stop_hook_feedback)
            echo "$STOP_HOOK_FEEDBACK"
            ;;
        "INTERVENTION_MESSAGE")
            [ -z "$INTERVENTION_MESSAGE" ] && INTERVENTION_MESSAGE=$(get_intervention_message)
            echo "$INTERVENTION_MESSAGE"
            ;;
        "REJECT_RESULT")
            [ -z "$REJECT_RESULT" ] && REJECT_RESULT=$(get_reject_result)
            echo "$REJECT_RESULT"
            ;;
        "APPROVE_RESULT")
            [ -z "$APPROVE_RESULT" ] && APPROVE_RESULT=$(get_approve_result)
            echo "$APPROVE_RESULT"
            ;;
        "TOOL_USE_RESULT_REJECT")
            [ -z "$TOOL_USE_RESULT_REJECT" ] && TOOL_USE_RESULT_REJECT=$(get_tool_use_result_reject)
            echo "$TOOL_USE_RESULT_REJECT"
            ;;
        "TOOL_USE_RESULT_APPROVE")
            [ -z "$TOOL_USE_RESULT_APPROVE" ] && TOOL_USE_RESULT_APPROVE=$(get_tool_use_result_approve)
            echo "$TOOL_USE_RESULT_APPROVE"
            ;;
        "TOOL_USE_RESULT_APPROVE_OBJECT_FORMAT")
            echo "$(get_tool_use_result_approve_object_format)"
            ;;
        "EDIT_TOOL_FALSE_POSITIVE")
            [ -z "$EDIT_TOOL_FALSE_POSITIVE" ] && EDIT_TOOL_FALSE_POSITIVE=$(get_edit_tool_false_positive)
            echo "$EDIT_TOOL_FALSE_POSITIVE"
            ;;
        "READ_TOOL_USE")
            echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/test.txt"}}]}}'
            ;;
        "EDIT_TOOL_USE")
            echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/test.txt","old_string":"old","new_string":"new"}}]}}'
            ;;
        "WRITE_TOOL_USE")
            echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/test.txt","content":"new content"}}]}}'
            ;;
        "MCP_SERENA_REPLACE")
            echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__serena__replace_regex","input":{"relative_path":"test.txt","regex":"old","repl":"new"}}]}}'
            ;;
        "USER_SKIP_QG")
            [ -z "$USER_SKIP_QG" ] && USER_SKIP_QG=$(get_user_skip_qg)
            echo "$USER_SKIP_QG"
            ;;
        "USER_SKIP_QG_LOWERCASE")
            [ -z "$USER_SKIP_QG_LOWERCASE" ] && USER_SKIP_QG_LOWERCASE=$(get_user_skip_qg_lowercase)
            echo "$USER_SKIP_QG_LOWERCASE"
            ;;
        "USER_SKIP_QG_MIXED")
            [ -z "$USER_SKIP_QG_MIXED" ] && USER_SKIP_QG_MIXED=$(get_user_skip_qg_mixed)
            echo "$USER_SKIP_QG_MIXED"
            ;;
        "USER_SKIP_QG_IN_CONTEXT")
            [ -z "$USER_SKIP_QG_IN_CONTEXT" ] && USER_SKIP_QG_IN_CONTEXT=$(get_user_skip_qg_in_context)
            echo "$USER_SKIP_QG_IN_CONTEXT"
            ;;
        "USER_NOT_SKIP_QG")
            [ -z "$USER_NOT_SKIP_QG" ] && USER_NOT_SKIP_QG=$(get_user_not_skip_qg)
            echo "$USER_NOT_SKIP_QG"
            ;;
        "USER_LGTM")
            [ -z "$USER_LGTM" ] && USER_LGTM=$(get_user_lgtm)
            echo "$USER_LGTM"
            ;;
        "USER_LOOKS_GOOD")
            [ -z "$USER_LOOKS_GOOD" ] && USER_LOOKS_GOOD=$(get_user_looks_good)
            echo "$USER_LOOKS_GOOD"
            ;;
        *)
            echo "Unknown data type: $1" >&2
            return 1
            ;;
    esac
}

# Create test transcript function
create_test_transcript() {
    local output_file="$1"
    echo "# Test transcript with all message types" > "$output_file"
    get_data "USER_INPUT" >> "$output_file"
    get_data "ASSISTANT_RESPONSE" >> "$output_file" 
    get_data "STOP_HOOK_FEEDBACK" >> "$output_file"
    get_data "INTERVENTION_MESSAGE" >> "$output_file"
    get_data "REJECT_RESULT" >> "$output_file"
    get_data "STOP_HOOK_FEEDBACK" >> "$output_file"
    get_data "APPROVE_RESULT" >> "$output_file"
    get_data "TOOL_USE_RESULT_REJECT" >> "$output_file"
    get_data "TOOL_USE_RESULT_APPROVE" >> "$output_file"
}

# Usage example function
show_usage() {
    echo "Common test data usage examples:"
    echo "source test-data-common-v2.sh"
    echo "create_test_transcript /tmp/test.jsonl"
    echo ""
    echo "Available data types:"
    echo "- ASSISTANT_RESPONSE: Regular assistant response"
    echo "- USER_INPUT: Regular user input"
    echo "- STOP_HOOK_FEEDBACK: Stop hook feedback"
    echo "- INTERVENTION_MESSAGE: Intervention message (Task tool usage)"
    echo "- REJECT_RESULT: Sidechain REJECT result"
    echo "- APPROVE_RESULT: Sidechain APPROVE result"
    echo "- TOOL_USE_RESULT_REJECT: toolUseResult format REJECT"
    echo "- TOOL_USE_RESULT_APPROVE: toolUseResult format APPROVE"
    echo ""
    echo "Usage: get_data \"DATA_TYPE\" or use \$DATA_TYPE (with lazy loading)"
}

# Execute when script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_usage
fi