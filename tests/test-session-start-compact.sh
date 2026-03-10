#!/usr/bin/env bash
# Tests for session-start-compact.sh (SessionStart compact hook)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
HOOK="$SCRIPT_DIR/../hooks/session-start-compact.sh"
TMPDIR_BASE="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

create_transcript() {
  local file="$1"
  cat > "$file" <<'EOF'
{"type":"user","message":{"content":"hello"},"timestamp":"2026-03-10T10:00:00Z"}
{"type":"assistant","message":{"content":"hi"},"timestamp":"2026-03-10T10:00:01Z"}
{"type":"user","message":{"content":"do something"},"timestamp":"2026-03-10T10:01:00Z"}
{"type":"assistant","message":{"content":"done"},"timestamp":"2026-03-10T10:01:01Z"}
{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}
EOF
}

create_transcript_two_boundaries() {
  local file="$1"
  cat > "$file" <<'EOF'
{"type":"user","message":{"content":"first session"},"timestamp":"2026-03-10T09:00:00Z"}
{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}
{"type":"user","message":{"content":"second session"},"timestamp":"2026-03-10T10:00:00Z"}
{"type":"assistant","message":{"content":"working"},"timestamp":"2026-03-10T10:00:01Z"}
{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}
EOF
}

test_compact_outputs_context() {
  echo "compact → additionalContext output"
  local transcript="$TMPDIR_BASE/transcript-auto.jsonl"
  create_transcript "$transcript"
  local json='{"session_id":"test-001","transcript_path":"'"$transcript"'","hook_event_name":"SessionStart","source":"compact"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_contains "has additionalContext" "additionalContext" "$output"
  assert_contains "has SessionStart hookEventName" "SessionStart" "$output"
  assert_contains "has transcript path" "$transcript" "$output"
  assert_contains "start line is 1" "line 1 to" "$output"
}

test_no_boundary_skips() {
  echo "no compact_boundary → skip"
  local transcript="$TMPDIR_BASE/transcript-none.jsonl"
  cat > "$transcript" <<'EOF'
{"type":"user","message":{"content":"hello"},"timestamp":"2026-03-10T10:00:00Z"}
{"type":"assistant","message":{"content":"hi"},"timestamp":"2026-03-10T10:00:01Z"}
EOF
  local json='{"session_id":"test-003","transcript_path":"'"$transcript"'","hook_event_name":"SessionStart","source":"compact"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_two_boundaries_correct_range() {
  echo "two boundaries → range between them"
  local transcript="$TMPDIR_BASE/transcript-two.jsonl"
  create_transcript_two_boundaries "$transcript"
  local json='{"session_id":"test-004","transcript_path":"'"$transcript"'","hook_event_name":"SessionStart","source":"compact"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_contains "has additionalContext" "additionalContext" "$output"
  assert_contains "start after first boundary" "line 2 to" "$output"
}

test_missing_session_id() {
  echo "missing session_id → skip"
  local json='{"transcript_path":"/tmp/fake.jsonl","hook_event_name":"SessionStart"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_missing_transcript() {
  echo "missing transcript → skip"
  local json='{"session_id":"test-005","transcript_path":"/nonexistent/path.jsonl","hook_event_name":"SessionStart"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_empty_stdin() {
  echo "empty stdin → skip"
  local output
  output=$(printf '' | zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_delta_exists_skips() {
  echo "delta file already exists → skip"
  local transcript="$TMPDIR_BASE/transcript-deltaexists.jsonl"
  create_transcript "$transcript"
  local claude_dir="$TMPDIR_BASE/fake-claude"
  mkdir -p "$claude_dir/projects/test-proj"
  local fake_transcript="$claude_dir/projects/test-proj/test-delta-exists.jsonl"
  cp "$transcript" "$fake_transcript"
  mkdir -p "$claude_dir/workspace/delta"
  echo "# existing delta" > "$claude_dir/workspace/delta/delta-test-delta-exists.md"
  local json='{"session_id":"test-delta-exists","transcript_path":"'"$fake_transcript"'","hook_event_name":"SessionStart","source":"compact"}'
  local output
  output=$(printf '%s' "$json" | zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output (delta exists)" "$output"
}

test_no_jq() {
  echo "jq unavailable → skip"
  local transcript="$TMPDIR_BASE/transcript-nojq.jsonl"
  create_transcript "$transcript"
  local json='{"session_id":"test-nojq","transcript_path":"'"$transcript"'","hook_event_name":"SessionStart","source":"compact"}'
  local output
  # PATH=/bin keeps cat/date but excludes /usr/bin/jq and ~/.local/bin/jq
  output=$(printf '%s' "$json" | PATH="/bin" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

echo "=== session-start-compact.sh tests ==="
test_compact_outputs_context
test_no_boundary_skips
test_two_boundaries_correct_range
test_delta_exists_skips
test_missing_session_id
test_missing_transcript
test_empty_stdin
test_no_jq

report_results
