#!/usr/bin/env bash

parse_loop_args() {
  PIPE_MODE=false
  LOOP_MODE="build"
  PROMPT_FILE="prompt-build.md"
  ARCH_MODE=""
  RUN_TAG=""
  MAX_ITERATIONS=""
  SHOW_HELP=false
  CLI_MODEL=""

  for arg in "$@"; do
    case "$arg" in
      -p) PIPE_MODE=true ;;
      plan) LOOP_MODE="plan"; PROMPT_FILE="prompt-plan.md" ;;
      build) LOOP_MODE="build"; PROMPT_FILE="prompt-build.md" ;;
      --serial) ARCH_MODE="serial" ;;
      --parallel) ARCH_MODE="parallel" ;;
      --run-tag=*) RUN_TAG="${arg#--run-tag=}" ;;
      --model=*) CLI_MODEL="${arg#--model=}" ;;
      --help|-h) SHOW_HELP=true ;;
      [0-9]*) MAX_ITERATIONS="$arg" ;;
    esac
  done
}

show_help() {
  cat <<'HELP'
Usage: ./ralphd [options] [plan|build] [iterations]

Modes:
  plan              Interactive planning session (no -p flag)
  build             Build loop (default)

Options:
  -p                Non-interactive (pipe) mode
  --model=<name>    Override model for all agents
  --serial          Force serial architecture
  --parallel        Force parallel architecture
  --run-tag=<tag>   Tag for this run (used in logs)
  --help, -h        Show this help and exit

Supported models:
  claude-opus-4-6       Anthropic Opus 4.6  (200k context)
  claude-sonnet-4-6     Anthropic Sonnet 4.6 (200k context)
  claude-haiku-4-5      Anthropic Haiku 4.5  (200k context)
  gpt-5.4               OpenAI GPT-5.4       (272k context)
  gpt-4o                OpenAI GPT-4o        (128k context)
  o3                    OpenAI o3            (200k context)
  o4-mini               OpenAI o4-mini       (200k context)

Model resolution order:
  1. --model flag
  2. RALPH_MODEL env var
  3. Per-agent model in context-budgets.json
  4. Default: claude-opus-4-6

Environment variables:
  RALPH_MODEL           Global model override (same as --model)
  CLAUDE_MODEL          Alias for RALPH_MODEL (deprecated)
  RALPH_HOME            Path to ralPhD framework install
  ANTHROPIC_API_KEY     API key for Anthropic models
  OPENAI_API_KEY        API key for OpenAI models

Examples:
  ./ralphd plan                          # Interactive planning session
  ./ralphd -p build                      # Non-interactive build loop
  ./ralphd --model=claude-sonnet-4-6 -p  # Build with Sonnet
  ./ralphd -p build 10                   # Build for max 10 iterations
  ./ralphd --model=gpt-5.4 -p build     # Build with GPT-5.4
HELP
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

  if [ -z "$arch_mode" ] || ! echo "$arch_mode" | grep -qE '^(serial|parallel|auto)$'; then
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
