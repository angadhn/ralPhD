# Checkpoint — tool-call-prototype

**Thread:** tool-call-prototype
**Last updated:** 2026-03-11
**Last agent:** research-coder (Task 9)
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
| 10. Interview re: Howler agents | **next** | human — which agents to port |
| 11. End-to-end test | pending | human — full ralph-loop run |
| 12. Toolsmith agent | future | human — self-extending capability |

## Last Completed

Task 9: Complete tool inventory.
- `tools/checks.py` (+3 tools): citation_lookup (single+batch), citation_verify, citation_manifest (check+add)
- `tools/search.py` (new, 2 tools): list_files (glob), code_search (ripgrep)
- `tools/__init__.py`: _ESSENTIALS pattern, all agents get 5 core tools
- Scout gets citation_lookup, citation_verify, citation_manifest
- Figure-stylist workflow now references check_figure (step 4)
- 14 tools total, 6 agents, all schemas verified

**Next Task:** Task 10: Interview re: Howler agents — human
