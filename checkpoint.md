# Checkpoint — verify-cited-claims

**Thread:** verify-cited-claims
**Last updated:** 2026-03-23
**Last agent:** coder
**Status:** ready to build

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Fixtures | done | commit da1dda7 |
| 2. _build_doi_bib_index | done | RED 777a361, GREEN 9818e20 |
| 3. extract_page_texts | pending | depends: 1 |
| 4. verify_cited_claims ledger-first | pending | depends: 2,3 |
| 5. PDF fallback verdicts | pending | depends: 4 |
| 6. section_filter | pending | depends: 5 |
| 7. Tool registration + agent prompts | pending | depends: 6 |
| 8. Regression guard + spec update | pending | |

## Last Reflection

<none yet>

## Next Task

Task 3: `extract_page_texts` — red/green TDD — **coder**
