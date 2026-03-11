# Human Review Needed — Phase 1 → Phase 2

## Completed: Phase 1 — GitHub Actions Workflow for ralph-loop

### What was done

**Task 3: `.github/workflows/ralph-run.yml`**
- `workflow_dispatch` trigger with 7 inputs (thread, prompt, autonomy, target_repo, target_ref, max_iterations, loop_mode)
- Dual checkout: ralPhD as `ralph-home/`, target project as `workspace/`
- Sets `RALPH_HOME` for all steps, runs `ralph-loop.sh -p` in pipe mode
- Artifact upload (outputs, checkpoint, logs), job summary
- 60-minute timeout, configurable iteration cap

**Task 4: CI-aware init step**
- Added `--ci` flag to `scripts/init-project.sh` — copies specs/, templates/, .claude/agents/ instead of symlinking
- Workflow injects thread name, date, prompt, autonomy into template files
- Idempotent: re-running on existing workspace preserves custom files

**Task 5: Local tests**
- `tests/test-workflow-local.sh` — 31/31 tests passing
- Covers: CI init, template injection, RALPH_HOME resolution, agent detection, YAML structure, secrets, idempotency

### Files changed
- `.github/workflows/ralph-run.yml` (new)
- `scripts/init-project.sh` (modified — `--ci` flag)
- `tests/test-workflow-local.sh` (new)

### Required secrets (to be configured in GitHub repo settings)
- `ANTHROPIC_API_KEY` — Anthropic API key for agent runner
- `TARGET_REPO_TOKEN` (optional) — PAT for cross-repo checkout

### Required variables (optional)
- `CLAUDE_MODEL` — defaults to `claude-sonnet-4-6` if not set

## Next: Phase 2 — RALPH_HOME Separation Hardening

Phase 2 will audit all code paths for hardcoded path assumptions:
- **Task 6:** `ralph-loop.sh` — ensure all framework paths use `$RALPH_HOME/`
- **Task 7:** Agent prompts — ensure specs/templates resolve from RALPH_HOME, not CWD
- **Task 8:** `ralph_agent.py` + `tools/` — ensure tool scripts resolve from RALPH_HOME

This phase ensures ralPhD works correctly when RALPH_HOME ≠ CWD (i.e., when running as an engine on a separate project repo).

## Action required

Review the workflow and init changes. When ready, delete this file and re-run:
```bash
rm HUMAN_REVIEW_NEEDED.md && ./ralph-loop.sh -p
```
