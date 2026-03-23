# Task Summary — verify_cited_claims (all 8 tasks)

## Files created
- `tools/verify.py` — new tool: `_handle_verify_cited_claims` with ledger-first + PDF fallback
- `tests/fixtures/verify/` — 5 fixture files (bib, tracker, ledger, 2 PDFs)

## Files modified
- `tools/_citation.py` — added `_build_doi_bib_index()` (DOI→bib bridge)
- `tools/pdf.py` — added `extract_page_texts()` (PDF text extraction with scanned detection)
- `tools/__init__.py` — registered `verify_cited_claims` in TOOLS + AGENT_TOOLS (editor, critic)
- `.claude/agents/editor.md` — added `verify_cited_claims` to pre-edit diagnostics with section_filter derivation
- `.claude/agents/critic.md` — added `verify_cited_claims` as primary mechanical check in style-check mode
- `specs/evidence-format.md` — added optional `support_quote`, `support_page`, `support_section` fields
- `tests/test-runtime-local.sh` — added tests 30a-36c (26 test cases)

## Test results
All tests verified passing via direct Python execution:
- 30a-30c: `_build_doi_bib_index` parsing, case-insensitivity, title extraction
- 31a-31c: `extract_page_texts` page count, text content, pages param
- 32a-32c: ledger-first verdicts (LEDGER_DIRECT, PARTIAL_SUPPORT, fall-through)
- 33a-33h: PDF fallback (PDF_MISSING, scoring, DIRECT_SUPPORT, CONTRADICTED, TEXT_UNAVAILABLE)
- 34a-34c: section_filter prefix matching
- 35a-35f: tool registration, agent prompt integration
- 36a-36c: regression guards (check_claims intact, old format works, spec updated)

## RED/GREEN commit hashes
| Task | RED | GREEN |
|------|-----|-------|
| 2. _build_doi_bib_index | 777a361 | 9818e20 |
| 3. extract_page_texts | 7d57a63 | 7a7506b |
| 4. ledger-first | 1651ad3 | 27d3095 |
| 5. PDF fallback | fa193ef | fefd010 |
| 6. section_filter | passes immediately | 6ba0357 (regression tests) |
| 7. registration | e0798a6 | 5b0cc25 |
| 8. spec update | a5c3f1a | f89db47 |

## Deviations from plan
- Task 6 (section_filter): RED tests passed immediately because section_filter was already implemented in task 4's `_handle_verify_cited_claims`. Added regression tests only.
- Task 8 test 36b: adjusted assertion from `'error' not in r.lower()` to `'Traceback' not in r` because the word "error" legitimately appears in claim text ("error reduction").
