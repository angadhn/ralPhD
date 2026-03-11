# Human Review Needed — Phase 4 Complete

## What was completed

**Phase 4 — Modify tools/download.py** (Task 8)

- Replaced subprocess call in `_register_manifest()` with direct `from tools._citation import manifest_add`
- Removed `import subprocess` entirely from `tools/download.py`
- All Unpaywall/SciHub download logic unchanged
- 72/72 tests pass

**Overall progress:** 8/11 tasks complete. All 4 tool modules (`checks.py`, `pdf.py`, `download.py`) now call implementation functions directly — zero subprocess indirection remains in the tools layer.

## What Phase 5 will do

**Phase 5 — Verify and clean up** (Tasks 9-11)

- **Task 9:** Run full test suite as final verification
- **Task 10:** Delete 6 merged scripts (`check_language.py`, `check_journal.py`, `check_figure.py`, `citation_tools.py`, `pdf_metadata.py`, `extract_figure.py`) and re-run tests
- **Task 11:** Update `tools/README.md` and module docstrings

This is the final cleanup phase — deleting the now-unused script files and updating documentation.
