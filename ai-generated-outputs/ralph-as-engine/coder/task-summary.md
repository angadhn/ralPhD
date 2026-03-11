# Task 7 Summary — Audit agent prompts for path assumptions

## What was done

Audited all 12 agent prompts, prompt-build.md, prompt-plan.md, and supporting specs for path references. Identified the two-root path resolution challenge (RALPH_HOME vs CWD) and implemented a runtime solution.

### Key findings

1. **~50+ references to `specs/` files** across agent prompts — these are framework files that live in RALPH_HOME
2. **init-project.sh already handles most cases** by symlinking (local) or copying (CI) specs/ and templates/ to the project CWD
3. **Gap**: `.claude/agents/` is NOT symlinked in local mode, and references in prompt-build.md and prompt-plan.md would break
4. **Gap**: If init-project.sh isn't run, all `specs/` references break when RALPH_HOME ≠ CWD

### Solution implemented

**Runtime path context injection** (zero-change to agent prompts):

- `ralph_agent.py`: Added `build_path_preamble()` that detects when RALPH_HOME ≠ CWD and prepends a "Path Context" section to the system prompt telling the LLM to prefix framework file paths with RALPH_HOME
- Self-hosted mode (RALPH_HOME == CWD): no preamble injected, backward compatible
- Engine mode: preamble injected with explicit RALPH_HOME path and file categorization

**Documentation**:
- `agent-base.md`: Added "Path Resolution" section documenting the two-root model
- `prompt-build.md`: Annotated framework file references
- `prompt-plan.md`: Annotated `.claude/agents/README.md` reference

## Files changed

| File | Change |
|------|--------|
| `ralph_agent.py` | Added `build_path_preamble()` + inject into system prompt |
| `.claude/agents/agent-base.md` | Added "Path Resolution" section |
| `prompt-build.md` | Annotated framework file references |
| `prompt-plan.md` | Annotated `.claude/agents/README.md` reference |
| `tests/test-workflow-local.sh` | Added 3 path preamble tests |

## Test results

34/34 tests pass (31 original + 3 new path preamble tests)
