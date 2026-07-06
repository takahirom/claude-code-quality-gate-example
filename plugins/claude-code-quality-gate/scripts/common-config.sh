#!/bin/bash
# Common configuration for quality gate scripts

# Check for required commands
if ! command -v nl >/dev/null 2>&1; then
    echo "ERROR: nl command not found. Please install coreutils package." >&2
    exit 1
fi
# Determine reverse command (tac on GNU, tail -r on BSD/macOS)
if command -v tac >/dev/null 2>&1; then
    REVERSE_CMD="tac"
elif command -v tail >/dev/null 2>&1 && tail -r </dev/null >/dev/null 2>&1; then
    REVERSE_CMD="tail -r"
else
    echo "ERROR: No reverse command found (tac or tail -r). Please install coreutils (tac) or ensure tail -r is available." >&2
    exit 1
fi

# Run quality gate outside git repositories (default: false)
# Set to true to enable quality gate checks in non-git directories
QUALITY_GATE_RUN_OUTSIDE_GIT="${QUALITY_GATE_RUN_OUTSIDE_GIT:-false}"

# 差分の基準ブランチ（デフォルト: main）。作業ツリーだけでなく main との
# マージベースからの差分をレビュー対象にするために使う。
QUALITY_GATE_DIFF_BASE="${QUALITY_GATE_DIFF_BASE:-main}"

# ハッシュコマンド（macOS は shasum、GNU は sha1sum）。どちらも無ければ
# 空にして冪等判定を無効化する（従来の編集検知にフォールバック）。
if command -v shasum >/dev/null 2>&1; then
    QG_HASH_CMD="shasum"
elif command -v sha1sum >/dev/null 2>&1; then
    QG_HASH_CMD="sha1sum"
else
    QG_HASH_CMD=""
fi

# Configurable pattern for file editing tools (for MCP compatibility)
# Support both old and new variable names for backward compatibility
# Includes standard tools and serena MCP tools
# Note: Anchors enforce exact matches (e.g., TodoWrite no longer matches Write) and stay portable across GNU/BSD grep
QUALITY_GATE_EDIT_TOOLS_PATTERN="${QUALITY_GATE_EDIT_TOOLS_PATTERN:-${EDIT_TOOLS_PATTERN:-^(Write|Edit|MultiEdit|NotebookEdit|replace_regex|replace_symbol_body|insert_after_symbol|insert_before_symbol|mcp__serena__(replace_regex|replace_symbol_body|insert_after_symbol|insert_before_symbol))$}}"

# Check dependencies function
check_dependencies() {
    for cmd in jq git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "❌ Required dependency '$cmd' not found" >&2
            exit 1
        fi
    done
}

# main ブランチとのマージベースを解決する
# 出力: マージベースのコミットハッシュ / 見つからなければ非ゼロで返す
quality_gate_diff_base() {
    local base="$QUALITY_GATE_DIFF_BASE"
    local ref=""
    # ローカルブランチ → リモート追跡の順に解決する
    if git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
        ref="$base"
    elif git rev-parse --verify --quiet "origin/$base" >/dev/null 2>&1; then
        ref="origin/$base"
    else
        return 1
    fi
    git merge-base HEAD "$ref" 2>/dev/null
}

# レビュー対象の変更が存在するか判定する
# 未追跡ファイル、および main とのマージベースからの差分（コミット済み含む）を見る
# base が解決できない場合は従来どおり作業ツリーの差分にフォールバックする
# 返り値: 0 = 変更あり / 1 = 変更なし
quality_gate_has_changes() {
    if [[ -n $(git ls-files --others --exclude-standard 2>/dev/null) ]]; then
        return 0
    fi
    local base
    if base=$(quality_gate_diff_base); then
        if ! git diff --quiet "$base" 2>/dev/null; then
            return 0
        fi
        return 1
    fi
    if [[ -n $(git diff --name-only 2>/dev/null) ]]; then
        return 0
    fi
    return 1
}

