# Checkpoint — howler-port

**Thread:** howler-port
**Last updated:** 2026-03-11
**Last agent:** research-coder
**Status:** Phase 4 complete — all 16 tasks done. Phase 5 next (venue convention + housekeeping).

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. evidence-format spec | done | specs/evidence-format.md — JSONL schema with 6 fields |
| 2. check_claims tool | done | tools/claims.py — cross-refs .tex + ledger + .bib; registered for critic, editor, coherence-reviewer |
| 3. citation_verify_all tool | done | tools/checks.py — batch DOI verify via CrossRef; registered for scout, editor, critic (triage/synthesizer when created) |
| 4. editor agent | done | .claude/agents/editor.md — substantiated editing, section-by-section, pre/post diagnostics |
| 5. editor output format spec | done | specs/editor-output-format.md — change_log.md structure, 6 justification categories, commit gates, minimal edit principle |
| 6. coherence-reviewer agent | done | .claude/agents/coherence-reviewer.md — 4 checks: promise-delivery, terminology, contradictions, novelty claims. Read-only on .tex, skim-first approach. |
| 7. coherence-reviewer output format | done | specs/coherence-reviewer-output-format.md — coherence_review.md template, 3 severity levels, verdict logic, commit gates |
| 8. paper-writer REVIEW-EDITS mode | done | Updated paper-writer.md — third mode for reviewing editor changes, accept/revert with reasoning, edit_review.md output |
| 9. provocateur agent | done | .claude/agents/provocateur.md — 3 lenses: negative space, inverted assumptions, cross-domain bridges. _ESSENTIALS only. Registered in AGENT_TOOLS. |
| 10. provocateur output format | done | specs/provocateur-output-format.md — provocations.md template, impact levels per lens, priority ranking, commit gates |
| 11. synthesizer agent | done | .claude/agents/synthesizer.md — merges deep-reader + critic + provocateur into synthesis narrative, master.bib, section outline. Tools: citation_lint + citation_verify_all. Registered in AGENT_TOOLS. |
| 12. synthesizer output format | done | specs/synthesizer-output-format.md — synthesis.md (themes, conflicts, provocateur integration, story arc), master.bib (deduplicated, lint-clean), section_outline.md (claims→evidence mapping, word budgets). 16 commit gates. |
| 13. triage agent | done | .claude/agents/triage.md — corpus deduplication, grade conflict resolution, reading plan generation. Tools: pdf_metadata + citation_verify_all. Registered in AGENT_TOOLS. |
| 14. triage output format | done | specs/triage-output-format.md — templates for triage_report.md, reading_plan.md, corpus_index_deduped.jsonl |
| 15. Critic FIGURE-PROPOSAL mode | done | Updated critic.md — 5th mode: reads deep-reader notes/reports, inventories existing figs, evaluates data availability + visual impact + claim support, ranks by impact |
| 16. Critic output format update | done | Updated critic-output-format.md — figure_proposals.md template (per-proposal entries with impact/type/sources/rationale), HUMAN_REVIEW figure approval section, 5 commit gates |
| 17-18. Venue + housekeeping | pending | init-project.sh, README — Phase 5 |
| 19. Prompt audit | pending | Phase 6 |
| 20-21. Verification | pending | Tool + agent loading checks — Phase 7 |

## Last Reflection

Iteration 2 reflection: On track. Phase 3 nearly complete (13/14 tasks done). Pattern of agent+spec creation is efficient and consistent. No course corrections needed. After task 14, phase boundary triggers stage-gate review.

## Next Task

17. Update scripts/init-project.sh — create inputs/ directory research-coder
