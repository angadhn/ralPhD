## Identity

<!-- 1-2 sentences: What is this agent? What does it produce? -->
<agent-role> — <what it does and what it outputs>.

## Inputs (READ these)

<!-- List ONLY what this agent needs. Every item should justify its context cost. -->
- `checkpoint.md` — current state (Knowledge State table + Next Task)
- `reasoning-notes.md` — grep for your phase and upstream phases only; do NOT read the whole file
- `<input-file-1>` — <why this agent needs it>
- `<input-file-2>` — <why this agent needs it>

## Operational Guardrails

<!-- Constraints that keep this agent efficient and predictable. -->

- **Pre-estimate:** <how to budget context before starting>
- **Priority order:** (1) <most important>, (2) <next>, (3) <least critical, skip if context tight>
- **Context check:** <when to check and what to do at thresholds>

<!-- Optional: context threshold table for agents that do heavy reading -->
<!--
| Context % | Action |
|-----------|--------|
| < 30% | Safe — proceed normally |
| 30-40% | Caution — finish current item ONLY, then yield |
| >= 40% | STOP — write outputs immediately, commit, yield |
-->

## Output Format

```
AI-generated-outputs/<thread>/<phase-NN-name>/
├── <output-file-1>    # Description
├── <output-file-2>    # Description
├── <output-file-3>    # Description
└── phase-summary.md   # What was accomplished, key decisions, what passes to next phase
```

<!-- If this agent writes structured data (JSON, JSONL), define the schema: -->
<!--
### <filename> schema
```json
{
  "field1": "description",
  "field2": "description"
}
```
-->

## Workflow

1. Read `checkpoint.md` — determine current task from Knowledge State + Next Task
2. Read `reasoning-notes.md` — grep for `## Phase <N>` headers relevant to your work
3. <Step 3>
4. <Step 4>
...
N-3. Append to `reasoning-notes.md` under `## Phase <N> — <name>` with key decisions and rationale
N-2. Write `AI-generated-outputs/<thread>/<phase-NN-name>/phase-summary.md` (~10 lines: what was accomplished, key decisions, what passes to next phase, issues/partial work)
N-1. Update `checkpoint.md` — replace Knowledge State section with current phase's table, update Next Task
N. Commit all outputs: phase outputs, phase-summary.md, reasoning-notes.md, checkpoint.md

## Ralph Loop Yield Protocol

- Check `/tmp/ralph-context-pct` before <when — e.g., every Read call, every major step>
- If `[ -f /tmp/ralph-yield ]`: <what to save before exiting>
- Before exiting: commit <critical files>, reasoning-notes.md, checkpoint.md
