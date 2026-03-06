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
POLL_INTERVAL=5
STATUSLINE_LOG="/tmp/ralph-statusline-log"
BACKOFF=60

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
  rm -f "$YIELD_FILE" "$CTX_FILE"
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

monitor_context() {
  local pid=$1
  local iter_start=$2
  local ignore_until=$3
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
          printf "  [%dm%02ds] context: %s%%" "$mins" "$secs" "$pct"
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
  rm -f "$CTX_FILE" "$YIELD_FILE"
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

    monitor_context "$CLAUDE_PID" "$ITER_START" "$IGNORE_UNTIL" &
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
          (if .model_usage then
            (.model_usage | to_entries[] |
              "\n  Model: \(.key)" +
              "\n    input: \(.value.input_tokens // 0) | cache_create: \(.value.cache_creation_input_tokens // 0) | cache_read: \(.value.cache_read_input_tokens // 0) | output: \(.value.output_tokens // 0)")
          else "" end) +
          (if .cost_usd then "\n  Cost: $\(.cost_usd)" else "" end)
        end
      ' /tmp/ralph-output.json 2>/dev/null || echo "  (could not parse output JSON)"
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
    monitor_context "$$" "$ITER_START" "$IGNORE_UNTIL" &
    MONITOR_PID=$!

    CLAUDE_MODEL="${CLAUDE_MODEL:-claude-opus-4-6}"
    echo "$PROMPT" | claude --model "$CLAUDE_MODEL" --dangerously-skip-permissions
    EXIT_CODE=$?

    kill "$MONITOR_PID" 2>/dev/null || true
    wait "$MONITOR_PID" 2>/dev/null || true
    MONITOR_PID=""

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
