# Task Summary — Tasks 4, 5 & 6

---

## Task 6 — Validate usage JSON parsing in lib/post-run.sh

**Task:** Check if `claude -p --output-format json` output is compatible with
`print_output_json_summary` and `log_usage_from_output_json`. Adapt if needed.

### Findings

Ran a live sample: `echo "Say hello" | claude --model claude-haiku-4-5-20251001 --output-format json --dangerously-skip-permissions`

Actual `claude -p --output-format json` output shape (relevant fields):
```json
{
  "is_error": false,
  "num_turns": 1,
  "duration_ms": 1429,
  "result": "hello",
  "total_cost_usd": 0.031,
  "usage": {
    "input_tokens": 9,
    "cache_creation_input_tokens": 23512,
    "cache_read_input_tokens": 14066,
    "output_tokens": 35
  },
  "modelUsage": {
    "claude-haiku-4-5-20251001": {
      "inputTokens": 9,
      "outputTokens": 35,
      "cacheReadInputTokens": 14066,
      "cacheCreationInputTokens": 23512
    }
  }
}
```

### Compatibility verdict: FULLY COMPATIBLE — no changes needed

| Field used by post-run.sh | Present in claude -p JSON | Notes |
|---|---|---|
| `.is_error` | ✓ | `false` on success |
| `.result` | ✓ | Final text (truncated by Claude CLI) |
| `.num_turns` | ✓ | |
| `.duration_ms` | ✓ | |
| `.total_cost_usd` | ✓ | |
| `.modelUsage` | ✓ | Per-model breakdown (camelCase) |
| `.usage.input_tokens` | ✓ | snake_case totals |
| `.usage.cache_read_input_tokens` | ✓ | |
| `.usage.cache_creation_input_tokens` | ✓ | |
| `.usage.output_tokens` | ✓ | |
| `.tools_called` | absent → handled | `(.tools_called // [])` returns `[]` safely |

The `claude -p --output-format json` format contains both `.usage` (snake_case aggregates)
AND `.modelUsage` (camelCase per-model breakdown) — the same dual structure that
`ralph_agent.py` produces. Extra fields in `.usage` (`server_tool_use`, `service_tier`,
etc.) are ignored by jq.

### Files changed
None — validation confirmed no code changes required.

### Test results
Live `claude -p` run confirmed output schema matches expectations.

---

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
