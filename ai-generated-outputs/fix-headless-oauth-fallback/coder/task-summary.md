# Task Summary — Task 3: Shell helpers in lib/exec.sh

## What was changed

**File:** `lib/exec.sh`

Added three new functions after `is_openai_model()`:

1. **`has_anthropic_api_key()`** — Returns 0 if `ANTHROPIC_API_KEY` is set to a regular API key (`sk-ant-api*`). OAuth tokens (`sk-ant-oat*`) and missing/empty keys return 1. Mirrors the auth detection logic in `providers.py`.

2. **`is_anthropic_model(model)`** — Returns 0 if the model is an Anthropic model. Implemented as the inverse of `is_openai_model()` (any model not matched by `gpt-*|o1*|o3*|o4*`).

3. **`build_claude_system_prompt(agent_name)`** — Outputs the full system prompt for `claude -p` headless mode to stdout:
   - Resolves agent `.md` file (workspace-first: `.claude/agents/{name}.md`, then `${RALPH_HOME}/.claude/agents/{name}.md`)
   - Prepends path preamble when `RALPH_HOME != CWD` (mirrors `ralph_agent.py:build_path_preamble()`)
   - Gets non-essential tools for the agent via inline Python (filters out `_ESSENTIALS`)
   - Appends `templates/tool-via-bash.md` with `{{RALPH_TOOLS}}` replaced by the custom tool list (using awk for multi-line substitution)

## Why

These helpers are the building blocks for the claude -p fallback in tasks 4 and 5. They isolate the auth detection and system prompt construction logic so the pipe mode branch (task 4) and parallel phase branch (task 5) can call them cleanly.

## Test results

- All existing tests: 215/216 (1 pre-existing failure unrelated to this change)
- Manual function tests: all pass
  - has_anthropic_api_key: correctly handles empty, api key, oauth token, unknown patterns
  - is_anthropic_model: correctly handles claude-*, gpt-*, o3*/o1*/o4* patterns
  - build_claude_system_prompt: correct output for coder (gh custom tool), paper-writer (check_language/citation_lint), missing agent (error)
