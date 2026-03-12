#!/usr/bin/env bash

resolve_model() {
  local agent_name="${1:-}"
  local budgets_file="${RALPH_HOME}/context-budgets.json"
  local model=""

  if [ -n "$agent_name" ] && [ -f "$budgets_file" ] && command -v jq >/dev/null 2>&1; then
    model=$(jq -r --arg a "$agent_name" '.[$a].model // empty' "$budgets_file" 2>/dev/null || true)
  fi
  if [ -z "$model" ]; then
    model="${CLAUDE_MODEL:-claude-opus-4-6}"
  fi
  echo "$model"
}

run_parallel_phase() {
  local phase_line=$1
  local pids=()
  local agents=()
  local task_idx=0

  echo "  ⚡ Parallel phase detected: $phase_line"

  while IFS='|' read -r agent_name task_desc; do
    task_idx=$((task_idx + 1))
    local output_dir="/tmp/ralph-parallel-${ITERATION}-${task_idx}"
    mkdir -p "$output_dir"

    if [ ! -f "${RALPH_HOME}/.claude/agents/${agent_name}.md" ]; then
      echo "  ⚠  Skipping parallel task (agent not found): $agent_name"
      continue
    fi

    local agent_model
    agent_model=$(resolve_model "$agent_name")
    echo "  Spawning parallel agent: $agent_name (task $task_idx, model $agent_model)"

    local task_prompt
    task_prompt=$(cat "$PROMPT_FILE")

    echo "$task_prompt" | python3 "${RALPH_HOME}/ralph_agent.py" \
      --agent "$agent_name" --task - --model "$agent_model" \
      --output-json "${output_dir}/output.json" &
    pids+=($!)
    agents+=("$agent_name")
  done < <(collect_phase_tasks "implementation-plan.md" "$phase_line")

  if [ ${#pids[@]} -eq 0 ]; then
    echo "  No parallel tasks to run."
    return 1
  fi

  echo "  Waiting for ${#pids[@]} parallel agents..."
  local failed=0
  for i in "${!pids[@]}"; do
    if wait "${pids[$i]}" 2>/dev/null; then
      echo "  ✓ ${agents[$i]} completed"
    else
      echo "  ✗ ${agents[$i]} failed (exit $?)"
      failed=$((failed + 1))
    fi
  done

  echo "  Parallel phase complete: $((${#pids[@]} - failed))/${#pids[@]} succeeded"

  for i in "${!agents[@]}"; do
    local idx=$((i + 1))
    local output_file="/tmp/ralph-parallel-${ITERATION}-${idx}/output.json"
    if [ -f "$output_file" ]; then
      log_usage_from_output_json "$output_file" "$ITERATION" "${agents[$i]}" "$LOOP_MODE" "$CURRENT_THREAD" "$idx"
    fi
  done

  return 0
}
