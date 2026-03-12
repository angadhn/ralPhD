#!/usr/bin/env bash
set -euo pipefail

# Archive current thread: move all per-thread files to archive/, restore blank templates.
#
# Usage: ./scripts/archive.sh
#   Reads thread name and date from checkpoint.md, creates archive/YYYY-MM-DD_thread/,
#   moves checkpoint.md, implementation-plan.md, agent outputs, reflections, inbox
#   content, and usage log there, then copies templates back to root and resets state.

# Framework home — defaults to script's parent dir (backward compatible).
# In RALPH_HOME mode, templates come from the framework; project files stay in CWD.
RALPH_HOME="${RALPH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"

# --- Parse checkpoint.md for thread name and date ---
if [ ! -f checkpoint.md ]; then
  echo "Error: checkpoint.md not found" >&2
  exit 1
fi

THREAD=$(grep '^\*\*Thread:\*\*' checkpoint.md | sed 's/\*\*Thread:\*\* *//' | tr -d '[:space:]')
LAST_UPDATED=$(grep '^\*\*Last updated:\*\*' checkpoint.md | sed 's/\*\*Last updated:\*\* *//' | tr -d '[:space:]')

if [ -z "$THREAD" ]; then
  echo "Error: could not parse thread name from checkpoint.md" >&2
  exit 1
fi

# Use last-updated date if available, otherwise today
if [ -z "$LAST_UPDATED" ]; then
  LAST_UPDATED=$(date +%Y-%m-%d)
fi

ARCHIVE_DIR="archive/${LAST_UPDATED}_${THREAD}"

# --- Safety check: don't overwrite existing archive ---
if [ -d "$ARCHIVE_DIR" ]; then
  echo "Error: archive directory already exists: $ARCHIVE_DIR" >&2
  echo "Remove it manually if you want to re-archive." >&2
  exit 1
fi

# --- Verify templates exist ---
if [ ! -f "$RALPH_HOME/templates/checkpoint.md" ] || [ ! -f "$RALPH_HOME/templates/implementation-plan.md" ]; then
  echo "Error: templates/ directory missing required files" >&2
  echo "Expected: $RALPH_HOME/templates/checkpoint.md and $RALPH_HOME/templates/implementation-plan.md" >&2
  exit 1
fi
if [ ! -f "$RALPH_HOME/templates/HUMAN_REVIEW_NEEDED.md" ]; then
  echo "Error: templates/HUMAN_REVIEW_NEEDED.md missing" >&2
  exit 1
fi

# --- Archive ---
mkdir -p "$ARCHIVE_DIR"
mv checkpoint.md "$ARCHIVE_DIR/"
mv implementation-plan.md "$ARCHIVE_DIR/"
if [ -f HUMAN_REVIEW_NEEDED.md ]; then
  mv HUMAN_REVIEW_NEEDED.md "$ARCHIVE_DIR/"
fi

# Also archive iteration_count for the record
if [ -f iteration_count ]; then
  cp iteration_count "$ARCHIVE_DIR/"
fi

# Archive per-thread agent outputs (ai-generated-outputs/<thread>/)
# Note: ai-generated-outputs/ may be a symlink to ../ai-generated-outputs in
# split-layout mode. mv and find resolve through symlinks transparently.
if [ -d "ai-generated-outputs/$THREAD" ]; then
  mkdir -p "$ARCHIVE_DIR/ai-generated-outputs"
  mv "ai-generated-outputs/$THREAD" "$ARCHIVE_DIR/ai-generated-outputs/"
  echo "Archived ai-generated-outputs/$THREAD/"
fi

# Archive reflections (ai-generated-outputs/reflections/*.md, preserve .gitkeep)
REFLECTION_FILES=$(find ai-generated-outputs/reflections/ -name '*.md' -not -name '.gitkeep' 2>/dev/null || true)
if [ -n "$REFLECTION_FILES" ]; then
  mkdir -p "$ARCHIVE_DIR/reflections"
  for f in $REFLECTION_FILES; do
    mv "$f" "$ARCHIVE_DIR/reflections/"
  done
  echo "Archived reflections"
fi

# Archive inbox.md if it has content, then reset it
if [ -f inbox.md ] && [ -s inbox.md ]; then
  cp inbox.md "$ARCHIVE_DIR/"
  echo "Archived inbox.md"
fi
> inbox.md

# Archive CHANGELOG.md (accumulates per-iteration entries across all threads)
if [ -f CHANGELOG.md ]; then
  mv CHANGELOG.md "$ARCHIVE_DIR/"
  echo "# CHANGELOG" > CHANGELOG.md
  echo "Archived and reset CHANGELOG.md"
fi

# Clean /tmp/ralph-* state files from this thread
rm -f /tmp/ralph-context-pct /tmp/ralph-yield /tmp/ralph-budget-info \
      /tmp/ralph-output.json /tmp/ralph-statusline-log /tmp/ralph-monitor-start \
      /tmp/ralph-reflect /tmp/ralph-test-output.json
echo "Cleaned /tmp/ralph-* state files"

echo "Archived to $ARCHIVE_DIR/"

# --- Restore blank templates ---
cp "$RALPH_HOME/templates/checkpoint.md" checkpoint.md
cp "$RALPH_HOME/templates/implementation-plan.md" implementation-plan.md
cp "$RALPH_HOME/templates/HUMAN_REVIEW_NEEDED.md" HUMAN_REVIEW_NEEDED.md

echo "Restored blank templates to root"

# --- Write thread summary to usage log ---
USAGE_LOG="logs/usage.jsonl"
if [ -f "$USAGE_LOG" ]; then
  SUMMARY=$(jq -sc --arg thread "$THREAD" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    [ .[] | select(.thread == $thread and .error != true) ] |
    if length > 0 then
      {type: "thread_summary", timestamp: $ts, thread: $thread,
       iterations: length,
       first_iteration: (map(.iteration) | min),
       last_iteration: (map(.iteration) | max),
       total_input_tokens: (map(.input_tokens // 0) | add),
       total_output_tokens: (map(.output_tokens // 0) | add),
       total_cost_usd: (map(.cost_usd // 0) | add | . * 100 | round / 100),
       total_duration_ms: (map(.duration_ms // 0) | add),
       agents_used: (map(.agent) | unique)}
    else empty end
  ' "$USAGE_LOG" 2>/dev/null)
  if [ -n "$SUMMARY" ]; then
    echo "$SUMMARY" >> "$USAGE_LOG"
    echo "Thread summary written to $USAGE_LOG"
  fi
fi

# --- Reset iteration counter ---
echo "0" > iteration_count
echo "Reset iteration_count to 0"

echo ""
echo "Archive complete: $ARCHIVE_DIR"
echo "Root files reset. Ready for a new thread."
