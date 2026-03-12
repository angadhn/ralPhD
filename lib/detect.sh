#!/usr/bin/env bash

extract_next_task_from_checkpoint() {
  local checkpoint_path=$1
  local next_task=""

  next_task=$(grep -i '^\*\*Next Task\*\*:\|^Next Task:' "$checkpoint_path" 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g')
  if [ -z "$next_task" ]; then
    next_task=$(awk '/^## Next Task/{found=1; next} found && /[^ ]/{print; exit}' \
      "$checkpoint_path" 2>/dev/null)
  fi

  echo "$next_task" | sed 's/([^)]*)//g; s/\*//g; s/^ *//; s/ *$//'
}

detect_agent_from_checkpoint() {
  local checkpoint_path=$1
  local plan_path=${2:-}
  local next_task=""

  next_task=$(extract_next_task_from_checkpoint "$checkpoint_path")

  case "$next_task" in
    none*|None*|"<"*|"")
      if [ -n "$plan_path" ]; then
        next_task=$(grep '^\- \[ \]' "$plan_path" 2>/dev/null \
          | grep -v '<task description>\|<agent>' \
          | head -1 | sed 's/^- \[ \] [0-9]*\. *//' | sed 's/\*//g')
        next_task=$(echo "$next_task" | sed 's/^ *//; s/ *$//')
      else
        next_task=""
      fi
      ;;
  esac

  if [ -z "$next_task" ]; then
    echo ""
    return
  fi

  local agent="${next_task##* }"
  agent=$(echo "$agent" | sed 's/[^a-zA-Z0-9_-]//g')
  echo "$agent"
}

detect_current_phase() {
  local plan_path=$1
  local in_phase=""
  while IFS= read -r line; do
    if echo "$line" | grep -q '^## Phase'; then
      in_phase="$line"
    fi
    if echo "$line" | grep -q '^\- \[ \]'; then
      echo "$in_phase"
      return
    fi
  done < "$plan_path"
  echo ""
}

is_parallel_phase() {
  local phase_line=$1
  echo "$phase_line" | grep -qi '(parallel)'
}

collect_phase_tasks() {
  local plan_path=$1
  local target_phase=$2
  local in_target=false

  while IFS= read -r line; do
    if echo "$line" | grep -q '^## Phase'; then
      if [ "$line" = "$target_phase" ]; then
        in_target=true
      elif $in_target; then
        break
      fi
    fi

    if $in_target && echo "$line" | grep -q '^\- \[ \]'; then
      local task_desc
      task_desc=$(echo "$line" | sed 's/^- \[ \] [0-9]*\. *//' | sed 's/\*//g')
      local agent_name="${task_desc##* }"
      agent_name=$(echo "$agent_name" | sed 's/[^a-zA-Z0-9_-]//g')
      echo "${agent_name}|${task_desc}"
    fi
  done < "$plan_path"
}

resolve_agent_path() {
  local agent_name=$1
  if [ -f ".claude/agents/${agent_name}.md" ]; then
    echo ".claude/agents/${agent_name}.md"
  elif [ -f "${RALPH_HOME}/.claude/agents/${agent_name}.md" ]; then
    echo "${RALPH_HOME}/.claude/agents/${agent_name}.md"
  fi
}

extract_agent_name() {
  local name
  name=$(grep '^\*\*Last agent:\*\*' checkpoint.md 2>/dev/null \
    | sed 's/\*\*Last agent:\*\* *//' | tr -d '[:space:]' | head -1)
  echo "${name:-unknown}"
}

extract_thread() {
  local thread
  thread=$(grep '^\*\*Thread:\*\*\|^Thread:' checkpoint.md 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g' | tr -d '[:space:]')
  if [ -z "$thread" ] || [ "$thread" = "<thread-name>" ]; then
    echo "unknown"
  else
    echo "$thread"
  fi
}
