#!/usr/bin/env bash
set -euo pipefail

# init-project.sh — Initialize a workspace for ralPhD
#
# Usage:
#   RALPH_HOME=/path/to/ralPhD bash scripts/init-project.sh [workspace] [--ci]
#
# Options:
#   --ci    CI mode: copy specs/templates instead of symlinking,
#           skip ralphd launcher and brownfield detection.

# Resolve RALPH_HOME (env var > script location)
RALPH_HOME="${RALPH_HOME:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ ! -f "$RALPH_HOME/ralph_agent.py" ]; then
  echo "Error: RALPH_HOME=$RALPH_HOME is not a valid ralPhD install"; exit 1
fi

CI_MODE=false
WORKSPACE=""
for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=true ;;
    *) WORKSPACE="$arg" ;;
  esac
done
WORKSPACE="${WORKSPACE:-.}"

mkdir -p "$WORKSPACE"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

echo "Initializing ralph workspace: $WORKSPACE"
echo "Framework: $RALPH_HOME"
$CI_MODE && echo "Mode: CI (copy, no symlinks)"

# --- Directories ---
# inputs/ — user-provided context: reviewer feedback, prior submissions,
#            venue-specific guidelines, style files, supplementary material.
#            Agents (editor, paper-writer, coherence-reviewer) read from here
#            but never write to it. Only humans populate this directory.
for dir in ai-generated-outputs papers corpus sections references figures logs archive inputs; do
  mkdir -p "$WORKSPACE/$dir"
done

# --- specs and templates ---
if $CI_MODE; then
  # CI: copy directories (symlinks don't survive git commits)
  for dir in specs templates; do
    if [ ! -d "$WORKSPACE/$dir" ]; then
      cp -r "$RALPH_HOME/$dir" "$WORKSPACE/$dir"
      echo "  Copied $dir/"
    else
      echo "  Skipping $dir/ (already exists)"
    fi
  done
else
  # Local: symlink for live updates
  for dir in specs templates; do
    target="$RALPH_HOME/$dir"
    link="$WORKSPACE/$dir"
    if [ -L "$link" ]; then
      rm "$link"  # recreate to ensure correct target
    fi
    if [ ! -e "$link" ]; then
      ln -s "$target" "$link"
    else
      echo "  Skipping $dir/ (already exists as regular dir)"
    fi
  done
fi

# --- Project files (skip-existing) ---
cp -n "$RALPH_HOME/templates/checkpoint.md" "$WORKSPACE/checkpoint.md" 2>/dev/null || true
cp -n "$RALPH_HOME/templates/implementation-plan.md" "$WORKSPACE/implementation-plan.md" 2>/dev/null || true
[ -f "$WORKSPACE/inbox.md" ] || touch "$WORKSPACE/inbox.md"
[ -f "$WORKSPACE/iteration_count" ] || echo "0" > "$WORKSPACE/iteration_count"

# --- .claude/agents (CI only — agents need to be in workspace for ralph_agent.py) ---
if $CI_MODE; then
  if [ ! -d "$WORKSPACE/.claude/agents" ]; then
    mkdir -p "$WORKSPACE/.claude"
    cp -r "$RALPH_HOME/.claude/agents" "$WORKSPACE/.claude/agents"
    echo "  Copied .claude/agents/"
  fi
fi

# --- inputs/ README (first-init only) ---
if [ ! -f "$WORKSPACE/inputs/README.md" ]; then
  cat > "$WORKSPACE/inputs/README.md" << 'INPUTS_README'
# inputs/

Human-provided context for the writing pipeline. Place files here for agents to read.

## What goes here

| File type | Example | Used by |
|-----------|---------|---------|
| Reviewer feedback | `reviews-round1.pdf`, `reviewer2-comments.txt` | editor, paper-writer |
| Prior submissions | `v1-submitted.pdf` | editor, coherence-reviewer |
| Venue guidelines | `icml2025-style-guide.pdf`, `author-kit.zip` | editor, paper-writer |
| Style files | `icml2025.sty`, `neurips_2025.sty` | paper-writer |
| Supplementary notes | `advisor-notes.md` | all agents |

## Convention

- Agents read from this directory but never write to it.
- Only humans populate `inputs/`.
- Filenames should be descriptive — agents use them to decide relevance.
INPUTS_README
fi

# --- .ralphrc ---
echo "RALPH_HOME=$RALPH_HOME" > "$WORKSPACE/.ralphrc"

# --- Local-only: ralphd launcher and brownfield detection ---
if ! $CI_MODE; then
  cat > "$WORKSPACE/ralphd" << 'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# RALPH_HOME: env var > .ralphrc
if [ -z "${RALPH_HOME:-}" ] && [ -f "$SCRIPT_DIR/.ralphrc" ]; then
  RALPH_HOME=$(grep '^RALPH_HOME=' "$SCRIPT_DIR/.ralphrc" | cut -d= -f2)
fi
export RALPH_HOME

# Self-healing symlinks
for dir in specs templates; do
  target="$RALPH_HOME/$dir"
  link="$SCRIPT_DIR/$dir"
  if [ -L "$link" ] && [ "$(readlink "$link")" != "$target" ]; then
    rm "$link" && ln -s "$target" "$link"
  elif [ ! -e "$link" ]; then
    ln -s "$target" "$link"
  fi
done

exec "$RALPH_HOME/ralph-loop.sh" "$@"
LAUNCHER
  chmod +x "$WORKSPACE/ralphd"

  # Brownfield detection: if workspace is inside another git repo, isolate
  if [ "$WORKSPACE" != "$RALPH_HOME" ]; then
    PARENT_GIT=$(git -C "$WORKSPACE" rev-parse --git-dir 2>/dev/null || true)
    if [ -n "$PARENT_GIT" ] && [ "$PARENT_GIT" != "$WORKSPACE/.git" ]; then
      echo "  Detected parent git repo — initializing isolated git for workspace"
      git init "$WORKSPACE"
      PARENT_DIR=$(dirname "$WORKSPACE")
      BASENAME=$(basename "$WORKSPACE")
      if [ -d "$PARENT_DIR" ]; then
        grep -qxF "$BASENAME/" "$PARENT_DIR/.gitignore" 2>/dev/null || echo "$BASENAME/" >> "$PARENT_DIR/.gitignore"
      fi
    fi
  fi
fi

echo ""
echo "Workspace ready: $WORKSPACE"
if $CI_MODE; then
  echo "  CI mode — run ralph-loop.sh with RALPH_HOME=$RALPH_HOME"
else
  echo "  cd $WORKSPACE && ./ralphd plan"
fi
