#!/usr/bin/env bash
set -euo pipefail

# --- Mode ---
PIPE_MODE=false
LOOP_MODE="build"
PROMPT_FILE="prompt-build.md"

for arg in "$@"; do
  case "$arg" in
    -p) PIPE_MODE=true ;;
    plan) LOOP_MODE="plan"; PROMPT_FILE="prompt-plan.md" ;;
    build) LOOP_MODE="build"; PROMPT_FILE="prompt-build.md" ;;
    [0-9]*) MAX_ITERATIONS="$arg" ;;
  esac
done

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
  rm -f "$YIELD_FILE" "$CTX_FILE" "$BUDGET_FILE"
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
  next_task=$(grep -i '^\*\*Next Task\|^Next Task\|^## Next' checkpoint.md 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g')
  echo "${next_task##* }" | tr -d '[:space:]'
}

estimate_input_cost() {
  # Estimate context % that reading input files will consume for a given agent.
  # Uses file sizes on disk: ~4 bytes/token, ~200k tokens = 100% context.
  # Returns integer percentage via stdout.
  local agent_name=$1
  local thread=""
  local total_bytes=0

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

  # ~4 bytes per token, ~200k tokens = 100% context → 800k bytes = 100%
  # pct = total_bytes * 100 / 800000
  local input_pct=$(( total_bytes * 100 / 800000 ))
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
  if [ -f "context-budgets.json" ] && command -v jq &>/dev/null; then
    max_step=$(jq -r --arg a "$agent_name" '.[$a].max_step // 0' context-budgets.json 2>/dev/null || echo 0)
  fi

  # Estimate input file cost and adjust max_step if inputs are larger than expected
  input_cost=$(estimate_input_cost "$agent_name")
  if [ "$input_cost" -gt 0 ]; then
    local static_read_cost
    static_read_cost=$(jq -r --arg a "$agent_name" '.[$a].steps.read_inputs // .[$a].steps.read_chunk // 0' context-budgets.json 2>/dev/null || echo 0)
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
echo "Context yield threshold: ${CONTEXT_THRESHOLD}%"
[ -n "${MAX_ITERATIONS:-}" ] && echo "Max iterations: $MAX_ITERATIONS"
echo "Double Ctrl+C to stop"
echo ""

while true; do
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

  # --- Detect agent for budget computation ---
  CURRENT_AGENT=$(detect_agent)
  if [ -n "$CURRENT_AGENT" ] && [ "$CURRENT_AGENT" != "" ]; then
    echo "  Agent detected: $CURRENT_AGENT"
  else
    CURRENT_AGENT="unknown"
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
    CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-6}"
    echo "  Model: $CLAUDE_MODEL"

    # Create start marker for JSONL monitor (before launching claude)
    touch /tmp/ralph-monitor-start

    # Launch JSONL context monitor in background
    MONITOR_SCRIPT=""
    for _s in "${GITHUB_WORKSPACE:-.}/.github/scripts/ralph-monitor.sh" \
              ".github/scripts/ralph-monitor.sh"; do
      if [ -x "$_s" ]; then MONITOR_SCRIPT="$_s"; break; fi
    done
    if [ -n "$MONITOR_SCRIPT" ]; then
      bash "$MONITOR_SCRIPT" "$CONTEXT_THRESHOLD" 200000 &
      JSONL_MONITOR_PID=$!
      echo "  JSONL context monitor started (pid $JSONL_MONITOR_PID)"
    fi

    # Launch Claude (stdout is clean — no OTEL hijacking)
    echo "$PROMPT" | claude -p --model "$CLAUDE_MODEL" --output-format json --dangerously-skip-permissions > /tmp/ralph-output.json &
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
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        if .is_error then
          {iteration: ($iter|tonumber), timestamp: $ts, agent: $agent, loop_mode: $mode,
           error: true, message: .result}
        else
          {iteration: ($iter|tonumber), timestamp: $ts, agent: $agent, loop_mode: $mode,
           model: (.modelUsage // {} | keys[0] // "unknown"),
           num_turns: .num_turns, duration_ms: .duration_ms,
           input_tokens: .usage.input_tokens,
           cache_read_input_tokens: .usage.cache_read_input_tokens,
           cache_creation_input_tokens: .usage.cache_creation_input_tokens,
           output_tokens: .usage.output_tokens,
           cost_usd: .total_cost_usd}
        end
      ' /tmp/ralph-output.json >> "$USAGE_LOG" 2>/dev/null \
        && echo "  Usage logged to $USAGE_LOG" \
        || echo "  (could not log usage data)"
    fi

    # Human review checkpoint
    if [ -f "HUMAN_REVIEW_NEEDED.md" ]; then
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

    CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-6}"
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
      python3 scripts/extract_session_usage.py "$SESSION_FILE" \
        | jq -c --arg iter "$ITERATION" --arg agent "$AGENT_NAME" --arg mode "$LOOP_MODE" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '. + {iteration: ($iter|tonumber), timestamp: $ts, agent: $agent, loop_mode: $mode}' \
        >> "$USAGE_LOG" 2>/dev/null \
        && echo "  Usage logged to $USAGE_LOG" \
        || echo "  (could not log usage data)"
    else
      echo "  (session file not found — usage not logged)"
    fi

    # Human review checkpoint
    if [ -f "HUMAN_REVIEW_NEEDED.md" ]; then
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
    sleep "$BACKOFF"
    BACKOFF=$((BACKOFF * 2))
    [ "$BACKOFF" -gt 3600 ] && BACKOFF=3600
    # Rewind counter so the retry keeps the same iteration number
    ITERATION=$((ITERATION - 1))
    echo "$ITERATION" > "$COUNTER_FILE"
    continue
  fi

  # Reset backoff after success
  BACKOFF=60

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
