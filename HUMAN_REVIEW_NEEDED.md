# Human Review — Phase 4 → Phase 5 Gate

## Completed: Phase 4 (Critic Update)

**Tasks 15-16 completed:**

1. **Updated `.claude/agents/critic.md`** — Added FIGURE-PROPOSAL as 5th mode:
   - Triggered by `FIGURE-PROPOSAL critic` in checkpoint's Next Task
   - Reads deep-reader `notes.md` Figure Opportunities sections + `report.tex` quantitative claims
   - Inventories existing figures to avoid duplication
   - Evaluates candidates on: data availability, visual impact, claim support
   - Ranks proposals by impact (HIGH/MEDIUM/LOW)
   - Outputs `figure_proposals.md` + appends approval section to `HUMAN_REVIEW_NEEDED.md`
   - Flow: critic proposes → human approves → research-coder implements → figure-stylist reviews

2. **Updated `specs/critic-output-format.md`** — Added figure proposal format:
   - `figure_proposals.md` template: self-contained entries with impact level, chart type, data sources with paths, data points table, rationale, design notes
   - Impact criteria: HIGH (central thesis, 3+ sources), MEDIUM (secondary, 2 sources), LOW (illustrative, single source)
   - `HUMAN_REVIEW_NEEDED.md` Figure Proposals section: checkbox approval list
   - 5 commit gates for figure proposal mode

## Next: Phase 5 (Venue Convention + Housekeeping)

**What Phase 5 will do:**
- Task 17: Update `scripts/init-project.sh` to create `inputs/` directory during project init
- Task 18: Update `.claude/agents/README.md` to document all new agents (editor, coherence-reviewer, provocateur, synthesizer, triage) with tool summaries + `inputs/` convention

These are low-risk infrastructure changes. No agent prompts or tool code will be modified.
