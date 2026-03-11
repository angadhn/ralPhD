# Human Review Needed — Phase 1 → Phase 2 Gate

## Completed: Phase 1 (New Tools)

All 3 tasks done:

1. **specs/evidence-format.md** — JSONL schema for evidence ledger (claim, source_key, source_section, extraction_type, confidence, reviewer)
2. **tools/claims.py** — `check_claims` tool. Cross-references .tex + evidence-ledger.jsonl + .bib. Flags: low-confidence inferences, stale entries, uncovered citations. Registered for editor, critic, coherence-reviewer.
3. **tools/checks.py** — `citation_verify_all` tool. Batch-verifies all DOIs in a .bib file via CrossRef. Reports: verified/failed/no-DOI/mismatches. Registered for scout, editor, critic (triage/synthesizer when agents are created).

## Next: Phase 2 (Editor Cycle)

Tasks 4-8 create the editing pipeline:
- **Task 4:** `.claude/agents/editor.md` — academic editor agent prompt
- **Task 5:** `specs/editor-output-format.md` — editor checkpoint output spec
- **Task 6:** `.claude/agents/coherence-reviewer.md` — cross-section coherence checker
- **Task 7:** `specs/coherence-reviewer-output-format.md` — output format spec
- **Task 8:** Update `paper-writer.md` with REVIEW-EDITS mode

## Action Required

Review Phase 1 deliverables and approve Phase 2 to proceed.
Delete this file to resume.
