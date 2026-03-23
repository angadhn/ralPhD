# Checkpoint — fix-verify-and-loop-semantics

**Thread:** fix-verify-and-loop-semantics
**Last updated:** 2026-03-23
**Last agent:** coder
**Status:** in progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. auto_download papers_dir mismatch | done | RED: ffdd98c, GREEN: d8473c4. Fixed `output_dir` → `papers_dir` key at verify.py:170 |
| 2. terminal checkpoint dispatch | pending | detect.sh:42 extracts last word; prose like "ready for review" yields bogus agent |
| 3. DOI-to-BibTeX fail-open | pending | _citation.py:575,578 returns {} silently on missing deps |
| 4. one-task-per-iteration enforcement | pending | ralph-loop.sh has no post-iteration plan diff validator |
| 5. final review | pending | depends: 1,2,3,4 |

## Last Reflection

Task 1 complete. One-line fix, verified with red/green TDD.

## Next Task

- [ ] 2. Test and fix terminal checkpoint dispatch (red/green TDD) — **coder**
