# Human Review Needed

## Completed: Phase 1 — Create shared citation module

**Task 1** is done. `tools/_citation.py` (679 lines) extracts all 17 implementation functions from `scripts/citation_tools.py` into a shared internal module. No TOOLS dict — it's an import-only module used by `tools/checks.py` and `tools/download.py`.

- Import verification: all 17 functions importable
- Full test suite: 72/72 passed
- Commit: `1bb9534`

## Next: Phase 2 — Rewrite tools/checks.py

Tasks 2–5 will inline `check_language.py`, `check_journal.py`, `check_figure.py` into `tools/checks.py` and rewire the 5 citation handlers to import from `tools/_citation` instead of shelling out via subprocess.

This is a large change to `tools/checks.py` (currently 323 lines, will grow substantially). Please confirm to proceed.
