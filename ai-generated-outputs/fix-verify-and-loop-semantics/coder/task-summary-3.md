# Task 3 Summary — DOI-to-BibTeX fail-open

## What was changed

**Bug:** `_build_doi_bib_index()` in `tools/_citation.py` silently returned `{}` when:
1. `bibtexparser` was not installed (ImportError swallowed)
2. The `.bib` file path didn't exist (checked with `if not exists: return {}`)

This caused `verify.py` to proceed with an empty DOI→source_key index, meaning all ledger lookups silently failed — verification reported PDF_MISSING instead of surfacing the root cause.

**Fix:**
- `tools/_citation.py`: Removed the `try/except ImportError: return {}` and the silent `return {}` for missing files. Now raises `ImportError` and `FileNotFoundError` respectively.
- `tools/verify.py`: Wrapped `_build_doi_bib_index()` call in try/except, returning explicit error messages that name the dependency or missing file.

## Files modified
- `tools/_citation.py` — `_build_doi_bib_index()` now raises instead of returning `{}`
- `tools/verify.py` — catches and surfaces ImportError/FileNotFoundError from bib index builder
- `tests/test_doi_bibtex_failopen.py` — 3 RED/GREEN tests

## Test results
- RED commit: `8fdfa9d` — all 3 tests failed as expected
- GREEN commit: `00eae28` — all 3 tests pass
- No regressions in existing tests (`test_auto_download_papers_dir.py` still passes)
