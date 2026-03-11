#!/usr/bin/env bash
set -euo pipefail

# --- Mode ---
PIPE_MODE=false
LOOP_MODE="build"
PROMPT_FILE="prompt-build.md"
ARCH_MODE=""
RUN_TAG=""

for arg in "$@"; do
  case "$arg" in
    -p) PIPE_MODE=true ;;
    plan) LOOP_MODE="plan"; PROMPT_FILE="prompt-plan.md" ;;
    build) LOOP_MODE="build"; PROMPT_FILE="prompt-build.md" ;;
    --serial) ARCH_MODE="serial" ;;
    --parallel) ARCH_MODE="parallel" ;;
    --single) ARCH_MODE="single" ;;
    --run-tag=*) RUN_TAG="${arg#--run-tag=}" ;;
    [0-9]*) MAX_ITERATIONS="$arg" ;;
  esac
done

# --- Architecture mode resolution ---
# CLI flags override plan field; plan field overrides default.
if [ -z "$ARCH_MODE" ]; then
  ARCH_MODE=$(grep -i '^\*\*Architecture:\*\*\|^Architecture:' implementation-plan.md 2>/dev/null | head -1 | sed 's/.*: *//' | sed 's/\*//g' | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]' || true)
fi
if [ -z "$ARCH_MODE" ] || ! echo "$ARCH_MODE" | grep -qE '^(serial|parallel|single|auto)$'; then
  ARCH_MODE="serial"
fi
export ARCH_MODE

# --- RALPH_HOME resolution ---
# RALPH_HOME points to the ralPhD framework directory.
# Default: the directory containing this script (backward compatible).
if [ -z "${RALPH_HOME:-}" ]; then
  RALPH_HOME="$(cd "$(dirname "$0")" && pwd)"
fi
if [ ! -f "${RALPH_HOME}/ralph_agent.py" ]; then
  echo "Error: RALPH_HOME (${RALPH_HOME}) does not contain ralph_agent.py"
  exit 1
fi
export RALPH_HOME
PROMPT_FILE="${RALPH_HOME}/${PROMPT_FILE}"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: $PROMPT_FILE not found"
  exit 1
fi

# --- Config ---
CONTEXT_THRESHOLD=55
CTX_FILE="/tmp/ralph-context-pct"
YIELD_FILE="/tmp/ralph-yield"
BUDGET_FILE="/tmp/ralph-budget-info"
POLL_INTERVAL=5
STATUSLINE_LOG="/tmp/ralph-statusline-log"
BACKOFF=60
USAGE_LOG="logs/usage.jsonl"
AGENT_MAX_RETRIES=3          # bash-level retries per agent invocation
AGENT_RETRY_DELAYS=(5 15 45) # seconds between retries

# --- Circuit breaker ---
# Halts the loop after too many consecutive failures to avoid burning tokens.
CB_FILE="/tmp/ralph-circuit-breaker"
CB_THRESHOLD=5   # consecutive failures before opening circuit
CB_CONSECUTIVE_FAILURES=0

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

# Restore circuit breaker state from previous run
if [ -f "$CB_FILE" ]; then
  CB_CONSECUTIVE_FAILURES=$(cat "$CB_FILE" 2>/dev/null | tr -d '[:space:]')
  if ! [[ "$CB_CONSECUTIVE_FAILURES" =~ ^[0-9]+$ ]]; then
    CB_CONSECUTIVE_FAILURES=0
  fi
fi

# --- Persistent iteration counter ---
COUNTER_FILE="iteration_count"
if [ -f "$COUNTER_FILE" ]; then
  ITERATION=$(cat "$COUNTER_FILE")
  if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
    echo "Warning: invalid iteration_count ('$ITERATION'), resetting to 0" >&2
    ITERATION=0
  fi
else
  ITERATION=0
fi

# --- State ---
CLAUDE_PID=""
MONITOR_PID=""
JSONL_MONITOR_PID=""
LAST_CTRL_C=0

