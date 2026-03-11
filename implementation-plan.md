# Implementation Plan — Colocated Tools Refactor

**Thread:** colocated-tools-refactor
**Created:** 2026-03-11
**Autonomy:** stage-gates

## Context

Tools have two layers: `tools/*.py` (thin subprocess wrappers with schemas) and `scripts/*.py` (actual implementation). Tools shell out via `subprocess.run(["python3", str(_scripts_dir() / "script.py"), ...])`. This violates ghuntley's colocated principle — tool definition + implementation should live together. Merging eliminates ~2100 lines of subprocess indirection and makes each tool self-contained.

## Design Decisions

1. **citation_tools.py (794 lines) -> new `tools/_citation.py`** — shared internal module (no TOOLS dict). Used by both `tools/checks.py` (5 citation tools) and `tools/download.py` (manifest-add). Underscore prefix matches existing `_paths.py` convention.
2. **Keep `_scripts_dir` importable from each module** — Test 8e asserts `checks_mod._scripts_dir() == pdf_mod._scripts_dir() == download_mod._scripts_dir()`. Keep the import: zero cost.
3. **Lazy imports for PIL/PyMuPDF** — `check_figure.py` does `sys.exit(1)` on missing Pillow at module level. After inlining, move to lazy imports inside handlers.
4. **print->return refactoring** — Script functions use `print()` for output. After inlining, handlers call functions directly and need string returns. Use `io.StringIO` capture or refactor to return strings.
5. **Name collision: `parse_pub_reqs()`** — exists in both check_journal.py and check_figure.py with different implementations. Prefix: `_journal_parse_pub_reqs()` / `_figure_parse_pub_reqs()`.
6. **Delete merged scripts after tests pass** — `scripts/` keeps only: `usage_report.py`, `tool_report.py`, `extract_session_usage.py`, plus shell scripts.

<!-- gate -->

## Phase 1 — Create shared citation module

- [ ] 1. Create `tools/_citation.py` — extract all implementation from `scripts/citation_tools.py` minus CLI `main()` and argparse. Functions: `_score_candidate`, `_classify`, `_get_json`, `query_semantic_scholar`, `query_crossref`, `query_openalex`, `query_ntrs`, `verify_doi`, `lookup_paper`, `_score_entry`, `lint_bib_files`, `_manifest_path`, `manifest_check`, `manifest_add`, `cited_check`, `batch_verify_bib`. Verify import works: `python3 -c "from tools._citation import lookup_paper, verify_doi, manifest_add"` — **coder**

<!-- gate -->

## Phase 2 — Rewrite tools/checks.py

- [ ] 2. Inline `check_language.py` into `tools/checks.py` — all functions from strip_latex_commands through check_file. Remove subprocess call in `_handle_check_language`, call `check_file()` directly with `io.StringIO` capture — **coder**
- [ ] 3. Inline `check_journal.py` into `tools/checks.py` — `_journal_parse_pub_reqs`, `count_words_tex`, `check_bib_fields`, `collect_tex_files`, `collect_bib_files`. Rewrite `_handle_check_journal` to call directly. Note: `strip_latex_commands`/`extract_body` are now local (no `sys.path` hack) — **coder**
- [ ] 4. Inline `check_figure.py` into `tools/checks.py` — `FIGURE_DEFAULTS`, `_figure_parse_pub_reqs`, `check_raster`, `check_pdf`, `collect_figure_files`. PIL/fitz imported lazily inside handlers. Rewrite `_handle_check_figure` — **coder**
- [ ] 5. Rewire 5 citation handlers in `tools/checks.py` — import from `tools._citation`, rewrite `_handle_citation_lint`, `_handle_citation_lookup`, `_handle_citation_verify`, `_handle_citation_verify_all`, `_handle_citation_manifest` to call functions directly (no subprocess). Keep report-reading summary logic in lint handler — **coder**

<!-- gate -->

## Phase 3 — Rewrite tools/pdf.py

- [ ] 6. Inline `pdf_metadata.py` into `tools/pdf.py` — `_FIG_PATTERN`, `_TABLE_PATTERN`, `_HEADING_PATTERNS`, `get_fast_metadata`, `get_section_headings`, `estimate_reading_chunks`. fitz imported lazily. Rewrite `_handle_pdf_metadata` to call `get_fast_metadata()` directly, return `json.dumps(result, indent=2)` — **coder**
- [ ] 7. Inline `extract_figure.py` into `tools/pdf.py` — `parse_page_range`, `list_images`, `extract_images`, `extract_page_as_image`. Rewrite `_handle_extract_figure` with `io.StringIO` capture — **coder**

<!-- gate -->

## Phase 4 — Modify tools/download.py

- [ ] 8. Replace subprocess in `_register_manifest()` with `from tools._citation import manifest_add`. Remove `import subprocess`. Keep all Unpaywall/SciHub logic unchanged — **coder**

<!-- gate -->

## Phase 5 — Verify and clean up

- [ ] 9. Run full test suite: `bash tests/test-workflow-local.sh` — all 72 assertions must pass. Critical: Test 8a-c (`scripts_dir()` resolution), Test 8d (17 tools, all agent registries valid), Test 8e (`_scripts_dir` backward compat) — **coder**
- [ ] 10. Delete merged scripts: `check_language.py`, `check_journal.py`, `check_figure.py`, `citation_tools.py`, `pdf_metadata.py`, `extract_figure.py`. Re-run tests to confirm nothing references deleted files — **coder**
- [ ] 11. Update `tools/README.md` — remove "wrappers around scripts/" language. Update module docstrings in checks.py, pdf.py, download.py — **coder**

## Files Changed

| File | Action |
|------|--------|
| `tools/_citation.py` | CREATE |
| `tools/checks.py` | REWRITE |
| `tools/pdf.py` | REWRITE |
| `tools/download.py` | MODIFY |
| `scripts/check_language.py` | DELETE (phase 5) |
| `scripts/check_journal.py` | DELETE (phase 5) |
| `scripts/check_figure.py` | DELETE (phase 5) |
| `scripts/citation_tools.py` | DELETE (phase 5) |
| `scripts/pdf_metadata.py` | DELETE (phase 5) |
| `scripts/extract_figure.py` | DELETE (phase 5) |
| `tools/README.md` | UPDATE |

**No changes to:** `tools/__init__.py`, `tools/_paths.py`, `tools/core.py`, `tools/search.py`, `tools/claims.py`, `tests/test-workflow-local.sh`
