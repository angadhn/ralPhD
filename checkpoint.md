# Checkpoint — ralph-home-separation

**Thread:** ralph-home-separation
**Last updated:** 2026-03-11
**Last agent:** research-coder
**Status:** In progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. RALPH_HOME in ralph-loop.sh | done | 7 framework refs prefixed, export RALPH_HOME, defaults to script dir |
| 2. RALPH_HOME in ralph_agent.py | done | ralph_home var resolves from env, falls back to script dir; used for budgets_path and agent_path |
| 3. _scripts_dir() in tools/*.py | done | Helper added to checks.py, pdf.py, download.py; 14 hardcoded paths replaced |
| 4. RALPH_HOME in archive.sh | pending | template paths |
| 5. init-project.sh | pending | new workspace scaffolding script |
| 6. README.md update | pending | three usage modes + structure tree |
| 7. Backward compat verification | pending | verify ralPhD-repo usage unchanged |
| 8. New-project smoke test | pending | init + verify structure |

## Last Completed

Task 3: Added `_scripts_dir()` helper function to `tools/checks.py`, `tools/pdf.py`, and `tools/download.py`. Each resolves `RALPH_HOME/scripts` from env var, falling back to `Path(__file__).resolve().parent.parent / "scripts"` (backward compatible). Replaced all 14 hardcoded `"scripts/..."` subprocess paths: 9 in checks.py (check_language, check_journal, check_figure, citation_tools x6), 4 in pdf.py (pdf_metadata, extract_figure x3), 1 in download.py (citation_tools manifest-add). Syntax check and smoke tests passed for both default and explicit RALPH_HOME paths.

**Next Task:** Task 4: RALPH_HOME in archive.sh — research-coder