cleanup() {
  [ -n "$JSONL_MONITOR_PID" ] && kill "$JSONL_MONITOR_PID" 2>/dev/null || true
  [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null || true
  [ -n "$CLAUDE_PID" ] && kill "$CLAUDE_PID" 2>/dev/null || true
  rm -f "$YIELD_FILE" "$CTX_FILE" "$BUDGET_FILE" "$CB_FILE"
}

handle_interrupt() {
  local now
  now=$(date +%s)
  if (( now - LAST_CTRL_C < 3 )); then
    echo ""
    echo "Stopped."
    cleanup
    exit 0
  else
    LAST_CTRL_C=$now
    echo ""
    echo "Press Ctrl+C again within 3s to stop."
  fi
}

trap 'handle_interrupt' INT

HEARTBEAT_INTERVAL=90  # seconds between heartbeat prints

detect_agent() {
  local next_task
  # Try inline format first: "**Next Task:** value" or "Next Task: value"
  next_task=$(grep -i '^\*\*Next Task\*\*:\|^Next Task:' checkpoint.md 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g')
  # If not found, try heading format: "## Next Task" with value on the next non-empty line
  if [ -z "$next_task" ]; then
    next_task=$(awk '/^## Next Task/{found=1; next} found && /[^ ]/{print; exit}' checkpoint.md 2>/dev/null)
  fi

  # Strip parentheticals, markdown formatting, and trim whitespace
  next_task=$(echo "$next_task" | sed 's/([^)]*)//g; s/\*//g; s/^ *//; s/ *$//')

  # No task: "none", template placeholder, or empty — fall back to implementation-plan.md
  case "$next_task" in
    none*|None*|"<"*|"")
      # Try first unchecked task from implementation-plan.md (skip template placeholders)
      next_task=$(grep '^\- \[ \]' implementation-plan.md 2>/dev/null \
        | grep -v '<task description>\|<agent>' \
        | head -1 | sed 's/^- \[ \] [0-9]*\. *//' | sed 's/\*//g')
      next_task=$(echo "$next_task" | sed 's/^ *//; s/ *$//')
      if [ -z "$next_task" ]; then
        echo ""; return
      fi
      ;;
  esac

  # Agent name is the last word (strip any trailing punctuation)
  local agent="${next_task##* }"
  agent=$(echo "$agent" | sed 's/[^a-zA-Z0-9_-]//g')
  # Empty after cleanup means template placeholder — treat as no task
  if [ -z "$agent" ]; then
    echo ""; return
  fi
  echo "$agent"
}

resolve_model() {
  # Resolve model for a given agent: context-budgets.json > CLAUDE_MODEL env > default.
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

estimate_input_cost() {
  # Estimate context % that reading input files will consume for a given agent.
  # Returns integer percentage via stdout.
  #
  # Constants (calibrate after first e2e run using logs/usage.jsonl):
  #   BYTES_PER_TOKEN: ~3.5 for English markdown/LaTeX, ~4.0 for mixed code.
  #     Using 3.5 (conservative — overestimates tokens, triggers yield earlier).
  #   CONTEXT_WINDOW: 200k tokens total.
  #   BASELINE_OVERHEAD: system prompt + tool schemas consume tokens before any
  #     user content. Measured 2026-03-11:
  #       scout: ~2730 tokens (9.6k bytes), paper-writer: ~2740 (9.6k),
  #       critic: ~2885 (10.1k), deep-reader: ~2490 (8.7k),
  #       research-coder: ~2250 (7.9k), figure-stylist: ~1690 (5.9k)
  #     Using 3000 as safe upper bound for all agents.
  local agent_name=$1
  local thread=""
  local total_bytes=0

  local BYTES_PER_TOKEN=35    # x10 to avoid floating point (3.5 * 10)
  local CONTEXT_WINDOW=200000
  local BASELINE_OVERHEAD=3000  # tokens consumed by system prompt + tool schemas

  # Effective window = total window minus baseline overhead
  local EFFECTIVE_WINDOW=$(( CONTEXT_WINDOW - BASELINE_OVERHEAD ))

  # Resolve thread from checkpoint.md
  thread=$(grep '^\*\*Thread:\*\*\|^Thread:' checkpoint.md 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g' | tr -d '[:space:]')

  if [ -z "$thread" ] || [ "$thread" = "<thread-name>" ]; then
    echo 0
    return
  fi

  local base="AI-generated-outputs/$thread"

  # Per-agent input files that can grow large
  case "$agent_name" in
    deep-reader)
      for f in "$base/deep-analysis/notes.md" \
               "$base/scout-corpus/scored_papers.md"; do
        [ -f "$f" ] && total_bytes=$(( total_bytes + $(wc -c < "$f") ))
      done
      ;;
    paper-writer)
      for f in "$base/deep-analysis/notes.md" \
               "$base/deep-analysis/report.tex" \
               "$base/deep-analysis/section_map.md" \
               "$base/writing/outline.md"; do
        [ -f "$f" ] && total_bytes=$(( total_bytes + $(wc -c < "$f") ))
      done
      ;;
    research-coder)
      for f in "$base/deep-analysis/notes.md" \
               "$base/critic-review/figure_proposals.md"; do
        [ -f "$f" ] && total_bytes=$(( total_bytes + $(wc -c < "$f") ))
      done
      ;;
    critic)
      for f in "$base/deep-analysis/report.tex" \
               "$base/deep-analysis/notes.md"; do
        [ -f "$f" ] && total_bytes=$(( total_bytes + $(wc -c < "$f") ))
      done
      ;;
    *)
      # scout, figure-stylist, unknown — minimal file inputs
      echo 0
      return
      ;;
  esac

  # tokens = bytes * 10 / BYTES_PER_TOKEN (x10 to avoid floating point)
  # pct = tokens * 100 / EFFECTIVE_WINDOW
  local input_tokens=$(( total_bytes * 10 / BYTES_PER_TOKEN ))
  local input_pct=$(( input_tokens * 100 / EFFECTIVE_WINDOW ))
  echo "$input_pct"
}

