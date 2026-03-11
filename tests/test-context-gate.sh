#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
HOOK="$SCRIPT_DIR/../hooks/context-gate.sh"
TMPDIR_BASE="$(mktemp -d)"

cleanup() { rm -rf "$TMPDIR_BASE"; }
trap cleanup EXIT

run_gate() {
  local session_id="$1" tool_name="$2"
  local json='{"tool_name":"'"$tool_name"'","session_id":"'"$session_id"'"}'
  printf '%s' "$json" | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null
}

# --- Passthrough tests (should NOT block) ---

test_empty_stdin() {
  echo "empty stdin → no output (allow)"
  local output
  output=$(echo "" | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_no_session_id() {
  echo "no session_id → no output (allow)"
  local output
  output=$(printf '{"tool_name":"Bash"}' | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "no output" "$output"
}

test_no_tool_name() {
  echo "no tool_name → no output (allow)"
  create_bridge "gate-notool" 20
  local output
  output=$(printf '{"session_id":"gate-notool"}' | TMPDIR="$TMPDIR_BASE" zsh "$HOOK" 2>/dev/null) || true
  assert_empty "allow without tool_name" "$output"
}

test_healthy_context() {
  echo "healthy (50%) → no output (allow)"
  create_bridge "gate-healthy" 50
  local output
  output=$(run_gate "gate-healthy" "Bash") || true
  assert_empty "allow at healthy" "$output"
}

test_warning_level_allows() {
  echo "warning (30%) → no output (allow, not critical)"
  create_bridge "gate-warn" 30
  local output
  output=$(run_gate "gate-warn" "Bash") || true
  assert_empty "allow at warning" "$output"
}

test_missing_bridge() {
  echo "missing bridge → no output (allow)"
  local output
  output=$(run_gate "gate-nobridge" "Bash") || true
  assert_empty "allow without bridge" "$output"
}

test_stale_bridge() {
  echo "stale bridge (critical) → no output (allow)"
  local old_ts=$(($(date +%s) - 120))
  create_bridge "gate-stale" 20 "$old_ts"
  local output
  output=$(run_gate "gate-stale" "Bash") || true
  assert_empty "allow stale bridge" "$output"
}

# --- Blocking tests (should block non-delta tools at critical) ---

test_critical_blocks_bash() {
  echo "critical (20%) + Bash → block"
  create_bridge "gate-block" 20
  local output
  output=$(run_gate "gate-block" "Bash") || true
  assert_contains "has decision block" '"decision": "block"' "$output"
  assert_contains "has reason" "Non-delta tools are blocked" "$output"
  assert_contains "has remaining" "20%" "$output"
}

test_critical_blocks_other_tools() {
  for tool in Edit Agent; do
    echo "critical (20%) + ${tool} → block"
    create_bridge "gate-block-${tool}" 20
    local output
    output=$(run_gate "gate-block-${tool}" "$tool") || true
    assert_contains "blocks ${tool}" '"decision": "block"' "$output"
  done
}

test_critical_at_boundary() {
  echo "critical (25%, boundary) → block"
  create_bridge "gate-boundary" 25
  local output
  output=$(run_gate "gate-boundary" "Bash") || true
  assert_contains "blocks at boundary" '"decision": "block"' "$output"
}

test_just_above_critical() {
  echo "just above critical (26%) → no output (allow)"
  create_bridge "gate-above" 26
  local output
  output=$(run_gate "gate-above" "Bash") || true
  assert_empty "allow at 26%" "$output"
}

# --- Allow tests (delta-related tools at critical) ---

test_critical_allows_delta_tools() {
  for tool in Skill Read Write Glob Grep; do
    echo "critical (20%) + ${tool} → allow"
    create_bridge "gate-allow-${tool}" 20
    local output
    output=$(run_gate "gate-allow-${tool}" "$tool") || true
    assert_empty "allow ${tool}" "$output"
  done
}

# --- Edge case ---

test_critical_blocks_mcp_tools() {
  echo "critical (20%) + mcp__slack__send → block"
  create_bridge "gate-mcp" 20
  local output
  output=$(run_gate "gate-mcp" "mcp__slack__send") || true
  assert_contains "blocks MCP tool" '"decision"' "$output"
}

test_critical_at_zero() {
  echo "critical (0%) → block"
  create_bridge "gate-zero" 0
  local output
  output=$(run_gate "gate-zero" "Bash") || true
  assert_contains "blocks at 0%" "0%" "$output"
}

test_no_jq() {
  echo "jq unavailable (critical) → still blocks (printf fallback)"
  create_bridge "gate-nojq" 20
  local output
  output=$(printf '{"tool_name":"Bash","session_id":"gate-nojq"}' | TMPDIR="$TMPDIR_BASE" PATH="/bin" zsh "$HOOK" 2>/dev/null) || true
  assert_contains "blocks without jq" '"decision":"block"' "$output"
}

echo "=== context-gate.sh tests ==="
test_empty_stdin
test_no_session_id
test_no_tool_name
test_healthy_context
test_warning_level_allows
test_missing_bridge
test_stale_bridge
test_critical_blocks_bash
test_critical_blocks_other_tools
test_critical_at_boundary
test_just_above_critical
test_critical_allows_delta_tools
test_critical_blocks_mcp_tools
test_critical_at_zero
test_no_jq

report_results
