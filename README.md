# delta

Claude Code plugin for pre-compact Delta generation. Captures session context (discoveries, design changes, decisions, pending work) before context window compaction so nothing is lost between sessions.

## What is a Delta?

A Delta records the diff between your plan (SOW/Spec) and what actually happened during implementation:

- **Discoveries** - problems or constraints found during implementation
- **Design Changes** - deviations from SOW/Spec with rationale
- **Decisions** - choices made during discussion not recorded in plan
- **Pending** - incomplete tasks and next actions

## How it works

```
Context filling up
        │
        ▼
┌─────────────────┐    ┌──────────────┐    ┌─────────────┐
│ context-monitor │───▶│   /delta      │───▶│  /compact    │
│  (PostToolUse)  │    │  (Skill)     │    │  (manual)    │
└─────────────────┘    └──────────────┘    └─────────────┘
        │                      │
        │                      ▼
        │              delta-{SESSION_ID}.md
        │
        ▼ (if auto-compact fired first)
┌───────────────────────┐
│ session-start-compact │
│    (SessionStart)     │──▶ Auto-generates Delta from transcript
└───────────────────────┘
```

1. **context-monitor** (PostToolUse hook) watches context window usage via bridge file
   - **WARNING** at ≤35% remaining: suggests running `/delta`
   - **CRITICAL** at ≤25% remaining: demands immediate `/delta` execution
   - Debounces warnings (every 5 tool calls)
2. **`/delta` skill** generates a Delta file from current session context
3. **session-start-compact** (SessionStart hook) catches auto-compact events and generates Delta from the transcript as a fallback

## Installation

```bash
claude plugin add thkt/delta
```

## Plugin structure

```
.claude-plugin/
  plugin.json          # Plugin metadata (name, version, description)
hooks/
  hooks.json           # Hook registrations (PostToolUse + SessionStart)
  context-monitor.sh   # Context window usage monitor
  session-start-compact.sh  # Auto-compact fallback Delta generator
skills/
  delta/
    SKILL.md           # /delta skill definition
tests/
  test-helpers.sh      # Test utilities (assert_eq, assert_contains, etc.)
  test-context-monitor.sh        # 16 tests
  test-session-start-compact.sh  # 13 tests
```

## Configuration

### context-monitor thresholds

Edit `hooks/context-monitor.sh` to adjust:

| Variable             | Default | Description                        |
| -------------------- | ------- | ---------------------------------- |
| `WARNING_THRESHOLD`  | 35      | Remaining % to trigger warning     |
| `CRITICAL_THRESHOLD` | 25      | Remaining % to trigger critical    |
| `STALE_SECONDS`      | 60      | Max age of bridge file data        |
| `DEBOUNCE_CALLS`     | 5       | PostToolUse calls between warnings |

### Bridge file

The context monitor reads from `$TMPDIR/claude-ctx-{session_id}.json`, written by a statusline hook (not included in this plugin). Expected format:

```json
{ "remaining_pct": 42, "ts": 1710000000 }
```

## Dependencies

- **zsh** - hook scripts use zsh
- **jq** - required for JSON output (warning path only for context-monitor, always for session-start-compact)

## Running tests

```bash
zsh tests/test-context-monitor.sh
zsh tests/test-session-start-compact.sh
```

## License

MIT