compute_budget_info() {
  local agent_name=$1
  local pct=${2:-0}
  local headroom=$(( CONTEXT_THRESHOLD - pct ))
  local max_step=0
  local recommendation="PROCEED"
  local input_cost=0

  # Look up max_step from context-budgets.json
  if [ -f "${RALPH_HOME}/context-budgets.json" ] && command -v jq &>/dev/null; then
    max_step=$(jq -r --arg a "$agent_name" '.[$a].max_step // 0' "${RALPH_HOME}/context-budgets.json" 2>/dev/null || echo 0)
  fi

  # Estimate input file cost and adjust max_step if inputs are larger than expected
  input_cost=$(estimate_input_cost "$agent_name")
  if [ "$input_cost" -gt 0 ]; then
    local static_read_cost
    static_read_cost=$(jq -r --arg a "$agent_name" '.[$a].steps.read_inputs // .[$a].steps.read_chunk // 0' "${RALPH_HOME}/context-budgets.json" 2>/dev/null || echo 0)
    # If actual input cost exceeds the static estimate, inflate max_step by the difference
    if [ "$input_cost" -gt "$static_read_cost" ]; then
      max_step=$(( max_step + input_cost - static_read_cost ))
    fi
  fi

  # Recommendation logic
  if [ "$max_step" -gt 0 ]; then
    local caution_threshold=$(( max_step * 3 / 2 ))  # max_step * 1.5 (integer math)
    if [ "$headroom" -le "$max_step" ]; then
      recommendation="YIELD"
      # Also trigger the yield file as safety net
      if [ ! -f "$YIELD_FILE" ]; then
        touch "$YIELD_FILE"
      fi
    elif [ "$headroom" -le "$caution_threshold" ]; then
      recommendation="CAUTION"
    else
      recommendation="PROCEED"
    fi
  fi

  # Write budget info file
  cat > "$BUDGET_FILE" <<BUDGETEOF
agent=$agent_name
context_pct=$pct
threshold=$CONTEXT_THRESHOLD
headroom=$headroom
max_step_cost=$max_step
input_file_cost=$input_cost
recommendation=$recommendation
BUDGETEOF
}

monitor_context() {
  local pid=$1
  local iter_start=$2
  local ignore_until=$3
  local agent_name=${4:-unknown}
  local last_heartbeat=$iter_start
  local ticks=0
  while kill -0 "$pid" 2>/dev/null; do
    local now
    now=$(date +%s)
    if [ -f "$CTX_FILE" ] && [ "$now" -ge "$ignore_until" ]; then
      # Only trust the file if it was written AFTER this iteration started
      if [[ "$OSTYPE" == "darwin"* ]]; then
        file_time=$(stat -f %m "$CTX_FILE" 2>/dev/null || echo 0)
      else
        file_time=$(stat -c %Y "$CTX_FILE" 2>/dev/null || echo 0)
      fi
      if [ "$file_time" -ge "$iter_start" ]; then
        pct=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')

        # Update budget info on every tick
        if [ -n "$pct" ] 2>/dev/null; then
          compute_budget_info "$agent_name" "$pct"
        fi

        if [ -n "$pct" ] && [ "$pct" -ge "$CONTEXT_THRESHOLD" ] 2>/dev/null; then
          if [ ! -f "$YIELD_FILE" ]; then
            echo ""
            echo "⚠  Context at ${pct}% (threshold: ${CONTEXT_THRESHOLD}%) — yield signal sent"
            echo "   Claude will finish current subtask, then hand off."
            touch "$YIELD_FILE"
          fi
        fi
        # Heartbeat: periodic status line
        if (( now - last_heartbeat >= HEARTBEAT_INTERVAL )); then
          local elapsed=$(( now - iter_start ))
          local mins=$(( elapsed / 60 ))
          local secs=$(( elapsed % 60 ))
          local changed
          changed=$(git diff --stat --no-color 2>/dev/null | tail -1 | sed 's/^ *//' || echo "")
          local rec=""
          if [ -f "$BUDGET_FILE" ]; then
            rec=$(grep '^recommendation=' "$BUDGET_FILE" 2>/dev/null | cut -d= -f2)
          fi
          printf "  [%dm%02ds] context: %s%%" "$mins" "$secs" "$pct"
          if [ -n "$rec" ]; then
            printf " [%s]" "$rec"
          fi
          if [ -n "$changed" ]; then
            printf " | %s" "$changed"
          fi
          printf "\n"
          last_heartbeat=$now
        fi
      fi
    fi
    sleep "$POLL_INTERVAL"
  done
}

