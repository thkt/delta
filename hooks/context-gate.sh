#!/bin/zsh
set +e

source "${0:A:h}/lib/bridge-parser.sh"

parse_bridge || exit 0
[ -z "$tool_name" ] && exit 0

[ "$remaining" -gt "$CRITICAL_THRESHOLD" ] && exit 0

check_staleness || exit 0

case "$tool_name" in
    Skill|Read|Write|Glob|Grep) exit 0 ;;
esac

reason="Context ${remaining}% remaining (CRITICAL). Run Skill(skill: \"delta\") first. Non-delta tools are blocked until Delta is written."
if command -v jq &>/dev/null; then
    jq -n --arg reason "$reason" '{"decision":"block","reason":$reason}'
else
    printf '{"decision":"block","reason":"%s"}\n' "${reason//\"/\\\"}"
fi
