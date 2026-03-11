WARNING_THRESHOLD=35
CRITICAL_THRESHOLD=25
STALE_SECONDS=60

parse_bridge() {
    # Sets: session_id, tool_name, ctx_dir, bridge_content, remaining
    input=""
    if [ ! -t 0 ]; then
        IFS= read -r -t 1 -d '' input 2>/dev/null
    fi
    [ -z "$input" ] && return 1

    case "$input" in
        *'"session_id"'*) ;;
        *) return 1 ;;
    esac
    session_id="${input#*\"session_id\":\"}"
    session_id="${session_id%%\"*}"
    [[ "$session_id" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [ ${#session_id} -gt 128 ] && return 1

    tool_name=""
    case "$input" in
        *'"tool_name"'*)
            tool_name="${input#*\"tool_name\":\"}"
            tool_name="${tool_name%%\"*}"
            [[ "$tool_name" =~ ^[a-zA-Z0-9_:-]+$ ]] || tool_name=""
            ;;
    esac

    ctx_dir="${TMPDIR:-/tmp}"
    local bridge="${ctx_dir}/claude-ctx-${session_id}.json"
    bridge_content=$(< "$bridge" 2>/dev/null) || return 1
    [ -z "$bridge_content" ] && return 1

    remaining="${bridge_content#*\"remaining_pct\":}"
    remaining="${remaining%%[^0-9]*}"
    [[ "$remaining" =~ ^[0-9]+$ ]] || return 1
    [ "$remaining" -gt 100 ] && return 1

    return 0
}

check_staleness() {
    # Uses: bridge_content (set by parse_bridge)
    local ts now
    ts="${bridge_content#*\"ts\":}"
    ts="${ts%%[^0-9]*}"
    [[ "${ts:-0}" =~ ^[0-9]+$ ]] || return 1
    now=${EPOCHSECONDS:-$(date +%s)}
    [ "$ts" -gt $((now + 120)) ] && return 1
    [ "$ts" -lt 1000000000 ] && return 1
    [ $((now - ts)) -gt "$STALE_SECONDS" ] && return 1
    return 0
}
