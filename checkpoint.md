# Checkpoint — colocated-tools-refactor

**Thread:** colocated-tools-refactor
**Last updated:** 2026-03-11
**Last agent:** coder
**Status:** Phase 2 complete

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Create `tools/_citation.py` | DONE | 679 lines, 17 functions extracted, all imports verified, 72/72 tests pass |
| 2. Inline `check_language.py` into `tools/checks.py` | DONE | All functions inlined (strip_latex_commands through check_file), _handle_check_language uses io.StringIO capture, 72/72 tests pass |
| 3. Inline `check_journal.py` into `tools/checks.py` | DONE | 5 functions inlined (_journal_parse_pub_reqs, count_words_tex, check_bib_fields, collect_tex_files, collect_bib_files), handler builds text report directly, 72/72 tests pass |
| 4. Inline `check_figure.py` into `tools/checks.py` | DONE | 4 functions inlined (_figure_parse_pub_reqs, check_raster, check_pdf_figure, collect_figure_files), PIL/fitz lazy-imported, handler returns JSON, 72/72 tests pass |
| 5. Rewire 5 citation handlers in `tools/checks.py` | DONE | All 5 handlers import from tools._citation, subprocess removed entirely from checks.py, 72/72 tests pass |

## Last Reflection

<none yet>

## Next Task

Task 6: Inline `pdf_metadata.py` into `tools/pdf.py` — coder
(Phase 3 begins — stage gate: HUMAN_REVIEW_NEEDED required)
