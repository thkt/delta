---
name: delta
description:
  Write Delta (plan-to-implementation diff) before compaction. Records
  discoveries, design changes, and decisions not in SOW/Spec. Use when user
  mentions delta, デルタ, コンテキスト保存, compact前, コンテキスト残量警告.
allowed-tools: Read, Write, Glob, Grep
model: opus
user-invocable: true
---

# /delta - Pre-Compact Delta Generation

Write a Delta file capturing deviations from SOW/Spec before compacting.

## Execution

1. Find the active SOW/Spec:
   - Check `workspace/.current-sow` for path
   - Or scan `workspace/planning/` for recent sow.md/spec.md
   - If none found, skip SOW/Spec comparison and record general decisions

2. Review current context and extract:
   - Discoveries: problems or constraints found during implementation
   - Design changes: deviations from SOW/Spec with rationale
   - Decisions: choices made during discussion not recorded in plan
   - Pending work: incomplete tasks and next actions

3. Write to `workspace/delta/delta-${CLAUDE_SESSION_ID}.md` (create directory if
   needed, overwrite if exists)

4. Format (see template below)

5. Generate compact focus argument:
   - Review the Delta content (especially Pending and Decisions)
   - Compose a single-line Japanese focus instruction for `/compact` that tells
     the compactor what to prioritize preserving
   - Example: "Delta記録済み。Pending: Gap 2 HANDOFF.md実装。設計判断: two-layer
     Delta採用"
   - Include: current task status, key decisions, what the user will do next

6. Report and suggest compact:
   - Output: "Delta を workspace/delta/delta-{SESSION_ID}.md に書き出したで！"
   - Then show the generated focus argument as a copyable `/compact` command:

     ```text
     /compact [focus argument]
     ```

   - Note: `/compact` is a built-in CLI command and cannot be invoked via Skill
     tool. The user must run it manually.

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
