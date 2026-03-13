# Task Summary — Phase 5: Test all quick-start paths

**Task:** 5. Test all quick-start paths
**Thread:** fix-init-paths
**Date:** 2026-03-13

## Files Changed

| File | Change |
|------|--------|
| `tests/test-workflow-local.sh` | Added Test 17 with 55 new test cases covering QS-A, QS-B, QS-C |

## What Was Done

Added Test 17 block covering all three Quick Start paths:

**17a. Quick Start A** (run from ralPhD repo directly)
- `ralph-loop.sh` exists and is executable
- `.claude/agents/` has >5 agent files
- `templates/` and `specs/` directories exist

**17b. Quick Start B** (`init-project.sh /abs/path` from different cwd)
- Content dirs in WORKSPACE, not scattered into `/tmp`
- `specs/` and `templates/` symlinks resolve
- `.claude/agents/` is symlink → `$RALPH_HOME/.claude/agents`
- `ralphd` is executable and `--help` outputs usage

**17c. Quick Start C** (`init-project.sh /path/.ralph` brownfield/split layout)
- Content dirs at PROJECT_ROOT, not inside `.ralph/`
- All 6 content dir symlinks inside `.ralph/` resolve
- `.ralph/.claude/agents` → `$RALPH_HOME/.claude/agents`
- Framework state (logs, .ralphrc) in `.ralph/`
- `ralphd` executable + `--help` works

## Test Results

215/216 pass (55 new tests, all pass). Same pre-existing failure in tools/__init__.py.