# 現在の差分（base からの差分 + 未追跡ファイルの内容）のハッシュを出力する
# 承認時点の状態を記録し「承認後に実質的な変更がないか」を判定するために使う
# git やハッシュコマンドが無い場合は空文字を返し、冪等判定を無効化する
quality_gate_diff_hash() {
    [[ -n "$QG_HASH_CMD" ]] || return 0
    command -v git >/dev/null 2>&1 || return 0
    git rev-parse --git-dir >/dev/null 2>&1 || return 0
    local base
    base=$(quality_gate_diff_base) || base=""
    {
        if [[ -n "$base" ]]; then
            git diff "$base" 2>/dev/null
        else
            git diff 2>/dev/null
        fi
        # 未追跡ファイルの内容も差分に含める
        git ls-files --others --exclude-standard -z 2>/dev/null \
          | while IFS= read -r -d '' f; do
                echo "=== $f ==="
                cat -- "$f" 2>/dev/null
            done
    } | $QG_HASH_CMD | awk '{print $1}'
}

# 承認済み差分ハッシュを保存する状態ファイルのパスを出力する
# QUALITY_GATE_STATE_FILE で上書き可能（主にテスト用）
quality_gate_state_file() {
    if [[ -n "${QUALITY_GATE_STATE_FILE:-}" ]]; then
        echo "$QUALITY_GATE_STATE_FILE"
        return 0
    fi
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || root="$PWD"
    local key="unknown"
    if [[ -n "$QG_HASH_CMD" ]]; then
        key=$(printf '%s' "$root" | $QG_HASH_CMD | awk '{print $1}')
    fi
    echo "${TMPDIR:-/tmp}/claude_quality_gate_approved-$key"
}

# APPROVED かつ現在の差分と一致することが確定した時点で差分ハッシュを記録する
# これにより次回以降、差分が変わらなければ再レビューをスキップできる（冪等化）
record_quality_gate_approval() {
    local h
    h=$(quality_gate_diff_hash)
    [[ -z "$h" ]] && return 0
    printf '%s\n' "$h" > "$(quality_gate_state_file)" 2>/dev/null || true
}

