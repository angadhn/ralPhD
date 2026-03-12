#!/usr/bin/env bash

parse_loop_args() {
  PIPE_MODE=false
  LOOP_MODE="build"
  PROMPT_FILE="prompt-build.md"
  ARCH_MODE=""
  RUN_TAG=""
  MAX_ITERATIONS=""

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
}

resolve_arch_mode_from_plan() {
  local cli_override=${1:-}
  local plan_path=${2:-implementation-plan.md}
  local arch_mode="$cli_override"

  if [ -z "$arch_mode" ]; then
    arch_mode=$(grep -i '^\*\*Architecture:\*\*\|^Architecture:' "$plan_path" 2>/dev/null \
      | head -1 | sed 's/.*: *//' | sed 's/\*//g' | tr -d '[:space:]' \
      | tr '[:upper:]' '[:lower:]' || true)
  fi

  if [ -z "$arch_mode" ] || ! echo "$arch_mode" | grep -qE '^(serial|parallel|single|auto)$'; then
    arch_mode="serial"
  fi

  echo "$arch_mode"
}

resolve_ralph_home() {
  local script_path=$1
  if [ -z "${RALPH_HOME:-}" ]; then
    RALPH_HOME="$(cd "$(dirname "$script_path")" && pwd)"
  fi
  if [ ! -f "${RALPH_HOME}/ralph_agent.py" ]; then
    echo "Error: RALPH_HOME (${RALPH_HOME}) does not contain ralph_agent.py"
    exit 1
  fi
  export RALPH_HOME
}

restore_iteration_counter() {
  COUNTER_FILE=${COUNTER_FILE:-iteration_count}
  if [ -f "$COUNTER_FILE" ]; then
    ITERATION=$(cat "$COUNTER_FILE")
    if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
      echo "Warning: invalid iteration_count ('$ITERATION'), resetting to 0" >&2
      ITERATION=0
    fi
  else
    ITERATION=0
  fi
}

print_loop_banner() {
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
}
