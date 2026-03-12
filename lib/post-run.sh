#!/usr/bin/env bash

cb_reset() {
  CB_CONSECUTIVE_FAILURES=0
  rm -f "$CB_FILE"
}

cb_record_failure() {
  CB_CONSECUTIVE_FAILURES=$((CB_CONSECUTIVE_FAILURES + 1))
  echo "$CB_CONSECUTIVE_FAILURES" > "$CB_FILE"
}

cb_record_success() {
  if [ "$CB_CONSECUTIVE_FAILURES" -gt 0 ]; then
    echo "  Circuit breaker: reset after $CB_CONSECUTIVE_FAILURES failure(s)"
  fi
  cb_reset
}

cb_is_open() {
  [ "$CB_CONSECUTIVE_FAILURES" -ge "$CB_THRESHOLD" ]
}

restore_circuit_breaker_state() {
  if [ -f "$CB_FILE" ]; then
    CB_CONSECUTIVE_FAILURES=$(cat "$CB_FILE" 2>/dev/null | tr -d '[:space:]')
    if ! [[ "$CB_CONSECUTIVE_FAILURES" =~ ^[0-9]+$ ]]; then
      CB_CONSECUTIVE_FAILURES=0
    fi
  fi
}

cleanup_loop_processes() {
  [ -n "${JSONL_MONITOR_PID:-}" ] && kill "$JSONL_MONITOR_PID" 2>/dev/null || true
  [ -n "${MONITOR_PID:-}" ] && kill "$MONITOR_PID" 2>/dev/null || true
  [ -n "${CLAUDE_PID:-}" ] && kill "$CLAUDE_PID" 2>/dev/null || true
  rm -f "$YIELD_FILE" "$CTX_FILE" "$BUDGET_FILE" "$CB_FILE"
}

handle_interrupt_signal() {
  local now
  now=$(date +%s)
  if (( now - LAST_CTRL_C < 3 )); then
    echo ""
    echo "Stopped."
    cleanup_loop_processes
    exit 0
  fi

  LAST_CTRL_C=$now
  echo ""
  echo "Press Ctrl+C again within 3s to stop."
}

print_output_json_summary() {
  local output_file=$1
  echo "  --- Post-run usage summary ---"
  jq -r '
    if .is_error then "  Result: ERROR — \(.result)"
    else
      "  Result: success (\(.num_turns) turns, \(.duration_ms/1000 | floor)s)" +
      (.modelUsage // {} | to_entries[] |
        "\n  Model: \(.key)" +
        "\n    input: \(.value.inputTokens // 0) | cache_create: \(.value.cacheCreationInputTokens // 0) | cache_read: \(.value.cacheReadInputTokens // 0) | output: \(.value.outputTokens // 0)") +
      (if .total_cost_usd then "\n  Cost: $\(.total_cost_usd)" else "" end)
    end
  ' "$output_file" 2>/dev/null || echo "  (could not parse output JSON)"
}

log_usage_from_output_json() {
  local output_file=$1
  local iteration=$2
  local agent_name=$3
  local loop_mode=$4
  local thread=$5
  local parallel_sub=${6:-}
  local timestamp

  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$USAGE_LOG")"

  jq -c \
    --arg iter "$iteration" \
    --arg agent "$agent_name" \
    --arg mode "$loop_mode" \
    --arg ts "$timestamp" \
    --arg thread "$thread" \
    --arg sub "$parallel_sub" '
    if .is_error then
      {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode,
       error: true, message: .result}
      + (if $sub != "" then {parallel_sub: ($sub|tonumber)} else {} end)
    else
      {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode,
       model: (.modelUsage // {} | keys[0] // "unknown"),
       num_turns: .num_turns, duration_ms: .duration_ms,
       input_tokens: .usage.input_tokens,
       cache_read_input_tokens: .usage.cache_read_input_tokens,
       cache_creation_input_tokens: .usage.cache_creation_input_tokens,
       output_tokens: .usage.output_tokens,
       cost_usd: .total_cost_usd}
      + (if (.tools_called // []) | length > 0 then {tools_called: (.tools_called // [])} else {} end)
      + (if $sub != "" then {parallel_sub: ($sub|tonumber)} else {} end)
    end
  ' "$output_file" >> "$USAGE_LOG" 2>/dev/null
}

log_interactive_session_usage() {
  local session_file=$1
  local iteration=$2
  local agent_name=$3
  local loop_mode=$4
  local thread=$5
  local timestamp

  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mkdir -p "$(dirname "$USAGE_LOG")"

  python3 "${RALPH_HOME}/scripts/extract_session_usage.py" "$session_file" \
    | jq -c \
      --arg iter "$iteration" \
      --arg agent "$agent_name" \
      --arg mode "$loop_mode" \
      --arg ts "$timestamp" \
      --arg thread "$thread" \
      '. + {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode}' \
    >> "$USAGE_LOG" 2>/dev/null
}

capture_eval_metrics() {
  python3 "${RALPH_HOME}/scripts/evaluate_iteration.py" \
    --iteration "$ITERATION" \
    --arch-mode "${ARCH_MODE:-serial}" \
    --run-tag "${RUN_TAG:-}" \
    2>/dev/null
}

handle_human_review_gate() {
  local template_file="${RALPH_HOME}/templates/HUMAN_REVIEW_NEEDED.md"
  if [ -f "HUMAN_REVIEW_NEEDED.md" ] && ! diff -q "HUMAN_REVIEW_NEEDED.md" "$template_file" >/dev/null 2>&1; then
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  HUMAN REVIEW REQUESTED                     ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""
    cat HUMAN_REVIEW_NEEDED.md
    echo ""
    echo "To continue: review above, edit checkpoint.md if needed, then:"
    echo "  rm HUMAN_REVIEW_NEEDED.md && ./ralph-loop.sh -p"
    return 0
  fi
  return 1
}

restore_truncated_files() {
  local truncated
  truncated=$(git diff --numstat 2>/dev/null | awk '$1 == 0 && $2 > 0 {print $3}')
  if [ -n "$truncated" ]; then
    echo "  ⚠  TRUNCATED FILES DETECTED:"
    echo "$truncated" | sed 's/^/    /'
    echo "  Restoring from HEAD..."
    echo "$truncated" | xargs git checkout HEAD --
  fi
}

append_changelog_entry() {
  if [ -f "CHANGELOG.md" ] || [ "$ITERATION" -eq 1 ]; then
    local last_msg
    last_msg=$(git log -1 --format='%s' 2>/dev/null || echo "no commit")
    printf "\n## Iteration %d — %s\n- %s\n" "$ITERATION" "$(date +%Y-%m-%d)" "$last_msg" >> CHANGELOG.md
  fi
}
