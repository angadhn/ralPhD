#!/usr/bin/env bash
set -euo pipefail

# Archive current thread: move checkpoint + plan to archive/, restore blank templates.
#
# Usage: ./scripts/archive.sh
#   Reads thread name and date from checkpoint.md, creates archive/YYYY-MM-DD_thread/,
#   moves checkpoint.md and implementation-plan.md there, copies templates back to root,
#   and resets iteration_count.

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

# --- Archive ---
mkdir -p "$ARCHIVE_DIR"
mv checkpoint.md "$ARCHIVE_DIR/"
mv implementation-plan.md "$ARCHIVE_DIR/"

# Also archive iteration_count for the record
if [ -f iteration_count ]; then
  cp iteration_count "$ARCHIVE_DIR/"
fi

echo "Archived to $ARCHIVE_DIR/"

# --- Restore blank templates ---
cp "$RALPH_HOME/templates/checkpoint.md" checkpoint.md
cp "$RALPH_HOME/templates/implementation-plan.md" implementation-plan.md

echo "Restored blank templates to root"

# --- Reset iteration counter ---
echo "0" > iteration_count
echo "Reset iteration_count to 0"

echo ""
echo "Archive complete: $ARCHIVE_DIR"
echo "Root files reset. Ready for a new thread."
