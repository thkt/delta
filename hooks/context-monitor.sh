#!/bin/zsh
set +e

# Context Monitor - PostToolUse hook
# Reads bridge file from statusline, injects agent-facing warnings
# when context window usage exceeds thresholds.
#
# Bridge file: $TMPDIR/claude-ctx-{session_id}.json
# Written by: hooks/lifecycle/statusline.sh (render_context)
#
# Thresholds:
#   WARNING  (remaining <= 35%): Wrap up current work
#   CRITICAL (remaining <= 25%): Stop and inform user

WARNING_THRESHOLD=35
CRITICAL_THRESHOLD=25
STALE_SECONDS=60
DEBOUNCE_CALLS=5 # emit warning every N PostToolUse calls (not every call)

input=""
if [ ! -t 0 ]; then
    IFS= read -r -t 3 -d '' input 2>/dev/null
fi
[ -z "$input" ] && exit 0

case "$input" in
    *'"session_id"'*) ;;
    *) exit 0 ;;
esac
# Hot-path: manual parse avoids jq fork. Assumes top-level string field.
session_id="${input#*\"session_id\":\"}"
session_id="${session_id%%\"*}"
[[ "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]] || exit 0

ctx_dir="${TMPDIR:-/tmp}"
bridge="${ctx_dir}/claude-ctx-${session_id}.json"
bridge_content=$(cat "$bridge" 2>/dev/null) || exit 0
[ -z "$bridge_content" ] && exit 0

remaining="${bridge_content#*\"remaining_pct\":}"
remaining="${remaining%%[,\}]*}"
[[ "$remaining" =~ ^[0-9]+$ ]] || exit 0

[ "$remaining" -gt "$WARNING_THRESHOLD" ] && exit 0

# --- Warning path (rare) — jq allowed below this line ---

command -v jq &>/dev/null || exit 0

bridge_data=$(printf '%s' "$bridge_content" | jq -r '[.remaining_pct, .ts] | @tsv' 2>/dev/null)
[ -z "$bridge_data" ] && exit 0

IFS=$'\t' read -r remaining ts <<< "$bridge_data"

now=${EPOCHSECONDS:-$(date +%s)}
[[ "${ts:-0}" =~ ^[0-9]+$ ]] || exit 0
[ $((now - ts)) -gt $STALE_SECONDS ] && exit 0

# Debounce
warn_file="${ctx_dir}/claude-ctx-${session_id}-warned"
calls_since=0
last_level=""

if [ -f "$warn_file" ]; then
    IFS=$'\t' read -r calls_since last_level < "$warn_file" 2>/dev/null
    [[ "$calls_since" =~ ^[0-9]+$ ]] || calls_since=0
    calls_since=$((calls_since + 1))
fi

is_critical=0
[ "$remaining" -le "$CRITICAL_THRESHOLD" ] && is_critical=1

current_level="warning"
[ "$is_critical" -eq 1 ] && current_level="critical"

severity_escalated=0
[ "$current_level" = "critical" ] && [ "$last_level" = "warning" ] && severity_escalated=1

if [ "$calls_since" -gt 0 ] && [ "$calls_since" -lt "$DEBOUNCE_CALLS" ] && [ "$severity_escalated" -eq 0 ]; then
    printf '%s\t%s\n' "$calls_since" "$last_level" > "$warn_file"
    exit 0
fi

printf '0\t%s\n' "$current_level" > "$warn_file"

# One-shot /delta trigger with warning→critical escalation
delta_flag="${ctx_dir}/claude-ctx-${session_id}-delta"

if [ -f "$delta_flag" ]; then
    read -r prev_level < "$delta_flag" 2>/dev/null
    if [ "$current_level" != "critical" ] || [ "$prev_level" != "warning" ]; then
        exit 0
    fi
fi

if [ "$current_level" = "critical" ]; then
    message="Context ${remaining}% remaining. Execute /delta NOW via Skill tool (skill: \"delta\"). Do not start new work."
else
    message="Context ${remaining}% remaining. Execute /delta via Skill tool (skill: \"delta\") at a good stopping point. Avoid unnecessary exploration."
fi

jq -n --arg msg "$message" \
    '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$msg}}' \
    && printf '%s' "$current_level" > "$delta_flag"