echo "=== Ralph Loop ==="
echo "Loop mode: $LOOP_MODE"
echo "Prompt: $PROMPT_FILE"
if $PIPE_MODE; then
  echo "IO mode: non-interactive (-p)"
else
  echo "IO mode: interactive"
fi
echo "Architecture mode: $ARCH_MODE"
echo "Context yield threshold: ${CONTEXT_THRESHOLD}%"
[ -n "${MAX_ITERATIONS:-}" ] && echo "Max iterations: $MAX_ITERATIONS"
echo "Double Ctrl+C to stop"
echo ""

# --- Parallel execution helpers ---
detect_current_phase() {
  # Find which phase the first unchecked task belongs to.
  # Returns the phase heading line (e.g., "## Phase 2 — Build (parallel)")
  local in_phase=""
  while IFS= read -r line; do
    if echo "$line" | grep -q '^## Phase'; then
      in_phase="$line"
    fi
    if echo "$line" | grep -q '^\- \[ \]'; then
      echo "$in_phase"
      return
    fi
  done < implementation-plan.md
  echo ""
}

is_parallel_phase() {
  # Check if a phase heading contains "(parallel)" annotation
  local phase_line="$1"
  echo "$phase_line" | grep -qi '(parallel)' && return 0 || return 1
}

collect_phase_tasks() {
  # Collect all unchecked tasks in the current phase.
  # Outputs one line per task: "agent_name|task_description"
  local target_phase="$1"
  local in_target=false
  while IFS= read -r line; do
    if echo "$line" | grep -q '^## Phase'; then
      if [ "$line" = "$target_phase" ]; then
        in_target=true
      elif $in_target; then
        # Reached next phase — stop
        break
      fi
    fi
    if $in_target && echo "$line" | grep -q '^\- \[ \]'; then
      # Extract agent name (last word) and task description
      local task_desc
      task_desc=$(echo "$line" | sed 's/^- \[ \] [0-9]*\. *//' | sed 's/\*//g')
      local agent_name="${task_desc##* }"
      agent_name=$(echo "$agent_name" | sed 's/[^a-zA-Z0-9_-]//g')
      echo "${agent_name}|${task_desc}"
    fi
  done < implementation-plan.md
}

