---
name: delta
description: Write Delta (plan-to-implementation diff) before compaction. Records
  discoveries, design changes, and decisions not in SOW/Spec. Use when user
  mentions delta, デルタ, コンテキスト保存, compact前, コンテキスト残量警告.
allowed-tools: Read, Write, Glob, Grep, Bash
model: opus
user-invocable: true
---

# /delta - Pre-Compact Delta Generation

Write a Delta file capturing deviations from SOW/Spec before compacting.

## Execution

1. Find the active SOW/Spec:
   - Check `~/.claude/workspace/.current-sow` for path
   - Or scan `~/.claude/workspace/planning/` for recent sow.md/spec.md
   - If none found, skip SOW/Spec comparison and record general decisions

2. Review current context and extract:
   - Discoveries: problems or constraints found during implementation
   - Design changes: deviations from SOW/Spec with rationale
   - Decisions: choices made during discussion not recorded in plan
   - Pending work: incomplete tasks and next actions

3. Write to `~/.claude/workspace/delta/delta-${CLAUDE_SESSION_ID}.md` (create directory if
   needed, overwrite if exists)

4. Format (see template below)

5. Generate compact focus argument:
   - Review the Delta content (especially Pending and Decisions)
   - Compose a single-line focus instruction for `/compact` that tells the
     compactor what to prioritize preserving
   - Example: "Delta recorded. Pending: Gap 2 HANDOFF.md impl. Decision:
     two-layer Delta adopted"
   - Include: current task status, key decisions, what the user will do next

6. Run compact:
   - Output: "Delta written to ~/.claude/workspace/delta/delta-{SESSION_ID}.md"
   - After outputting, immediately run `/compact [focus argument]` yourself.
   - `/compact` is a built-in command. Type it directly as your next action
     after this skill completes, as if the user had typed it.
   - Fallback: if `/compact` cannot be executed, copy the command to clipboard
     via Bash: `echo -n '/compact [focus argument]' | pbcopy`
     Then show the command and confirm it was copied:

     ```text
     /compact [focus argument]
     ```

     Copied to clipboard. Cmd+V to paste and run.

## Delta Template

```markdown
# Delta

SOW: [path or "none"] Generated: [timestamp]

## Discoveries

- [finding and its impact]

## Design Changes

| Original Plan   | Actual         | Rationale |
| --------------- | -------------- | --------- |
| [from SOW/Spec] | [what changed] | [why]     |

## Decisions

- [decision and context]

## Pending

- [ ] [next action]
```

## Constraints

- Do NOT read the transcript file. Use only current context.
- Keep Delta concise. Max ~100 lines.
- If nothing significant to record, write minimal Delta and note it.
- Compact focus argument: 1 line, ~50-100 chars. Task status + next action.