# Helper: Check for edits after given line number
has_edits_after_line() {
    local transcript_path="$1"
    local line_number="$2"
    
    tail -n +$((line_number + 1)) "$transcript_path" | \
        jq -r '
          select((.message.content | type) == "array")               # only arrays
          | .message.content[]
          | select(.type == "tool_use" and (.name // empty) != "")   # only tool_use with a name
          | .name
        ' 2>/dev/null | grep -qE "$QUALITY_GATE_EDIT_TOOLS_PATTERN"
}

# Get the most recent quality-gate-keeper result from transcript
# Returns: 0 if APPROVED, 1 if REJECTED, 2 if no result found
get_quality_result() {
    local transcript_path="$1"
    
    if [[ ! -f "$transcript_path" ]]; then
        return 2
    fi
    
    # Find the most recent Final Result using reverse search (performance optimized)
    local last_result=""
    local last_result_line=0
    local total_lines
    total_lines=$(wc -l < "$transcript_path")
    
    # Find most recent Final Result from sidechain or toolUseResult only
    # This prevents interference from ongoing Bash commands containing "Final Result:"
    # Optimized: Use head -10 to limit jq checks since Final Result is usually near the end
    local result_info
    result_info=$($REVERSE_CMD "$transcript_path" | nl -nrn | grep "Final Result:" | head -10 | while read -r line; do
        # Only check jq for lines that contain Final Result
        if echo "$line" | cut -f2- | jq -e '.isSidechain == true or .toolUseResult' >/dev/null 2>&1; then
            echo "$line"
            break
        fi
    done | head -1)
    
    if [[ -n "$result_info" ]]; then
        local reverse_line_num
        reverse_line_num=$(echo "$result_info" | cut -f1)
        local line
        line=$(echo "$result_info" | cut -f2-)
        last_result_line=$((total_lines - reverse_line_num + 1))
        
        # Determine result type and extract content
        if echo "$line" | jq -e '.isSidechain == true' >/dev/null 2>&1; then
            last_result=$(extract_message_content "$line")
        elif echo "$line" | jq -e '.toolUseResult' >/dev/null 2>&1; then
            local tool_result_content
            tool_result_content=$(extract_tool_use_result_content "$line")
            if [[ -n "$tool_result_content" ]] && echo "$tool_result_content" | grep -q "Final Result:"; then
                last_result="$tool_result_content"
            fi
        fi
    fi
    
    # Check for user SKIP QG message (highly optimized)
    local user_skip_qg_line=0
    local user_skip_qg
    # Optimized: Pre-filter user messages and check for SKIP QG pattern
    # User messages use string format: "content": "SKIP QG" or "content":"SKIP QG"
    user_skip_qg=$($REVERSE_CMD "$transcript_path" | nl -nrn | grep -E '"type"\s*:\s*"user"' | head -100 | while read -r line; do
        # Fast check: look for SKIP QG in content field (handles with/without spaces)
        if echo "$line" | grep -qiE '"content"\s*:\s*"\s*SKIP\s+QG\s*"'; then
            # Found potential match, verify with jq (only for matches)
            local json_data
            json_data=$(echo "$line" | cut -f2-)
            local content
            content=$(extract_user_content "$json_data")
            
            # Double-check with proper extraction
            if [[ -n "$content" ]] && echo "$content" | grep -qiE '^[[:space:]]*SKIP[[:space:]]+QG[[:space:]]*$'; then
                echo "$line" | cut -f1
                break
            fi
        fi
    done | head -1)
    
    if [[ -n "$user_skip_qg" ]]; then
        user_skip_qg_line=$((total_lines - user_skip_qg + 1))
        
        # User SKIP QG is valid if: no Final Result OR it comes after Final Result
        if [[ -z "$last_result" ]] || [[ $user_skip_qg_line -gt $last_result_line ]]; then
            # Check for stale skip (edits after user SKIP QG)
            if has_edits_after_line "$transcript_path" "$user_skip_qg_line"; then
                return 2  # Stale skip
            fi
            return 0  # User skipped QG
        fi
    fi
    
    # No Final Result found and no user SKIP QG
    if [[ -z "$last_result" ]]; then
        # Check if any edits have been made in the session
        if ! jq -r 'select(.message.content[]?.name) | .message.content[]?.name' "$transcript_path" 2>/dev/null | \
           grep -qE "$QUALITY_GATE_EDIT_TOOLS_PATTERN"; then
            # No edits made, skip quality gate
            return 3  # New return code for "no edits"
        fi
        return 2
    fi
    
    # Check result status
    if echo "$last_result" | grep -qE "✅.*APPROVED"; then
        # Check for file edits after approval
        if has_edits_after_line "$transcript_path" "$last_result_line"; then
            # 承認後に編集はあるが、差分が承認時点と同一なら実質無変更なので
            # 再レビューを促さず承認扱いにする（冪等化）
            local approved_hash current_hash
            approved_hash=$(cat "$(quality_gate_state_file)" 2>/dev/null)
            current_hash=$(quality_gate_diff_hash)
            if [[ -n "$approved_hash" && -n "$current_hash" && "$approved_hash" == "$current_hash" ]]; then
                return 0  # 承認時点から差分が変わっていない
            fi
            return 2  # Stale approval
        fi
        return 0  # APPROVED
    elif echo "$last_result" | grep -q "❌ REJECTED"; then
        return 1  # REJECTED
    else
        return 2  # No result
    fi
}

# Helper function to extract user content from a JSON line
# Handles both string and array formats
# Input: JSON line (from transcript)
# Output: extracted text content or empty string
extract_user_content() {
    local json_line="$1"
    echo "$json_line" | jq -r '
        if (.message.content | type) == "string" then
            .message.content
        elif (.message.content | type) == "array" then
            .message.content[] | select(.type == "text") | .text // empty
        else
            empty
        end' 2>/dev/null
}

# Helper function to extract content from toolUseResult
# Handles both string and object formats
# Input: JSON line (from transcript)
# Output: extracted text content or empty string
extract_tool_use_result_content() {
    local json_line="$1"
    echo "$json_line" | jq -r '
        if (.toolUseResult | type) == "string" then
            .toolUseResult
        elif (.toolUseResult | type) == "object" then
            .toolUseResult
            | .content[]?
            | select(.type == "text")
            | .text // empty
        else
            empty
        end' 2>/dev/null | tr '\n' ' '
}

# Helper function to extract content from transcript line (deprecated - use extract_user_content)
# Returns extracted content or empty string; supports string and array forms
extract_message_content() {
    local line="$1"
    echo "$line" | jq -r '
        if (.message.content | type) == "string" then
            .message.content
        elif (.message.content | type) == "array" then
            .message.content[] | select(.type == "text") | .text // empty
        else
            empty
        end
    ' 2>/dev/null | tr '\n' ' '
}

# Count attempts since last reset point (approval or user input) in transcript
# Returns: 0 if max attempts reached, 1 otherwise
count_attempts_since_last_reset_point() {
    local transcript_path="$1"
    local max_attempts="${2:-10}"  # Default 10 attempts
    
    if [[ ! -f "$transcript_path" ]]; then
        return 1  # Continue if no transcript file
    fi
    
    # Find last APPROVED result and user input using reverse search
    # Find last APPROVED result line number using reverse search
    # PERFORMANCE OPTIMIZED: Pre-filter with grep to reduce jq calls dramatically
    local last_approved_line=0
    local approved_result
    approved_result=$(
      $REVERSE_CMD "$transcript_path" \
        | nl -nrn \
        | grep -m50 -E 'Final Result:.*(✅[[:space:]]*)?APPROVED' \
        | while IFS= read -r line; do
            json_data=$(echo "$line" | cut -f2-)
            # Only accept trusted sources, and for toolUseResult re-validate the content has APPROVED
            if echo "$json_data" | jq -e '.isSidechain == true' >/dev/null 2>&1; then
              echo "$line" | cut -f1; break
            elif echo "$json_data" | jq -e '.toolUseResult' >/dev/null 2>&1; then
              tool_content=$(extract_tool_use_result_content "$json_data")
              if echo "$tool_content" | grep -qE 'Final Result:.*(✅[[:space:]]*)?APPROVED'; then
                echo "$line" | cut -f1; break
              fi
            fi
          done | head -1
    )
    
    if [[ -n "$approved_result" ]]; then
        local total_lines
        total_lines=$(wc -l < "$transcript_path")
        last_approved_line=$((total_lines - approved_result + 1))
    fi
    
    # Find last user input line number using reverse search (optimized)
    local last_user_input_line=0
    local user_result
    user_result=$($REVERSE_CMD "$transcript_path" | nl -nrn | while read -r line; do
        # Quick pre-check to avoid processing non-user lines
        if [[ "$line" == *'"type":"user"'* ]]; then
            local json_data
            json_data=$(echo "$line" | cut -f2-)
            local content
            content=$(extract_user_content "$json_data")
            if [[ -n "$content" ]] && ! echo "$content" | grep -q "Quality gate blocking session completion"; then
                echo "$line" | cut -f1  # Return line number
                break
            fi
        fi
    done | head -1)
    
    if [[ -n "$user_result" ]]; then
        local total_lines
        total_lines=$(wc -l < "$transcript_path")
        last_user_input_line=$((total_lines - user_result + 1))
    fi
    
    # Determine start line: MAX(last_approved_line, last_user_input_line)
    local start_line=0
    if [[ $last_approved_line -gt $last_user_input_line ]]; then
        start_line=$last_approved_line
    else
        start_line=$last_user_input_line
    fi
    
    # Count Stop hook messages after start line
    # Stop hook messages appear in tool_use commands within assistant messages
    local attempt_count=0
    local temp_transcript
    temp_transcript="$(mktemp "${TMPDIR:-/tmp}"/filtered_transcript.$$.XXXXXX.jsonl)"
    trap 'rm -f -- "$temp_transcript"' RETURN
    
    if [[ $start_line -gt 0 ]]; then
        # Extract lines after start_line
        tail -n +$((start_line + 1)) "$transcript_path" > "$temp_transcript"
    else
        # No APPROVED or user input found, use entire transcript
        cp "$transcript_path" "$temp_transcript"
    fi
    
    # Count Stop hook messages - use simple grep approach (most reliable)
    local raw_count
    raw_count=$(grep -c "Quality gate blocking session completion" "$temp_transcript" 2>/dev/null || echo 0)
    attempt_count=$(echo "$raw_count" | head -1 | tr -d ' \n\r')
    
    # cleanup handled by trap
    
    # Log only if LOG_FILE is set
    if [[ -n "$LOG_FILE" ]]; then
        echo "Attempt count since MAX(last_approved_line=$last_approved_line, last_user_input_line=$last_user_input_line): [$attempt_count] (max: $max_attempts)" >> "$LOG_FILE"
    fi
    
    if [[ $attempt_count -ge $max_attempts ]]; then
        return 0  # Max attempts reached
    else
        return 1  # Can continue
    fi
}
