#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/detect.sh"
source "${SCRIPT_DIR}/lib/monitor.sh"
source "${SCRIPT_DIR}/lib/post-run.sh"
source "${SCRIPT_DIR}/lib/exec.sh"

parse_loop_args "$@"

if $PIPE_MODE && [ "$LOOP_MODE" = "plan" ]; then
  echo "Error: plan mode is interactive only — remove the -p flag."
  echo "  Use: ./ralph-loop.sh plan"
  exit 1
fi

ARCH_MODE=$(resolve_arch_mode_from_plan "$ARCH_MODE" "implementation-plan.md")
export ARCH_MODE

resolve_ralph_home "$0"
PROMPT_FILE="${RALPH_HOME}/${PROMPT_FILE}"
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: $PROMPT_FILE not found"
  exit 1
fi

CONTEXT_THRESHOLD=55
CTX_FILE="/tmp/ralph-context-pct"
YIELD_FILE="/tmp/ralph-yield"
BUDGET_FILE="/tmp/ralph-budget-info"
POLL_INTERVAL=5
BACKOFF=60
USAGE_LOG="logs/usage.jsonl"
AGENT_MAX_RETRIES=3
AGENT_RETRY_DELAYS=(5 15 45)
CB_FILE="/tmp/ralph-circuit-breaker"
CB_THRESHOLD=5
CB_CONSECUTIVE_FAILURES=0
COUNTER_FILE="iteration_count"
HEARTBEAT_INTERVAL=90

CLAUDE_PID=""
MONITOR_PID=""
JSONL_MONITOR_PID=""
LAST_CTRL_C=0

restore_circuit_breaker_state
restore_iteration_counter

trap 'handle_interrupt_signal' INT

