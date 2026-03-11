# Checkpoint — ralph-home-separation

**Thread:** ralph-home-separation
**Last updated:** 2026-03-11
**Last agent:** research-coder
**Status:** Complete

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|
| 1. RALPH_HOME in ralph-loop.sh | done | 7 framework refs prefixed, export RALPH_HOME, defaults to script dir |
| 2. RALPH_HOME in ralph_agent.py | done | ralph_home var resolves from env, falls back to script dir; used for budgets_path and agent_path |
| 3. _scripts_dir() in tools/*.py | done | Helper added to checks.py, pdf.py, download.py; 14 hardcoded paths replaced |
| 4. RALPH_HOME in archive.sh | done | RALPH_HOME resolves templates; operates on CWD |
| 5. init-project.sh | done | ~85 lines: dirs, symlinks, project files, .ralphrc, launcher, brownfield detection |
| 6. README.md update | done | Three quick-start modes (repo, workspace, brownfield), framework/workspace structure trees, RALPH_HOME + CI section |
| 7. Backward compat verification | done | Syntax check + Python path resolution: all framework files found from repo dir |
| 8. New-project smoke test | done | init-project.sh creates correct dirs, symlinks, files; skip-existing preserves checkpoint.md on re-run |

## Last Completed

All 8 tasks complete. The ralph-home-separation thread is done.

- `scripts/init-project.sh` scaffolds workspaces with dirs, symlinks, project files, `.ralphrc`, and a self-healing `./ralph` launcher
- `README.md` updated with three usage modes, framework/workspace structure trees, `RALPH_HOME` docs, and CI example
- Backward compat verified: running from ralPhD repo unchanged (RALPH_HOME defaults to script dir)
- Smoke test passed: init + re-init with skip-existing both work correctly

**Next Task:** none (thread complete)
