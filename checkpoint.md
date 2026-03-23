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
| 3. DOI-to-BibTeX fail-open | done | RED: 8fdfa9d, GREEN: 00eae28. `_build_doi_bib_index` now raises ImportError/FileNotFoundError; verify.py catches and surfaces them |
| 4. one-task-per-iteration enforcement | pending | ralph-loop.sh has no post-iteration plan diff validator |
| 5. final review | pending | depends: 1,2,3,4 |

## Last Reflection

Task 3 complete. _build_doi_bib_index no longer swallows ImportError or missing-file errors. verify.py catches these and returns explicit error messages instead of silently proceeding with an empty DOI→source_key index.

## Next Task

- [ ] 4. Test and fix one-task-per-iteration enforcement (red/green TDD) — **coder**
