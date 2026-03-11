# Checkpoint — tool-call-prototype

**Thread:** tool-call-prototype
**Last updated:** 2026-03-11
**Last agent:** research-coder (Task 8)
**Status:** Ready for automated tasks

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
| 8. Split ralph_agent.py | **done** | tools/{__init__,core,checks,pdf}.py — 9 tools, 6 agents |
| 9. Complete tool inventory | **next** | citation_tools, list_files, code_search |
| 10. Interview re: Howler agents | pending | human — which agents to port |
| 11. End-to-end test | pending | human — full ralph-loop run |
| 12. Toolsmith agent | future | human — self-extending capability |

## Last Completed

Task 8: Split ralph_agent.py into loop + tools/ directory.
- `ralph_agent.py` (464→201 lines): loop, auth, CLI only
- `tools/__init__.py` (51 lines): merged TOOLS registry, AGENT_TOOLS, execute_tool(), get_tools_for_agent()
- `tools/core.py` (77 lines): read_file, write_file, bash
- `tools/checks.py` (113 lines): check_language, check_journal, check_figure, citation_lint
- `tools/pdf.py` (75 lines): pdf_metadata, extract_figure
- All 9 tools register, 6 agent mappings preserved, schemas verified clean

## Next Task

Task 9: Complete tool inventory — research-coder