run_parallel_phase() {
  # Spawn one ralph_agent.py per task concurrently, wait for all.
  local phase_line="$1"
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

    echo "$task_prompt" | python3 "${RALPH_HOME}/ralph_agent.py"       --agent "$agent_name" --task - --model "$agent_model"       --output-json "${output_dir}/output.json" &
    pids+=($!)
    agents+=("$agent_name")
  done < <(collect_phase_tasks "$phase_line")

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

  # Log usage for each parallel agent
  for i in "${!agents[@]}"; do
    local idx=$((i + 1))
    local output_file="/tmp/ralph-parallel-${ITERATION}-${idx}/output.json"
    if [ -f "$output_file" ]; then
      mkdir -p "$(dirname "$USAGE_LOG")"
      jq -c --arg iter "$ITERATION" --arg agent "${agents[$i]}" --arg mode "$LOOP_MODE" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg thread "$CURRENT_THREAD" \
        --arg sub "$idx" '
        if .is_error then
          {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread,
           agent: $agent, loop_mode: $mode, parallel_sub: ($sub|tonumber),
           error: true, message: .result}
        else
          {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread,
           agent: $agent, loop_mode: $mode, parallel_sub: ($sub|tonumber),
           model: (.modelUsage // {} | keys[0] // "unknown"),
           num_turns: .num_turns, duration_ms: .duration_ms,
           input_tokens: .usage.input_tokens,
           cache_read_input_tokens: .usage.cache_read_input_tokens,
           cache_creation_input_tokens: .usage.cache_creation_input_tokens,
           output_tokens: .usage.output_tokens,
           cost_usd: .total_cost_usd}
        end
      ' "$output_file" >> "$USAGE_LOG" 2>/dev/null
    fi
  done

  return 0
}


while true; do
  # --- Circuit breaker check ---
  if cb_is_open; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║  CIRCUIT BREAKER OPEN — $CB_CONSECUTIVE_FAILURES consecutive failures"
    echo "║  Halting to avoid wasting tokens.                       ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║  To resume:                                             ║"
    echo "║    rm $CB_FILE && ./ralph-loop.sh -p     ║"
    echo "║  Or investigate logs/usage.jsonl for error patterns.    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    break
  fi

  ITERATION=$((ITERATION + 1))
  echo "$ITERATION" > "$COUNTER_FILE"
  echo "=== Iteration $ITERATION ==="
  rm -f "$CTX_FILE" "$YIELD_FILE" "$BUDGET_FILE"
  sleep 3  # let any dying statusline process finish writing, then clear again
  rm -f "$CTX_FILE"

  ITER_START=$(date +%s)
  IGNORE_UNTIL=$(( ITER_START + 15 ))  # ignore context readings for first 15s (stale cache)

  # Check if statusline was active in previous iteration
  if [ "$ITERATION" -gt 1 ]; then
    if [ -f "$STATUSLINE_LOG" ]; then
      LINES=$(wc -l < "$STATUSLINE_LOG" | tr -d '[:space:]')
      echo "  Statusline log: ${LINES} entries (statusline IS firing in -p mode)"
    else
      echo "  Statusline log: empty (statusline NOT firing in -p mode)"
    fi
  fi

  # --- Reflection trigger (every 5th iteration) ---
  rm -f /tmp/ralph-reflect
  if [ "$ITERATION" -gt 0 ] && [ $(( ITERATION % 5 )) -eq 0 ]; then
    touch /tmp/ralph-reflect
    echo "  Reflection iteration (mod 5)"
  fi

  # --- Detect thread and agent ---
  CURRENT_THREAD=$(grep '^\*\*Thread:\*\*\|^Thread:' checkpoint.md 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g' | tr -d '[:space:]')
  [ -z "$CURRENT_THREAD" ] || [ "$CURRENT_THREAD" = "<thread-name>" ] && CURRENT_THREAD="unknown"
  if [ "$ARCH_MODE" = "single" ] && [ "$LOOP_MODE" = "build" ]; then
    CURRENT_AGENT="single"
    echo "  Single-agent mode — skipping agent detection"
  else
    CURRENT_AGENT=$(detect_agent)
  fi
  if [ "$LOOP_MODE" = "plan" ]; then
    # Plan mode doesn't need an agent — it's an interactive session
    CURRENT_AGENT="${CURRENT_AGENT:-plan}"
    echo "  Plan mode (agent detection skipped)"
  elif [ -n "$CURRENT_AGENT" ] && [ "$CURRENT_AGENT" != "" ]; then
    if [ "$CURRENT_AGENT" != "single" ] && [ ! -f "${RALPH_HOME}/.claude/agents/${CURRENT_AGENT}.md" ]; then
      RAW_LINE=$(grep -i '^\*\*Next Task\|^Next Task\|^## Next' checkpoint.md 2>/dev/null | head -1)
      echo "  ⚠  Agent file not found: ${RALPH_HOME}/.claude/agents/${CURRENT_AGENT}.md"
      echo "     Raw Next Task line: $RAW_LINE"
      echo "     Skipping iteration (fix checkpoint.md or agent name)."
      sleep 5
      continue
    fi
    echo "  Agent detected: $CURRENT_AGENT"
  else
    # Check if this is a completed plan (all tasks checked off) vs empty template
    CHECKED=$(grep -c '^\- \[x\]' implementation-plan.md 2>/dev/null || echo 0)
    UNCHECKED=$(grep -c '^\- \[ \]' implementation-plan.md 2>/dev/null || echo 0)
    if [ "$CHECKED" -gt 0 ] && [ "$UNCHECKED" -eq 0 ]; then
      echo "  All tasks complete — auto-archiving thread."
      bash "${RALPH_HOME}/scripts/archive.sh"
      echo ""
      echo "=== Thread archived. Loop complete. ==="
    else
      echo "  No task found in checkpoint.md — nothing to do."
      echo "  Run 'bash \"$RALPH_HOME/ralph-loop.sh\" plan' to plan next steps,"
      echo "  or 'bash \"$RALPH_HOME/scripts/archive.sh\"' to archive."
    fi
    break
  fi

  # --- Parallel mode: run all tasks in current phase concurrently ---
  if [ "$ARCH_MODE" = "parallel" ] && [ "$LOOP_MODE" = "build" ]; then
    CURRENT_PHASE=$(detect_current_phase)
    if [ -n "$CURRENT_PHASE" ] && is_parallel_phase "$CURRENT_PHASE"; then
      run_parallel_phase "$CURRENT_PHASE"
      PARALLEL_RC=$?

      # Eval capture for parallel iteration
      python3 "${RALPH_HOME}/scripts/evaluate_iteration.py" \
        --iteration "$ITERATION" \
        --arch-mode "$ARCH_MODE" \
        --run-tag "${RUN_TAG:-}" \
        2>/dev/null || true

      echo ""
      echo "=== Iteration $ITERATION complete (parallel phase). Fresh context in 3s... ==="
      sleep 3

      if [ -n "${MAX_ITERATIONS:-}" ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
        echo "=== Max iterations ($MAX_ITERATIONS) reached. Exiting. ==="
        break
      fi
      continue
    fi
    # Not a parallel phase — fall through to serial execution
    echo "  Phase not marked (parallel) — running serially"
  fi

  # --- Single-agent mode: use combined prompt ---
  if [ "$ARCH_MODE" = "single" ] && [ "$LOOP_MODE" = "build" ]; then
    PROMPT_FILE="${RALPH_HOME}/prompt-build-single.md"
  fi

  # --- Build prompt ---
  PROMPT=$(cat "$PROMPT_FILE")

  # Inbox: absorb operator notes if present
  if [ -s "inbox.md" ]; then
    echo "  📬 Absorbing operator notes from inbox.md"
    PROMPT="## Operator Notes (read and act on these first)"$'\n\n'"$(cat inbox.md)"$'\n\n'"$PROMPT"
    > inbox.md
  fi

  if $PIPE_MODE; then
    # Non-interactive: pipe prompt, background claude, poll for context via JSONL monitor
    CLAUDE_MODEL=$(resolve_model "$CURRENT_AGENT")
    echo "  Model: $CLAUDE_MODEL"

    # Create start marker for JSONL monitor (before launching claude)
    touch /tmp/ralph-monitor-start

    # Launch JSONL context monitor in background
    # Search: RALPH_HOME first (framework), then GITHUB_WORKSPACE, then CWD
    MONITOR_SCRIPT=""
    for _s in "${RALPH_HOME}/.github/scripts/ralph-monitor.sh" \
              "${GITHUB_WORKSPACE:-.}/.github/scripts/ralph-monitor.sh" \
              ".github/scripts/ralph-monitor.sh"; do
      if [ -x "$_s" ]; then MONITOR_SCRIPT="$_s"; break; fi
    done
    if [ -n "$MONITOR_SCRIPT" ]; then
      bash "$MONITOR_SCRIPT" "$CONTEXT_THRESHOLD" 200000 &
      JSONL_MONITOR_PID=$!
      echo "  JSONL context monitor started (pid $JSONL_MONITOR_PID)"
    fi

    # Launch agent runner with bash-level retries for transient failures
    AGENT_ATTEMPT=0
    while true; do
      rm -f /tmp/ralph-output.json

      echo "$PROMPT" | python3 "${RALPH_HOME}/ralph_agent.py" --agent "$CURRENT_AGENT" --task - --model "$CLAUDE_MODEL" --output-json /tmp/ralph-output.json &
      CLAUDE_PID=$!

      # Wait for first context reading (after ignore window) and print it
      for i in $(seq 1 30); do
        now=$(date +%s)
        if [ "$now" -ge "$IGNORE_UNTIL" ] && [ -f "$CTX_FILE" ]; then
          if [[ "$OSTYPE" == "darwin"* ]]; then
            file_time=$(stat -f %m "$CTX_FILE" 2>/dev/null || echo 0)
          else
            file_time=$(stat -c %Y "$CTX_FILE" 2>/dev/null || echo 0)
          fi
          if [ "$file_time" -ge "$IGNORE_UNTIL" ]; then
            start_pct=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
            if [ -n "$start_pct" ] 2>/dev/null; then
              echo "  Starting context: ${start_pct}%"
              break
            fi
          fi
        fi
        sleep 2
      done

      monitor_context "$CLAUDE_PID" "$ITER_START" "$IGNORE_UNTIL" "$CURRENT_AGENT" &
      MONITOR_PID=$!

      wait "$CLAUDE_PID" 2>/dev/null
      EXIT_CODE=$?
      CLAUDE_PID=""

      kill "$MONITOR_PID" 2>/dev/null || true
      wait "$MONITOR_PID" 2>/dev/null || true
      MONITOR_PID=""

      # Success — break out of retry loop
      if [ "$EXIT_CODE" -eq 0 ]; then
        break
      fi

      # Check if the failure looks transient (no output JSON = crash before any work)
      AGENT_ATTEMPT=$((AGENT_ATTEMPT + 1))
      if [ "$AGENT_ATTEMPT" -ge "$AGENT_MAX_RETRIES" ]; then
        echo "  Agent $CURRENT_AGENT failed after $((AGENT_ATTEMPT + 1)) attempts (exit $EXIT_CODE)"
        break
      fi

      delay=${AGENT_RETRY_DELAYS[$((AGENT_ATTEMPT - 1))]:-45}
      echo "  [agent retry] $CURRENT_AGENT exited $EXIT_CODE, attempt $((AGENT_ATTEMPT + 1))/$((AGENT_MAX_RETRIES + 1)), waiting ${delay}s..."
      sleep "$delay"
    done

    # Stop JSONL monitor if running
    if [ -n "$JSONL_MONITOR_PID" ]; then
      kill "$JSONL_MONITOR_PID" 2>/dev/null || true
      wait "$JSONL_MONITOR_PID" 2>/dev/null || true
      JSONL_MONITOR_PID=""
    fi

    # Log post-run usage summary from --output-format json
    if [ -f /tmp/ralph-output.json ]; then
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
      ' /tmp/ralph-output.json 2>/dev/null || echo "  (could not parse output JSON)"

      # Persist usage data to logs/usage.jsonl
      # Extract agent name from checkpoint.md "**Last agent:**" field
      AGENT_NAME=$(grep '^\*\*Last agent:\*\*' checkpoint.md 2>/dev/null \
        | sed 's/\*\*Last agent:\*\* *//' | tr -d '[:space:]' | head -1)
      AGENT_NAME="${AGENT_NAME:-unknown}"
      mkdir -p "$(dirname "$USAGE_LOG")"
      jq -c --arg iter "$ITERATION" --arg agent "$AGENT_NAME" --arg mode "$LOOP_MODE" \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg thread "$CURRENT_THREAD" '
        if .is_error then
          {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode,
           error: true, message: .result}
        else
          {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode,
           model: (.modelUsage // {} | keys[0] // "unknown"),
           num_turns: .num_turns, duration_ms: .duration_ms,
           input_tokens: .usage.input_tokens,
           cache_read_input_tokens: .usage.cache_read_input_tokens,
           cache_creation_input_tokens: .usage.cache_creation_input_tokens,
           output_tokens: .usage.output_tokens,
           cost_usd: .total_cost_usd,
           tools_called: (.tools_called // [])}
        end
      ' /tmp/ralph-output.json >> "$USAGE_LOG" 2>/dev/null \
        && echo "  Usage logged to $USAGE_LOG" \
        || echo "  (could not log usage data)"
    fi


    # --- Eval capture ---
    python3 "${RALPH_HOME}/scripts/evaluate_iteration.py" \
      --iteration "$ITERATION" \
      --arch-mode "${ARCH_MODE:-serial}" \
      --run-tag "${RUN_TAG:-}" \
      2>/dev/null || echo "  (eval capture skipped)"
    # Human review checkpoint
    if [ -f "HUMAN_REVIEW_NEEDED.md" ] && ! diff -q "HUMAN_REVIEW_NEEDED.md" "$RALPH_HOME/templates/HUMAN_REVIEW_NEEDED.md" >/dev/null 2>&1; then
      echo ""
      echo "╔══════════════════════════════════════════════╗"
      echo "║  HUMAN REVIEW REQUESTED                     ║"
      echo "╚══════════════════════════════════════════════╝"
      echo ""
      cat HUMAN_REVIEW_NEEDED.md
      echo ""
      echo "To continue: review above, edit checkpoint.md if needed, then:"
      echo "  rm HUMAN_REVIEW_NEEDED.md && ./ralph-loop.sh -p"
      exit 0
    fi
  else
    # Interactive: claude gets the terminal, monitor runs in background
    # Start a subshell monitor that will print starting context + watch threshold
    # Use the same monitor_context function (runs in background)
    monitor_context "$$" "$ITER_START" "$IGNORE_UNTIL" "$CURRENT_AGENT" &
    MONITOR_PID=$!

    CLAUDE_MODEL=$(resolve_model "$CURRENT_AGENT")
    SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    echo "$PROMPT" | claude --model "$CLAUDE_MODEL" --session-id "$SESSION_ID" --dangerously-skip-permissions
    EXIT_CODE=$?

    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
    MONITOR_PID=""

    # Log interactive session usage
    AGENT_NAME=$(grep '^\*\*Last agent:\*\*' checkpoint.md 2>/dev/null \
      | sed 's/\*\*Last agent:\*\* *//' | tr -d '[:space:]' | head -1)
    AGENT_NAME="${AGENT_NAME:-unknown}"
    PROJECT_DIR=$(echo "$PWD" | tr '/' '-' | sed 's/^-//')
    SESSION_FILE="$HOME/.claude/projects/${PROJECT_DIR}/${SESSION_ID}.jsonl"
    if [ -f "$SESSION_FILE" ]; then
      mkdir -p "$(dirname "$USAGE_LOG")"
      python3 "${RALPH_HOME}/scripts/extract_session_usage.py" "$SESSION_FILE" \
        | jq -c --arg iter "$ITERATION" --arg agent "$AGENT_NAME" --arg mode "$LOOP_MODE" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg thread "$CURRENT_THREAD" \
            '. + {iteration: ($iter|tonumber), timestamp: $ts, thread: $thread, agent: $agent, loop_mode: $mode}' \
        >> "$USAGE_LOG" 2>/dev/null \
        && echo "  Usage logged to $USAGE_LOG" \
        || echo "  (could not log usage data)"
    else
      echo "  (session file not found — usage not logged)"
    fi


    # --- Eval capture ---
    python3 "${RALPH_HOME}/scripts/evaluate_iteration.py" \
      --iteration "$ITERATION" \
      --arch-mode "${ARCH_MODE:-serial}" \
      --run-tag "${RUN_TAG:-}" \
      2>/dev/null || echo "  (eval capture skipped)"
    # Human review checkpoint
    if [ -f "HUMAN_REVIEW_NEEDED.md" ] && ! diff -q "HUMAN_REVIEW_NEEDED.md" "$RALPH_HOME/templates/HUMAN_REVIEW_NEEDED.md" >/dev/null 2>&1; then
      echo ""
      echo "╔══════════════════════════════════════════════╗"
      echo "║  HUMAN REVIEW REQUESTED                     ║"
      echo "╚══════════════════════════════════════════════╝"
      echo ""
      cat HUMAN_REVIEW_NEEDED.md
      echo ""
      echo "To continue: review above, edit checkpoint.md if needed, then:"
      echo "  rm HUMAN_REVIEW_NEEDED.md && ./ralph-loop.sh -p"
      exit 0
    fi
  fi

  # --- Error recovery with exponential backoff ---
  if [ "$EXIT_CODE" -ne 0 ]; then
    RATE_LIMITED=false
    if $PIPE_MODE && [ -f /tmp/ralph-output.json ]; then
      if grep -q "You've hit your limit\|rate_limit\|overloaded" /tmp/ralph-output.json 2>/dev/null; then
        RATE_LIMITED=true
      fi
    fi

    if $RATE_LIMITED; then
      echo "  ⚠  Rate limit hit. Backing off ${BACKOFF}s ..."
    else
      echo "  ⚠  Claude exited $EXIT_CODE. Backing off ${BACKOFF}s ..."
    fi
    cb_record_failure
    sleep "$BACKOFF"
    BACKOFF=$((BACKOFF * 2))
    [ "$BACKOFF" -gt 3600 ] && BACKOFF=3600
    # Rewind counter so the retry keeps the same iteration number
    ITERATION=$((ITERATION - 1))
    echo "$ITERATION" > "$COUNTER_FILE"
    continue
  fi

  # Reset backoff and circuit breaker after success
  BACKOFF=60
  cb_record_success

  # Safety net: detect and restore git-tracked files truncated to 0 bytes
  TRUNCATED=$(git diff --numstat 2>/dev/null | awk '$1 == 0 && $2 > 0 {print $3}')
  if [ -n "$TRUNCATED" ]; then
    echo "  ⚠  TRUNCATED FILES DETECTED:"
    echo "$TRUNCATED" | sed 's/^/    /'
    echo "  Restoring from HEAD..."
    echo "$TRUNCATED" | xargs git checkout HEAD --
  fi

  # Auto-append CHANGELOG entry from git log
  if [ -f "CHANGELOG.md" ] || [ "$ITERATION" -eq 1 ]; then
    LAST_MSG=$(git log -1 --format='%s' 2>/dev/null || echo "no commit")
    printf "\n## Iteration %d — %s\n- %s\n" "$ITERATION" "$(date +%Y-%m-%d)" "$LAST_MSG" >> CHANGELOG.md
  fi

  # Read final context %
  final_pct=""
  if [ -f "$CTX_FILE" ]; then
    final_pct=$(cat "$CTX_FILE" 2>/dev/null | tr -d '[:space:]')
  fi

  echo ""
  echo "=== Iteration $ITERATION complete (exit code: $EXIT_CODE${final_pct:+, context: ${final_pct}%}). Fresh context in 3s... ==="
  sleep 3

  # Max-iteration guard (for CI safety caps)
  if [ -n "${MAX_ITERATIONS:-}" ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
    echo "=== Max iterations ($MAX_ITERATIONS) reached. Exiting. ==="
    break
  fi
done
