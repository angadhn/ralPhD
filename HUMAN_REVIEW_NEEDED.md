# Human Review Needed — Phase 3 → Phase 4 Gate

## Completed: Phase 3 — Rewrite tools/pdf.py

- **Task 6:** Inlined `pdf_metadata.py` into `tools/pdf.py` — 3 functions (`get_fast_metadata`, `get_section_headings`, `estimate_reading_chunks`) + 3 regex patterns. `fitz` imported lazily. Handler returns `json.dumps(result, indent=2)`.
- **Task 7:** Inlined `extract_figure.py` into `tools/pdf.py` — 4 functions (`parse_page_range`, `list_images`, `extract_images`, `extract_page_as_image`). All refactored from `print()` to return strings via `io.StringIO`. `subprocess` and `_run_cmd` removed entirely from `pdf.py`.

All 72/72 tests pass after each task.

## Next: Phase 4 — Modify tools/download.py

- **Task 8:** Replace subprocess in `_register_manifest()` with `from tools._citation import manifest_add`. Remove `import subprocess`. Keep all Unpaywall/SciHub logic unchanged.

This is a small, targeted change — one handler in `download.py` currently shells out to `citation_tools.py manifest-add`. After this change it will call `manifest_add()` directly from the shared `tools/_citation.py` module.

## Status

- 7/11 tasks complete
- 72/72 tests passing
- Files modified so far: `tools/_citation.py` (created), `tools/checks.py` (rewritten), `tools/pdf.py` (rewritten)
- Scripts not yet deleted (that's Phase 5)

Delete this file to approve proceeding to Phase 4.