print_loop_banner


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

  # --- Reflection trigger (every 5th iteration) ---
  rm -f /tmp/ralph-reflect
  if [ "$ITERATION" -gt 0 ] && [ $(( ITERATION % 5 )) -eq 0 ]; then
    touch /tmp/ralph-reflect
    echo "  Reflection iteration (mod 5)"
  fi

  # --- Detect thread and agent ---
  CURRENT_THREAD=$(extract_thread)
  if [ "$ARCH_MODE" = "single" ] && [ "$LOOP_MODE" = "build" ]; then
    CURRENT_AGENT="single"
    echo "  Single-agent mode — skipping agent detection"
  else
    CURRENT_AGENT=$(detect_agent_from_checkpoint "checkpoint.md" "implementation-plan.md")
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
    CURRENT_PHASE=$(detect_current_phase "implementation-plan.md")
    if [ -n "$CURRENT_PHASE" ] && is_parallel_phase "$CURRENT_PHASE"; then
      run_parallel_phase "$CURRENT_PHASE"
      PARALLEL_RC=$?

      capture_eval_metrics || true

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

  # --- Build prompt ---
  if [ "$CURRENT_AGENT" = "single" ]; then
    # Single mode: system prompt (prompt-build-single.md) has all instructions.
    # Task is just a kick — don't send prompt-build.md (it contradicts single-mode behavior).
    PROMPT="Begin. Read checkpoint.md and implementation-plan.md, then work through the tasks."
  else
    PROMPT=$(cat "$PROMPT_FILE")
  fi

  # Inbox: absorb operator notes if present
  if [ -s "inbox.md" ]; then
    echo "  📬 Absorbing operator notes from inbox.md"
    PROMPT="## Operator Notes (read and act on these first)"$'\n\n'"$(cat inbox.md)"$'\n\n'"$PROMPT"
    : > inbox.md
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
      CONTEXT_WINDOW=$(resolve_context_window "$CLAUDE_MODEL")
      bash "$MONITOR_SCRIPT" "$CONTEXT_THRESHOLD" "$CONTEXT_WINDOW" &
      JSONL_MONITOR_PID=$!
      echo "  JSONL context monitor started (pid $JSONL_MONITOR_PID)"
    fi

    # Build extra args for ralph_agent.py (shell array to avoid word-splitting)
    AGENT_EXTRA_ARGS=()
    if [ "$CURRENT_AGENT" = "single" ]; then
      AGENT_EXTRA_ARGS+=(--system-prompt-file "${RALPH_HOME}/prompt-build-single.md")
    fi

    # Launch agent runner with bash-level retries for transient failures
    AGENT_ATTEMPT=0
    while true; do
      rm -f /tmp/ralph-output.json

      echo "$PROMPT" | python3 "${RALPH_HOME}/ralph_agent.py" --agent "$CURRENT_AGENT" --task - --model "$CLAUDE_MODEL" --output-json /tmp/ralph-output.json "${AGENT_EXTRA_ARGS[@]}" &
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
      print_output_json_summary /tmp/ralph-output.json

      # Persist usage data to logs/usage.jsonl
      # Extract agent name from checkpoint.md "**Last agent:**" field
      AGENT_NAME=$(extract_agent_name)
      log_usage_from_output_json /tmp/ralph-output.json "$ITERATION" "$AGENT_NAME" "$LOOP_MODE" "$CURRENT_THREAD" \
        && echo "  Usage logged to $USAGE_LOG" \
        || echo "  (could not log usage data)"
    fi


    # --- Eval capture ---
    capture_eval_metrics || echo "  (eval capture skipped)"
    if handle_human_review_gate; then
      exit 0
    fi
  else
    # Interactive: monitor runs in background, agent gets the terminal
    monitor_context "$$" "$ITER_START" "$IGNORE_UNTIL" "$CURRENT_AGENT" &
    MONITOR_PID=$!

    CLAUDE_MODEL=$(resolve_model "$CURRENT_AGENT")

    if is_openai_model "$CLAUDE_MODEL"; then
      # OpenAI models: use codex CLI for interactive TUI (uses codex's own tools),
      # fall back to ralph_agent.py (uses Ralph's per-agent tool registry)
      rm -f /tmp/ralph-output.json
      if command -v codex >/dev/null 2>&1; then
        echo "  Model: $CLAUDE_MODEL (OpenAI — using codex CLI)"
        echo "$PROMPT" | codex --model "$CLAUDE_MODEL" --full-auto -
        EXIT_CODE=$?
      else
        echo "  Model: $CLAUDE_MODEL (OpenAI — codex CLI not found, using ralph_agent.py)"
        AGENT_EXTRA_ARGS=()
        if [ "$CURRENT_AGENT" = "single" ]; then
          AGENT_EXTRA_ARGS+=(--system-prompt-file "${RALPH_HOME}/prompt-build-single.md")
        fi
        echo "$PROMPT" | python3 "${RALPH_HOME}/ralph_agent.py" --agent "$CURRENT_AGENT" --task - --model "$CLAUDE_MODEL" --output-json /tmp/ralph-output.json "${AGENT_EXTRA_ARGS[@]}"
        EXIT_CODE=$?
      fi

      kill "$MONITOR_PID" 2>/dev/null || true
      wait "$MONITOR_PID" 2>/dev/null || true
      MONITOR_PID=""

      # Log usage
      AGENT_NAME=$(extract_agent_name)
      if [ -f /tmp/ralph-output.json ]; then
        print_output_json_summary /tmp/ralph-output.json
        log_usage_from_output_json /tmp/ralph-output.json "$ITERATION" "$AGENT_NAME" "$LOOP_MODE" "$CURRENT_THREAD" \
          && echo "  Usage logged to $USAGE_LOG" \
          || echo "  (could not log usage data)"
      else
        echo "  (codex interactive — usage not logged)"
      fi
    else
      # Anthropic models: use claude CLI for interactive TUI
      SESSION_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
      echo "$PROMPT" | claude --model "$CLAUDE_MODEL" --session-id "$SESSION_ID" --dangerously-skip-permissions
      EXIT_CODE=$?

      kill "$MONITOR_PID" 2>/dev/null || true
      wait "$MONITOR_PID" 2>/dev/null || true
      MONITOR_PID=""

      # Log interactive session usage
      AGENT_NAME=$(extract_agent_name)
      PROJECT_DIR=$(echo "$PWD" | tr '/' '-' | sed 's/^-//')
      SESSION_FILE="$HOME/.claude/projects/${PROJECT_DIR}/${SESSION_ID}.jsonl"
      if [ -f "$SESSION_FILE" ]; then
        log_interactive_session_usage "$SESSION_FILE" "$ITERATION" "$AGENT_NAME" "$LOOP_MODE" "$CURRENT_THREAD" \
          && echo "  Usage logged to $USAGE_LOG" \
          || echo "  (could not log usage data)"
      else
        echo "  (session file not found — usage not logged)"
      fi
    fi


    # --- Eval capture ---
    capture_eval_metrics || echo "  (eval capture skipped)"
    if handle_human_review_gate; then
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

  restore_truncated_files
  append_changelog_entry

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
