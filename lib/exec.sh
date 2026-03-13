#!/usr/bin/env bash

resolve_model() {
  local agent_name="${1:-}"
  local budgets_file="${RALPH_HOME}/context-budgets.json"
  local model=""

  # RALPH_MODEL is a global override — when set, it wins over per-agent config.
  # This lets `RALPH_MODEL=gpt-5.4 ./ralphd -p build` run ALL agents on GPT-5.4.
  if [ -n "${RALPH_MODEL:-}" ]; then
    echo "$RALPH_MODEL"
    return
  fi

  # Otherwise check per-agent model in context-budgets.json
  if [ -n "$agent_name" ] && [ -f "$budgets_file" ] && command -v jq >/dev/null 2>&1; then
    model=$(jq -r --arg a "$agent_name" '.[$a].model // empty' "$budgets_file" 2>/dev/null || true)
  fi
  if [ -z "$model" ]; then
    model="${CLAUDE_MODEL:-claude-opus-4-6}"
  fi
  echo "$model"
}

is_openai_model() {
  local model="${1:-}"
  case "$model" in
    gpt-*|o1*|o3*|o4*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if ANTHROPIC_API_KEY is set to a regular API key (sk-ant-api*).
# OAuth tokens (sk-ant-oat*) and missing keys both return 1.
has_anthropic_api_key() {
  local key="${ANTHROPIC_API_KEY:-}"
  [ -z "$key" ] && return 1
  case "$key" in
    sk-ant-api*) return 0 ;;
    *) return 1 ;;
  esac
}

# Returns 0 if the model is an Anthropic model (anything not matched by is_openai_model).
is_anthropic_model() {
  local model="${1:-}"
  is_openai_model "$model" && return 1
  return 0
}

# Build the full system prompt for claude -p headless mode.
# Outputs to stdout: path preamble (if needed) + agent .md + tool-via-bash appendix.
build_claude_system_prompt() {
  local agent_name="${1:-}"

  # Resolve agent file (workspace-first, same as ralph_agent.py)
  local agent_file=""
  local workspace_path=".claude/agents/${agent_name}.md"
  local framework_path="${RALPH_HOME}/.claude/agents/${agent_name}.md"
  if [ -f "$workspace_path" ]; then
    agent_file="$workspace_path"
  elif [ -f "$framework_path" ]; then
    agent_file="$framework_path"
  else
    echo "Error: agent '${agent_name}' not found in workspace or framework" >&2
    return 1
  fi

  # Build path preamble (mirrors ralph_agent.py:build_path_preamble)
  local cwd rh
  cwd=$(pwd -P)
  rh=$(cd "$RALPH_HOME" && pwd -P)
  if [ "$rh" != "$cwd" ]; then
    cat <<PREAMBLE_EOF
## Path Context

ralPhD is running as an engine on a separate project.
- **RALPH_HOME** (framework): \`${rh}\`
- **Working directory** (project): \`${cwd}\`

File paths in this prompt use short names. Resolve them as follows:
- **Framework files** — prefix with RALPH_HOME:
  \`specs/*\`, \`templates/*\`, \`prompt-*.md\`
  Example: \`specs/writing-style.md\` → \`${rh}/specs/writing-style.md\`
- **Agent files** — workspace-first: \`.claude/agents/{name}.md\` checks
  project dir first, then RALPH_HOME
- **Project files** — use as-is (relative to working directory):
  \`checkpoint.md\`, \`implementation-plan.md\`, \`inbox.md\`,
  \`AI-generated-outputs/*\`, \`sections/*\`, \`figures/*\`, \`corpus/*\`,
  \`references/*\`, \`papers/*\`, \`logs/*\`

PREAMBLE_EOF
  fi

  # Agent .md content
  cat "$agent_file"

  # Tools are exposed via MCP server (tools/mcp_server.py), not via bash template.
  # No tool-via-bash appendix needed.
}

# Generate a temporary MCP config JSON pointing to tools/mcp_server.py for the given agent.
# Outputs the path to the config file.
build_mcp_config() {
  local agent_name="${1:-}"
  local config_file="/tmp/ralph-mcp-${agent_name}.json"

  # mcp requires Python ≥3.10; find the best available interpreter
  local py="python3"
  for candidate in python3.13 python3.12 python3.11 python3.10; do
    if command -v "$candidate" >/dev/null 2>&1; then
      py="$candidate"
      break
    fi
  done

  cat > "$config_file" <<EOF
{
  "mcpServers": {
    "ralph-tools": {
      "command": "${py}",
      "args": ["${RALPH_HOME}/tools/mcp_server.py", "${agent_name}"]
    }
  }
}
EOF
  echo "$config_file"
}

resolve_context_window() {
  local model="${1:-claude-opus-4-6}"
  case "$model" in
    gpt-5.4*) echo 272000 ;;
    gpt-4o|gpt-4o-mini) echo 128000 ;;
    *) echo 200000 ;;
  esac
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

    local agent_path
    agent_path=$(resolve_agent_path "$agent_name")
    if [ -z "$agent_path" ]; then
      echo "  ⚠  Skipping parallel task (agent not found): $agent_name"
      echo "     Checked: .claude/agents/${agent_name}.md, ${RALPH_HOME}/.claude/agents/${agent_name}.md"
      continue
    fi

    local agent_model
    agent_model=$(resolve_model "$agent_name")

    # Auth-detection: Anthropic model but no API key → use claude -p fallback (OAuth/Max plan)
    local use_claude_fallback=false
    if is_anthropic_model "$agent_model" && ! has_anthropic_api_key; then
      use_claude_fallback=true
      echo "  Spawning parallel agent: $agent_name (task $task_idx, model $agent_model, claude -p fallback)"
    else
      echo "  Spawning parallel agent: $agent_name (task $task_idx, model $agent_model)"
    fi

    local task_prompt
    task_prompt=$(cat "$PROMPT_FILE")

    if $use_claude_fallback; then
      local agent_system_prompt mcp_config
      agent_system_prompt=$(build_claude_system_prompt "$agent_name")
      mcp_config=$(build_mcp_config "$agent_name")
      echo "$task_prompt" | claude --model "$agent_model" \
        --tools "" \
        --mcp-config "$mcp_config" \
        --append-system-prompt "$agent_system_prompt" \
        --output-format json \
        --dangerously-skip-permissions > "${output_dir}/output.json" &
    else
      echo "$task_prompt" | python3 "${RALPH_HOME}/ralph_agent.py" \
        --agent "$agent_name" --task - --model "$agent_model" \
        --output-json "${output_dir}/output.json" &
    fi
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
