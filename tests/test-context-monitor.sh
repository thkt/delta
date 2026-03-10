#!/usr/bin/env bash
# Tests for context-monitor.sh (PostToolUse context warning hook)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
HOOK="$SCRIPT_DIR/../hooks/context-monitor.sh"
TMPDIR_BASE="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

# Helper: create bridge file
create_bridge() {
  local session_id="$1" remaining="$2"
  local ts="${3:-$(date +%s)}"
  printf '{"remaining_pct":%s,"ts":%s}' \
    "$remaining" "$ts" \
    > "${TMPDIR_BASE}/claude-ctx-${session_id}.json"
}

# Helper: run hook with session_id
run_hook() {
  local session_id="$1"
  local json='{"tool_name":"Read","session_id":"'"$session_id"'"}'
  printf '%s' "$json" | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null
}

# Helper: clean state files
clean_state() {
  local session_id="$1"
  rm -f "${TMPDIR_BASE}/claude-ctx-${session_id}-warned"
  rm -f "${TMPDIR_BASE}/claude-ctx-${session_id}-delta"
}

test_empty_stdin() {
  echo "empty stdin → no output"
  local output
  output=$(echo "" | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_no_session_id() {
  echo "no session_id → no output"
  local output
  output=$(printf '{"tool_name":"Read"}' | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_healthy_context() {
  echo "healthy (50%) → no output"
  create_bridge "healthy-001" 50
  local output
  output=$(run_hook "healthy-001") || true
  assert_empty "no output" "$output"
}

test_warning_outputs_delta() {
  echo "warning (30%) → /delta instruction"
  create_bridge "warn-001" 30
  clean_state "warn-001"
  local output
  output=$(run_hook "warn-001") || true
  assert_contains "has additionalContext" "additionalContext" "$output"
  assert_contains "has /delta instruction" "Execute /delta" "$output"
  assert_contains "is warning level" "at a good stopping point" "$output"
}

test_critical_outputs_delta_now() {
  echo "critical (20%) → /delta NOW"
  create_bridge "crit-001" 20
  clean_state "crit-001"
  local output
  output=$(run_hook "crit-001") || true
  assert_contains "has additionalContext" "additionalContext" "$output"
  assert_contains "has NOW" "NOW" "$output"
  assert_contains "no new work" "Do not start new work" "$output"
}

test_delta_flag_suppresses() {
  echo "delta flag → second call suppressed"
  create_bridge "flag-001" 30
  clean_state "flag-001"
  # First call: emits and creates delta flag
  run_hook "flag-001" >/dev/null || true
  # Remove warn_file so debounce doesn't interfere
  rm -f "${TMPDIR_BASE}/claude-ctx-flag-001-warned"
  # Second call: delta flag should suppress
  local output
  output=$(run_hook "flag-001") || true
  assert_empty "second call suppressed" "$output"
}

test_escalation_retriggers() {
  echo "warning→critical escalation → re-triggers"
  create_bridge "esc-001" 30
  clean_state "esc-001"
  # First call at warning level
  run_hook "esc-001" >/dev/null || true
  # Update bridge to critical, remove warn_file to bypass debounce
  create_bridge "esc-001" 20
  rm -f "${TMPDIR_BASE}/claude-ctx-esc-001-warned"
  # Should re-trigger due to escalation
  local output
  output=$(run_hook "esc-001") || true
  assert_contains "re-triggered" "additionalContext" "$output"
  assert_contains "has NOW" "NOW" "$output"
}

test_stale_bridge() {
  echo "stale bridge → no output"
  local old_ts=$(($(date +%s) - 120))
  create_bridge "stale-001" 30 "$old_ts"
  clean_state "stale-001"
  local output
  output=$(run_hook "stale-001") || true
  assert_empty "no output for stale" "$output"
}

test_missing_bridge() {
  echo "missing bridge → no output"
  local output
  output=$(run_hook "nobridge-001") || true
  assert_empty "no output" "$output"
}

test_debounce() {
  echo "debounce → intermediate calls suppressed"
  create_bridge "deb-001" 30
  clean_state "deb-001"
  # First call: emits (calls_since=0, doesn't debounce)
  run_hook "deb-001" >/dev/null || true
  # Remove delta flag to isolate debounce behavior
  rm -f "${TMPDIR_BASE}/claude-ctx-deb-001-delta"
  # Second call: calls_since=1, < DEBOUNCE_CALLS=5 → debounced
  local output
  output=$(run_hook "deb-001") || true
  assert_empty "debounce suppresses" "$output"
}

test_no_jq() {
  echo "jq unavailable → no output"
  create_bridge "nojq-001" 30
  clean_state "nojq-001"
  local output
  # PATH=/bin keeps cat/date but excludes /usr/bin/jq and ~/.local/bin/jq
  output=$(printf '{"tool_name":"Read","session_id":"nojq-001"}' | TMPDIR="$TMPDIR_BASE" PATH="/bin" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output without jq" "$output"
}

echo "=== context-monitor.sh tests ==="
test_empty_stdin
test_no_session_id
test_healthy_context
test_warning_outputs_delta
test_critical_outputs_delta_now
test_delta_flag_suppresses
test_escalation_retriggers
test_stale_bridge
test_missing_bridge
test_debounce
test_no_jq

report_results
