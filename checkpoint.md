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
| 4. RALPH_HOME in archive.sh | done | RALPH_HOME resolves templates; cd to REPO_ROOT removed; operates on CWD |
| 5. init-project.sh | pending | new workspace scaffolding script |
| 6. README.md update | pending | three usage modes + structure tree |
| 7. Backward compat verification | pending | verify ralPhD-repo usage unchanged |
| 8. New-project smoke test | pending | init + verify structure |

## Last Completed

Task 4: Updated `scripts/archive.sh` to resolve template paths via `$RALPH_HOME`. Added `RALPH_HOME="${RALPH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"` at top. Changed 3 template references (verify check + 2 cp commands) from `templates/...` to `"$RALPH_HOME/templates/..."`. Removed `REPO_ROOT` + `cd "$REPO_ROOT"` — script now operates on CWD (the workspace), while templates come from the framework. Syntax check passed. End-to-end smoke test passed from a separate temp workspace with explicit RALPH_HOME.

**Next Task:** Task 5: init-project.sh — research-coder
