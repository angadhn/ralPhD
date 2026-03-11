# Checkpoint — tool-call-prototype

**Thread:** tool-call-prototype
**Last updated:** 2026-03-11
**Last agent:** research-coder (Task 10)
**Status:** Ready for human tasks

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. Write ralph_agent.py | done | ~464 lines, tool-calling loop |
| 2. OAuth auth fix | done | X-Api-Key, not Bearer |
| 3. Standalone test | done | Tested with haiku |
| 4. Update paper-writer.md | done | Commit gates simplified |
| 5. Update critic.md | done | 6 script invocations → tool names |
| 6. Test critic tool use | done | check_language called as tool |
| 7. Wire ralph-loop.sh | done | Line 336 updated |
| 8. Split ralph_agent.py | done | tools/{__init__,core,checks,pdf}.py — 9 tools, 6 agents |
| 9. Complete tool inventory | **done** | 14 tools total: +citation_lookup/verify/manifest, +list_files, +code_search |
| 10. SciHub download tool | **done** | citation_download — Unpaywall + SciHub, gitignored |
| 11. Interview re: Howler agents | pending | human — which agents to port |
| 12. End-to-end test | pending | human — full ralph-loop run |
| 13. Toolsmith agent | future | human — self-extending capability |

## Last Completed

Task 10: citation_download tool.
- `tools/download.py` (new, 1 tool): citation_download — fetches PDFs by DOI
  - Unpaywall (legal, open-access) tried first
  - SciHub fallback only if SCIHUB_MIRROR env var is set (opt-in)
  - Saves to papers/ with Author2024_ShortTitle.pdf naming
  - Auto-registers in manifest via citation_tools.py manifest-add
- `tools/__init__.py`: registered download module, added citation_download to scout
- `.gitignore`: tools/download.py excluded per legal grey area
- 15 tools total, scout has 10 tools, all schemas verified

**Next Task:** Task 11: Interview re: Howler agents — human
