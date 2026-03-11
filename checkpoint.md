# Checkpoint — ralph-home-separation

**Thread:** ralph-home-separation
**Last updated:** 2026-03-11
**Last agent:** research-coder
**Status:** In progress

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. RALPH_HOME in ralph-loop.sh | done | 7 framework refs prefixed, export RALPH_HOME, defaults to script dir |
| 2. RALPH_HOME in ralph_agent.py | pending | agent prompt + budgets path |
| 3. _scripts_dir() in tools/*.py | pending | 14 occurrences across 3 files |
| 4. RALPH_HOME in archive.sh | pending | template paths |
| 5. init-project.sh | pending | new workspace scaffolding script |
| 6. README.md update | pending | three usage modes + structure tree |
| 7. Backward compat verification | pending | verify ralPhD-repo usage unchanged |
| 8. New-project smoke test | pending | init + verify structure |

## Last Completed

Task 1: Added RALPH_HOME resolution block after mode-parsing in `ralph-loop.sh`. Resolves `RALPH_HOME` defaulting to script directory (backward compatible), validates `ralph_agent.py` exists, exports for child processes, and prefixes 7 framework file references: `PROMPT_FILE` (3 via single prefix after arg loop), `context-budgets.json` (3 occurrences in `compute_budget_info`), `.claude/agents/` (agent file check), `ralph_agent.py` (invocation), `scripts/extract_session_usage.py`. Project files remain CWD-relative. Syntax check and backward-compat path resolution verified.

**Next Task:** Task 2: RALPH_HOME in ralph_agent.py — research-coder
