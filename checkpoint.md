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
| 3. _scripts_dir() in tools/*.py | pending | 14 occurrences across 3 files |
| 4. RALPH_HOME in archive.sh | pending | template paths |
| 5. init-project.sh | pending | new workspace scaffolding script |
| 6. README.md update | pending | three usage modes + structure tree |
| 7. Backward compat verification | pending | verify ralPhD-repo usage unchanged |
| 8. New-project smoke test | pending | init + verify structure |

## Last Completed

Task 2: Added `ralph_home` variable to `main()` in `ralph_agent.py` that resolves `RALPH_HOME` env var with fallback to `Path(__file__).parent` (backward compatible). Used it for `budgets_path` (context-budgets.json) and `agent_path` (.claude/agents/*.md). Syntax check passed, smoke tests confirmed both default and explicit RALPH_HOME paths work. `.env` loading and Python imports unchanged (already use __file__-relative paths).

**Next Task:** Task 3: _scripts_dir() in tools/*.py — research-coder
