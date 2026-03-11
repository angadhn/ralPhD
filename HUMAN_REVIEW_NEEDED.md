# Stage Gate: Phase 6 → Phase 7

## Phase 6 Complete: Prompt Audit

### What was done (Task 19)

1. **Shared boilerplate extracted:** Created `.claude/agents/agent-base.md` — yield/commit/checkpoint protocol shared by all 11 agents.
2. **Output format specs compressed:**
   - `specs/synthesizer-output-format.md`: 278 → 47 lines (examples moved to `templates/synthesizer-synthesis.md` and `templates/synthesizer-section-outline.md`)
   - `specs/triage-output-format.md`: 262 → 49 lines (examples moved to `templates/triage-report.md` and `templates/triage-reading-plan.md`)
3. **All 11 agent prompts audited:**
   - Added `Upstream: X → this → Y` ordering to every agent
   - Added `Inherits: agent-base.md` to every agent
   - Removed duplicated yield protocol, incremental commit, and yield check boilerplate
   - Converted negative prompts ("Does not edit") to positive ("Read-only on…", "Produces … only")
   - Compressed operational guardrails
   - Moved commit gate details to spec files where full checklists live
   - Net reduction: ~89 lines across agents
4. **README.md updated as planner's menu:** Agent table now includes upstream/downstream and when-to-assign columns.

### Token costs (post-audit)

| Agent | Lines | ~Tokens | Agent | Lines | ~Tokens |
|---|---|---|---|---|---|
| scout | 70 | 864 | editor | 100 | 1218 |
| triage | 84 | 1170 | coherence-reviewer | 90 | 1371 |
| deep-reader | 85 | 1145 | paper-writer | 151 | 2195 |
| critic | 124 | 2041 | research-coder | 94 | 1240 |
| provocateur | 82 | 1367 | figure-stylist | 57 | 684 |
| synthesizer | 90 | 1454 | agent-base | 26 | 296 |

Largest prompts are paper-writer (3 modes) and critic (5 modes) — size is justified by complexity.

## Phase 7: What's next

- **Task 20:** Verify tool registration — run each agent and confirm its tools are available
- **Task 21:** Verify agent file loading — confirm each new agent loads successfully

These are runtime verification tasks. They will invoke `ralph_agent.py` with test tasks.

## Action needed

Review the audit changes and approve proceeding to Phase 7.
