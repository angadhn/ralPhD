# Tasks 2-5: Rewrite tools/checks.py (Phase 2)

## What was done

Inlined all script implementations into `tools/checks.py`, eliminating all subprocess calls:

| Task | Script inlined | Functions | Handler change |
|------|---------------|-----------|----------------|
| 2 | check_language.py | 16 functions + 3 constants | io.StringIO capture of check_file() output |
| 3 | check_journal.py | 5 functions + 1 constant | Direct function calls, builds text report |
| 4 | check_figure.py | 4 functions + 1 constant | Lazy PIL/fitz imports, JSON output |
| 5 | citation_tools.py (handlers only) | 0 new (uses tools._citation) | Import from tools._citation, no subprocess |

## Key decisions

- `_journal_parse_pub_reqs` / `_figure_parse_pub_reqs` — prefixed to avoid name collision (design decision #5)
- `check_pdf_figure` (renamed from `check_pdf`) — avoids collision with pdf.py's future functions
- PIL/fitz lazy-imported inside functions, not at module top — avoids sys.exit(1) on missing deps
- Removed `subprocess` import and `_run_cmd` helper entirely after task 5

## Files changed

| File | Lines | Change |
|------|-------|--------|
| `tools/checks.py` | 323 → ~890 | Full rewrite: all handlers inline |

## Test results

72/72 tests pass after each task (verified 4 times).
