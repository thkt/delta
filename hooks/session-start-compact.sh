#!/bin/zsh
set +e

# SessionStart(compact) hook - auto-compact fallback for Delta generation
# Only activates for auto-compact (trigger: "auto").
# Manual compact assumes /delta was already run.
#
# Input (stdin): SessionStart JSON with session_id, transcript_path
# Output (stdout): JSON with additionalContext for Delta generation
# Uses: compact_boundary entries in transcript JSONL
# Requires: jq (non-hot-path, runs only on SessionStart after compact)

# Read JSON from stdin
input=""
if [ ! -t 0 ]; then
    IFS= read -r -t 3 -d '' input 2>/dev/null
fi
[ -z "$input" ] && exit 0

command -v jq &>/dev/null || exit 0

# Extract fields via jq (single call)
parsed=$(printf '%s' "$input" | jq -r '[.session_id // empty, .transcript_path // empty] | @tsv' 2>/dev/null)
IFS=$'\t' read -r session_id transcript_path <<< "$parsed"
[[ "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 0
[[ "$transcript_path" == *.jsonl ]] || exit 0
[ -r "$transcript_path" ] || exit 0

# Find compact_boundary entries with line numbers
# Substring match: compact_boundary only appears as system subtype in transcript
boundaries=$(grep -n '"compact_boundary"' "$transcript_path" 2>/dev/null)
grep_rc=$?
[ $grep_rc -eq 2 ] && exit 0  # grep error (not "no match")
[ -z "$boundaries" ] && exit 0

# Get the last compact_boundary
last_boundary_line=$(printf '%s' "$boundaries" | tail -1)
last_line_num="${last_boundary_line%%:*}"
last_boundary_json="${last_boundary_line#*:}"

# Only proceed for auto-compact
case "$last_boundary_json" in
    *'"auto"'*) ;;
    *) exit 0 ;;
esac

# Find previous compact_boundary for range start
start_line=1
boundary_count=$(printf '%s\n' "$boundaries" | wc -l)
boundary_count=$((boundary_count + 0)) # strip macOS wc -l leading whitespace
if [ "$boundary_count" -gt 1 ]; then
    prev_boundary_line=$(printf '%s\n' "$boundaries" | tail -2 | head -1)
    start_line="${prev_boundary_line%%:*}"
fi
[[ "$start_line" =~ ^[0-9]+$ ]] || start_line=1

# Build additionalContext
context="[Delta generation - auto-compact fallback]
auto-compact occurred. Generate Delta from pre-compaction session content.

1. Read ${transcript_path} from line ${start_line} to line ${last_line_num} using Read tool
2. Extract information not in SOW/Spec:
   - Problems or constraints discovered during implementation
   - Design changes from plan and their rationale
   - Incomplete work and next actions
   - Key decisions
3. Write extracted content to .claude/workspace/delta/delta-{SESSION_ID}.md (use current session ID)
4. Continue normal work after Delta generation"

# Escape for JSON via jq
jq -n --arg ctx "$context" \
    '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
exit 0
