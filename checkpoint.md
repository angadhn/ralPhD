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
| 4. one-task-per-iteration enforcement | done | RED: 7b5c58d, GREEN: 87ee3a2. `validate_single_task_completion` in post-run.sh + snapshot/check in ralph-loop.sh |
| 5. final review | pending | depends: 1,2,3,4 |

## Last Reflection

Task 4 complete. Added `validate_single_task_completion()` to `lib/post-run.sh` — counts `- [x]` lines before/after iteration, rejects >1 newly checked. Wired into `ralph-loop.sh` serial build path with plan snapshot before dispatch and validation after success. On violation, circuit breaker increments and loop breaks.

## Next Task

- [ ] 5. Final review of all 4 fixes — verify tests pass, check for regressions, confirm acceptance criteria (depends: 1,2,3,4) — **critic**
