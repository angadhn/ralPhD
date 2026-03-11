# Task 2: Inline check_language.py into tools/checks.py

## What was done

Inlined all functions from `scripts/check_language.py` into `tools/checks.py`, replacing the subprocess-based `_handle_check_language` with a direct call to `check_file()` using `io.StringIO` to capture stdout/stderr output.

## Functions inlined

- `_is_markdown`, `strip_latex_commands`, `extract_body`, `split_sections`
- `strip_markdown_formatting`, `extract_markdown_body`, `split_markdown_sections`
- `split_paragraphs`, `split_sentences`
- `STOCK_FRAMINGS`, `BALANCED_CLAUSE_PATTERNS` (constants)
- `check_citation_density`, `check_sentence_length_variance`, `check_stock_framings`
- `check_balanced_clauses`, `check_citation_free_generalizations`
- `check_file`

## Key changes

- `_handle_check_language` now captures `check_file()` print output via `io.StringIO` redirect
- Added imports: `io`, `re`, `statistics`, `sys`, `Path` (from pathlib)
- All other handlers (check_journal, check_figure, citation_*) remain subprocess-based (tasks 3-5)
- Updated module docstring to reflect partial inlining state

## Files changed

| File | Lines | Change |
|------|-------|--------|
| `tools/checks.py` | 389 | Inlined check_language functions, rewrote handler |

## Test results

72/72 tests pass (`bash tests/test-workflow-local.sh`)
