# Human Review — Phase 2 → Phase 3 Gate

## What was completed (Phase 2: Editor Cycle)

All 5 tasks in Phase 2 are done:

| Task | File | Summary |
|------|------|---------|
| 4. Editor agent | `.claude/agents/editor.md` | Substantiated editing agent — section-by-section, every edit requires justification from 6 categories. Pre/post `check_language` diagnostics. |
| 5. Editor output format | `specs/editor-output-format.md` | `change_log.md` template with per-edit justification, 6 justification categories, commit gates, minimal edit principle. |
| 6. Coherence reviewer agent | `.claude/agents/coherence-reviewer.md` | Read-only whole-manuscript consistency checker. Four ordered checks: promise-delivery alignment, terminology consistency, internal contradictions, novelty claims vs related work. Skim-first approach. |
| 7. Coherence reviewer output format | `specs/coherence-reviewer-output-format.md` | `coherence_review.md` template with severity levels (CRITICAL/MODERATE/MINOR), verdict logic, term/acronym registries, commit gates. |
| 8. Paper-writer REVIEW-EDITS mode | `.claude/agents/paper-writer.md` (updated) | Third mode for reviewing editor changes. Accept-by-default (≥80%), per-change decisions with reasoning, `edit_review.md` output. |

### Tool registrations (from Phase 1, already done)
- `coherence-reviewer` registered in `tools/__init__.py` with `check_claims` + `check_language`
- `editor` registered with `check_claims` + `check_language` + `citation_lint` + `citation_verify_all`

## What comes next (Phase 3: Analysis Agents)

Phase 3 creates three new analysis agents and their output format specs:

| Task | What | Key design choices |
|------|------|--------------------|
| 9. Provocateur agent | `.claude/agents/provocateur.md` | Finds gaps no other agent covers — cross-domain bridges, inverted assumptions, negative space. `_ESSENTIALS` only. |
| 10. Provocateur output format | `specs/provocateur-output-format.md` | `provocations.md` output format. |
| 11. Synthesizer agent | `.claude/agents/synthesizer.md` | Merges critic + deep-reader reports into section outline, merged master.bib, synthesis narrative. Tools: `citation_lint`, `citation_verify_all`. |
| 12. Synthesizer output format | `specs/synthesizer-output-format.md` | Synthesizer output format. |
| 13. Triage agent | `.claude/agents/triage.md` | Between scout and deep-reader. Corpus dedup, grade conflict resolution, reading plan. Tools: `pdf_metadata`, `citation_verify_all`. |
| 14. Triage output format | `specs/triage-output-format.md` | Triage output format. |

## Review questions

1. Are the Phase 2 agent definitions (editor, coherence-reviewer, paper-writer REVIEW-EDITS) aligned with your intended workflow?
2. Should any design choices be adjusted before building the analysis agents?
3. Ready to proceed to Phase 3?

Delete this file to proceed.
