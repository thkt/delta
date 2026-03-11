#!/bin/zsh
set +e

source "${0:A:h}/lib/bridge-parser.sh"

DEBOUNCE_CALLS=5

parse_bridge || exit 0

[ "$remaining" -gt "$WARNING_THRESHOLD" ] && exit 0

# --- Warning path (rare) — jq allowed below this line ---

check_staleness || exit 0

# Debounce
warn_file="${ctx_dir}/claude-ctx-${session_id}-warned"
calls_since=0
last_level=""

if [ -f "$warn_file" ]; then
    IFS=$'\t' read -r calls_since last_level < "$warn_file" 2>/dev/null
    [[ "$calls_since" =~ ^[0-9]+$ ]] || calls_since=0
    [[ "$last_level" =~ ^(warning|critical)$ ]] || last_level=""
    calls_since=$((calls_since + 1))
fi

current_level="warning"
[ "$remaining" -le "$CRITICAL_THRESHOLD" ] && current_level="critical"

severity_escalated=0
[ "$current_level" = "critical" ] && [ "$last_level" = "warning" ] && severity_escalated=1

if [ "$calls_since" -gt 0 ] && [ "$calls_since" -lt "$DEBOUNCE_CALLS" ] && [ "$severity_escalated" -eq 0 ]; then
    printf '%s\t%s\n' "$calls_since" "$last_level" > "$warn_file"
    exit 0
fi

# Fire-once per severity level; re-triggers on warning→critical escalation
delta_flag="${ctx_dir}/claude-ctx-${session_id}-delta"

if [ -f "$delta_flag" ]; then
    read -r prev_level < "$delta_flag" 2>/dev/null
    if [ "$current_level" != "critical" ] || [ "$prev_level" != "warning" ]; then
        exit 0
    fi
fi

if [ "$current_level" = "critical" ]; then
    message="Context ${remaining}% remaining. Non-delta tools are now blocked by context-gate. Run Skill(skill: \"delta\") immediately. Do not start new work."
else
    message="Context ${remaining}% remaining. Finish your current step, then run Skill(skill: \"delta\"). Avoid new exploration."
fi

{
    if command -v jq &>/dev/null; then
        jq -n --arg msg "$message" \
            '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}'
    else
        printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "${message//\"/\\\"}"
    fi
} && { printf '0\t%s\n' "$current_level" > "$warn_file"; printf '%s' "$current_level" > "$delta_flag"; }
