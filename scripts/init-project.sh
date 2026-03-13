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
#
# Layout:
#   Content directories (human-inputs, ai-generated-outputs, papers, corpus,
#   sections, references, figures) live at PROJECT_ROOT (cwd).
#   Framework state (logs, archive, ralphd, .ralphrc, etc.) lives in WORKSPACE.
#   Symlinks inside WORKSPACE point to the project-root content dirs so agents
#   see everything via relative paths from cwd — zero prompt/tool changes.
#
#   In CI mode or same-dir mode (workspace = .), all dirs live in WORKSPACE
#   directly (no symlinks except inputs → human-inputs for backward compat).

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
WORKSPACE="${WORKSPACE:-.ralph}"

mkdir -p "$WORKSPACE"
WORKSPACE="$(cd "$WORKSPACE" && pwd)"

# Derive PROJECT_ROOT from WORKSPACE:
#   Split layout (.ralph/): PROJECT_ROOT = parent directory
#   All-in-one layout:      PROJECT_ROOT = WORKSPACE itself
if [ "$(basename "$WORKSPACE")" = ".ralph" ]; then
  PROJECT_ROOT="$(dirname "$WORKSPACE")"
else
  PROJECT_ROOT="$WORKSPACE"
fi

# CI mode: all content in WORKSPACE (same-dir semantics — CI always runs from workspace)
if $CI_MODE; then
  PROJECT_ROOT="$WORKSPACE"
fi

echo "Initializing ralph workspace: $WORKSPACE"
echo "Framework: $RALPH_HOME"
$CI_MODE && echo "Mode: CI (copy, no symlinks)"

# --- Content directories ---
# human-inputs/ — user-provided context: reviewer feedback, prior submissions,
#                  venue-specific guidelines, style files, supplementary material.
#                  Agents (editor, paper-writer, coherence-reviewer) read from here
#                  but never write to it. Only humans populate this directory.
CONTENT_DIRS="ai-generated-outputs papers corpus sections references figures"
mkdir -p "$PROJECT_ROOT/human-inputs"
for dir in $CONTENT_DIRS; do
  mkdir -p "$PROJECT_ROOT/$dir"
done

# --- Workspace-only directories (framework state, disposable) ---
for dir in logs archive; do
  mkdir -p "$WORKSPACE/$dir"
done

# --- Content symlinks inside WORKSPACE ---
# When WORKSPACE is a subdirectory of PROJECT_ROOT (the default .ralph/ case),
# create symlinks so agents can access content dirs via WORKSPACE-relative paths.
if [ "$WORKSPACE" != "$PROJECT_ROOT" ]; then
  for dir in $CONTENT_DIRS; do
    link="$WORKSPACE/$dir"
    if [ -L "$link" ] || [ ! -e "$link" ]; then
      rm -f "$link"
      ln -s "../$dir" "$link"
    fi
  done
  # inputs → ../human-inputs (backward-compat name mapping)
  link="$WORKSPACE/inputs"
  if [ -L "$link" ] || [ ! -e "$link" ]; then
    rm -f "$link"
    ln -s "../human-inputs" "$link"
  fi
else
  # Same-dir mode (ralphd-init . or CI): inputs → human-inputs for backward compat
  link="$WORKSPACE/inputs"
  if [ ! -e "$link" ]; then
    ln -s "human-inputs" "$link"
  fi
fi

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

# --- .claude/agents ---
if $CI_MODE; then
  # CI: copy agents (symlinks don't survive git commits)
  if [ ! -d "$WORKSPACE/.claude/agents" ]; then
    mkdir -p "$WORKSPACE/.claude"
    cp -r "$RALPH_HOME/.claude/agents" "$WORKSPACE/.claude/agents"
    echo "  Copied .claude/agents/"
  fi
else
  # Local: symlink to RALPH_HOME for live updates
  mkdir -p "$WORKSPACE/.claude"
  target="$RALPH_HOME/.claude/agents"
  link="$WORKSPACE/.claude/agents"
  if [ -L "$link" ]; then
    rm "$link"  # recreate to ensure correct target
  fi
  if [ ! -e "$link" ]; then
    ln -s "$target" "$link"
  else
    echo "  Skipping .claude/agents/ (already exists as regular dir)"
  fi
fi

# --- human-inputs/ README (first-init only) ---
if [ ! -f "$PROJECT_ROOT/human-inputs/README.md" ]; then
  cat > "$PROJECT_ROOT/human-inputs/README.md" << 'INPUTS_README'
# human-inputs/

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
- Only humans populate `human-inputs/`.
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

# Self-healing symlinks — specs/templates → RALPH_HOME
for dir in specs templates; do
  target="$RALPH_HOME/$dir"
  link="$SCRIPT_DIR/$dir"
  if [ -L "$link" ] && [ "$(readlink "$link")" != "$target" ]; then
    rm "$link" && ln -s "$target" "$link"
  elif [ ! -e "$link" ]; then
    ln -s "$target" "$link"
  fi
done

# Self-healing .claude/agents → RALPH_HOME
mkdir -p "$SCRIPT_DIR/.claude"
target="$RALPH_HOME/.claude/agents"
link="$SCRIPT_DIR/.claude/agents"
if [ -L "$link" ] && [ "$(readlink "$link")" != "$target" ]; then
  rm "$link" && ln -s "$target" "$link"
elif [ ! -e "$link" ]; then
  ln -s "$target" "$link"
fi

# Self-healing content symlinks (only when workspace is a subdirectory)
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
if [ "$SCRIPT_DIR" != "$PARENT_DIR" ] && [ "$(basename "$SCRIPT_DIR")" = ".ralph" ]; then
  for dir in ai-generated-outputs papers corpus sections references figures; do
    link="$SCRIPT_DIR/$dir"
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      rm "$link" && ln -s "../$dir" "$link"
    elif [ ! -e "$link" ]; then
      ln -s "../$dir" "$link"
    fi
  done
  # inputs → ../human-inputs
  link="$SCRIPT_DIR/inputs"
  if [ -L "$link" ] && [ ! -e "$link" ]; then
    rm "$link" && ln -s "../human-inputs" "$link"
  elif [ ! -e "$link" ]; then
    ln -s "../human-inputs" "$link"
  fi
fi

exec "$RALPH_HOME/ralph-loop.sh" "$@"
LAUNCHER
  chmod +x "$WORKSPACE/ralphd"

  # --- Ensure workspace is a git repo ---
  if [ ! -d "$WORKSPACE/.git" ]; then
    echo "  Initializing git repository"
    git init "$WORKSPACE"
  fi

  # Brownfield: add workspace to parent's .gitignore
  if [ "$WORKSPACE" != "$RALPH_HOME" ]; then
    PARENT_GIT=$(git -C "$WORKSPACE/.." rev-parse --git-dir 2>/dev/null || true)
    if [ -n "$PARENT_GIT" ]; then
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
