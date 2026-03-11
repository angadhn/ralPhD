# Task 6 Summary — Audit ralph-loop.sh for hardcoded paths

## What was done

Audited every path reference in `ralph-loop.sh` to ensure proper RALPH_HOME separation:
framework files resolve via `$RALPH_HOME`, project files resolve via CWD.

### Complete audit results

**Already correct — RALPH_HOME (framework files):**
- `${RALPH_HOME}/ralph_agent.py` — agent runner
- `${RALPH_HOME}/${PROMPT_FILE}` — prompt templates
- `${RALPH_HOME}/context-budgets.json` — context budget config
- `${RALPH_HOME}/.claude/agents/${CURRENT_AGENT}.md` — agent definitions
- `${RALPH_HOME}/scripts/extract_session_usage.py` — usage extraction

**Already correct — CWD (project files):**
- `checkpoint.md`, `implementation-plan.md`, `inbox.md` — project state
- `iteration_count`, `CHANGELOG.md` — iteration tracking
- `HUMAN_REVIEW_NEEDED.md` — stage gate control
- `AI-generated-outputs/$thread/` — agent output directories
- `logs/usage.jsonl` — usage logging

### Issues found and fixed

1. **JSONL monitor script search path** (lines 389-393): Was searching only
   `$GITHUB_WORKSPACE` and CWD for `.github/scripts/ralph-monitor.sh`. Added
   `$RALPH_HOME` as the first search location since this is a framework file.

2. **Help message** (line 366): Was referencing `./ralphd plan` and
   `bash scripts/archive.sh` which assume CWD = framework root. Changed to
   use `$RALPH_HOME/ralph-loop.sh plan` and `$RALPH_HOME/scripts/archive.sh`.

## Files modified

- `ralph-loop.sh` — 2 targeted fixes (5 lines added, 2 removed)

## Test results

- 31/31 existing tests pass
- `bash -n ralph-loop.sh` syntax check: OK
