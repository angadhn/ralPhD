# Human Review Needed — Phase 3 → Phase 4 Gate

## Completed: Phase 3 — Analysis Agents

All 6 tasks in Phase 3 are done:

| Task | Deliverable | Status |
|------|------------|--------|
| 9 | `.claude/agents/provocateur.md` — 3 lenses: negative space, inverted assumptions, cross-domain bridges | ✅ |
| 10 | `specs/provocateur-output-format.md` — provocations.md template, impact levels, priority ranking | ✅ |
| 11 | `.claude/agents/synthesizer.md` — merges deep-reader + critic + provocateur into synthesis narrative | ✅ |
| 12 | `specs/synthesizer-output-format.md` — synthesis.md, master.bib, section_outline.md templates | ✅ |
| 13 | `.claude/agents/triage.md` — corpus deduplication, grade conflicts, reading plan generation | ✅ |
| 14 | `specs/triage-output-format.md` — triage_report.md, reading_plan.md, corpus_index_deduped.jsonl templates | ✅ |

All agents registered in `tools/__init__.py` AGENT_TOOLS with appropriate tool access.

## Next: Phase 4 — Critic Update

Two tasks:

- **Task 15:** Update `.claude/agents/critic.md` — add FIGURE-PROPOSAL mode. After reviewing deep-reader reports, identify claims needing visual support. Output `figure_proposals.md`.
- **Task 16:** Update `specs/critic-output-format.md` — add figure proposal format section.

This modifies an existing agent (critic) rather than creating new ones.

## Overall Progress

- Phases 1-3: ✅ Complete (14/21 tasks)
- Phase 4: Next (2 tasks — critic update)
- Phase 5: Pending (2 tasks — venue + housekeeping)
- Phase 6: Pending (1 task — prompt audit)
- Phase 7: Pending (2 tasks — verification)
