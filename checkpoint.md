# Checkpoint — fix-verify-and-loop-semantics

**Thread:** fix-verify-and-loop-semantics
**Last updated:** 2026-03-23
**Last agent:** coder
**Status:** in progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. auto_download papers_dir mismatch | done | RED: ffdd98c, GREEN: d8473c4. Fixed `output_dir` → `papers_dir` key at verify.py:170 |
| 2. terminal checkpoint dispatch | done | RED: 401bb35, GREEN: 27e421c. Structured-task check rejects prose; falls through to plan |
| 3. DOI-to-BibTeX fail-open | pending | _citation.py:575,578 returns {} silently on missing deps |
| 4. one-task-per-iteration enforcement | pending | ralph-loop.sh has no post-iteration plan diff validator |
| 5. final review | pending | depends: 1,2,3,4 |

## Last Reflection

Task 2 complete. detect.sh now requires next_task to start with digit or checkbox to be treated as a task; all other text falls through to the plan.

## Next Task

- [ ] 3. Test and fix DOI-to-BibTeX fail-open (red/green TDD) — **coder**
