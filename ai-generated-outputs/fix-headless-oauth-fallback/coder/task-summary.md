# Task Summary — Tasks 4 & 5: Auth-detection branch in pipe mode and parallel phase

## Task 4: Auth-detection branch in ralph-loop.sh pipe mode

**File:** `ralph-loop.sh` (pipe mode section, ~line 190)

Added auth-detection block before the agent retry loop. Before launching any agent process, the script now:
1. Checks `is_anthropic_model "$CLAUDE_MODEL"` — true for all non-OpenAI models
2. Checks `! has_anthropic_api_key` — true when `ANTHROPIC_API_KEY` is missing or is an OAuth token (`sk-ant-oat*`)
3. If both conditions hold: sets `USE_CLAUDE_FALLBACK=true`, logs a message, and calls `build_claude_system_prompt "$CURRENT_AGENT"` to construct the full system prompt once (before the retry loop, to avoid rebuilding on each retry)

Inside the retry loop, the `ralph_agent.py` invocation is now guarded:
- **Fallback path:** `echo "$PROMPT" | claude --model ... --append-system-prompt ... --output-format json --dangerously-skip-permissions > /tmp/ralph-output.json &`
- **Normal path:** unchanged `python3 ralph_agent.py ...` invocation

## Task 5: Auth-detection fallback in run_parallel_phase()

**File:** `lib/exec.sh` (`run_parallel_phase()`, ~line 160)

Same auth-detection pattern applied per-task inside the parallel spawn loop. For each task:
1. After resolving `agent_model`, checks `is_anthropic_model` and `! has_anthropic_api_key`
2. If fallback: sets local `use_claude_fallback=true`, logs "claude -p fallback" in the spawn message, calls `build_claude_system_prompt "$agent_name"`, runs `claude ... > ${output_dir}/output.json &`
3. Otherwise: runs `ralph_agent.py` as before

This ensures OAuth/Max plan users can also use parallel execution phases without API key errors.

## Why

Max plan / OAuth users have `ANTHROPIC_API_KEY` set to `sk-ant-oat*`, which the API rejects. The `claude` CLI handles OAuth transparently. This fallback routes those users through the CLI instead of `ralph_agent.py` in both serial pipe mode and parallel phase mode.

## Test results

- `bash -n lib/exec.sh`: syntax OK
- `bash tests/test-workflow-local.sh`: 215/216 passed (1 pre-existing failure unrelated to this change)
