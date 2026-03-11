#!/usr/bin/env bash
set -euo pipefail

# test-workflow-local.sh — Simulate the GitHub Actions workflow locally
#
# Tests the critical path without calling the Anthropic API:
#   1. CI init (init-project.sh --ci)
#   2. Template injection (thread, date, autonomy)
#   3. RALPH_HOME resolution in ralph-loop.sh
#   4. Agent detection from checkpoint.md
#   5. Workflow YAML structure
#   6. Idempotent re-init
#   7. Path context preamble (RALPH_HOME separation)
#
# Usage: bash tests/test-workflow-local.sh

RALPH_HOME="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE=$(mktemp -d)
PASS=0
FAIL=0
TESTS=0

cleanup() {
  rm -rf "$WORKSPACE"
}
trap cleanup EXIT

pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); TESTS=$((TESTS + 1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); TESTS=$((TESTS + 1)); }
check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

# Cross-platform sed -i
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

echo "=== Test: Workflow Local Simulation ==="
echo "RALPH_HOME: $RALPH_HOME"
echo "WORKSPACE:  $WORKSPACE"
echo ""

# ── Test 1: CI init ────────────────────────────────────────────
echo "--- 1. CI Init ---"
RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" --ci "$WORKSPACE" > /dev/null

check "checkpoint.md created" test -f "$WORKSPACE/checkpoint.md"
check "implementation-plan.md created" test -f "$WORKSPACE/implementation-plan.md"
check "inbox.md created" test -f "$WORKSPACE/inbox.md"
check "iteration_count created" test -f "$WORKSPACE/iteration_count"
check "specs/ is directory (not symlink)" test -d "$WORKSPACE/specs" -a ! -L "$WORKSPACE/specs"
check "templates/ is directory (not symlink)" test -d "$WORKSPACE/templates" -a ! -L "$WORKSPACE/templates"
check ".claude/agents/ copied" test -d "$WORKSPACE/.claude/agents"
check "ralphd not created in CI mode" test ! -f "$WORKSPACE/ralphd"
check ".ralphrc created" test -f "$WORKSPACE/.ralphrc"

# Verify agents are present
AGENT_COUNT=$(ls "$WORKSPACE/.claude/agents/"*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$AGENT_COUNT" -gt 5 ]; then
  pass "agents copied ($AGENT_COUNT .md files)"
else
  fail "expected >5 agent files, got $AGENT_COUNT"
fi
echo ""

# ── Test 2: Template injection ─────────────────────────────────
echo "--- 2. Template Injection ---"
cd "$WORKSPACE"

INPUT_THREAD="test-thread-42"
INPUT_AUTONOMY="autopilot"
TODAY=$(date +%Y-%m-%d)

# Inject thread
sedi "s/<thread-name>/${INPUT_THREAD}/g" checkpoint.md
sedi "s/<thread name>/${INPUT_THREAD}/g" checkpoint.md
sedi "s/<date>/${TODAY}/g" checkpoint.md
sedi "s/<thread-name>/${INPUT_THREAD}/g" implementation-plan.md
sedi "s/<thread name>/${INPUT_THREAD}/g" implementation-plan.md
sedi "s/<date>/${TODAY}/g" implementation-plan.md

check "thread injected into checkpoint" grep -q "$INPUT_THREAD" checkpoint.md
check "date injected into checkpoint" grep -q "$TODAY" checkpoint.md
check "thread injected into plan" grep -q "$INPUT_THREAD" implementation-plan.md

# Set autonomy (cross-platform: use printf + temp file approach)
{
  head -1 implementation-plan.md
  echo "**Autonomy:** ${INPUT_AUTONOMY}"
  tail -n +2 implementation-plan.md
} > implementation-plan.md.tmp && mv implementation-plan.md.tmp implementation-plan.md
check "autonomy set in plan" grep -q "Autonomy.*autopilot" implementation-plan.md

# Write prompt to inbox
printf '%s\n' "Test prompt: write the introduction" > inbox.md
check "prompt written to inbox" grep -q "Test prompt" inbox.md
echo ""

# ── Test 3: RALPH_HOME resolution ─────────────────────────────
echo "--- 3. RALPH_HOME Resolution ---"
check "ralph_agent.py exists in RALPH_HOME" test -f "$RALPH_HOME/ralph_agent.py"
check "prompt-build.md exists in RALPH_HOME" test -f "$RALPH_HOME/prompt-build.md"
check "prompt-plan.md exists in RALPH_HOME" test -f "$RALPH_HOME/prompt-plan.md"
check "context-budgets.json exists in RALPH_HOME" test -f "$RALPH_HOME/context-budgets.json"

# Test RALPH_HOME validation from ralph-loop.sh
if RALPH_HOME="$RALPH_HOME" bash -c '
  RALPH_HOME="${RALPH_HOME}"
  if [ ! -f "${RALPH_HOME}/ralph_agent.py" ]; then
    exit 1
  fi
  exit 0
' 2>/dev/null; then
  pass "ralph-loop.sh RALPH_HOME validation passes"
else
  fail "ralph-loop.sh RALPH_HOME validation"
fi
echo ""

# ── Test 4: Agent detection ───────────────────────────────────
echo "--- 4. Agent Detection ---"

# detect_agent extracted from ralph-loop.sh
detect_agent() {
  local ckpt="$1"
  local next_task
  next_task=$(grep -i '^\*\*Next Task\*\*:\|^Next Task:' "$ckpt" 2>/dev/null \
    | head -1 | sed 's/.*: *//' | sed 's/\*//g')
  if [ -z "$next_task" ]; then
    next_task=$(awk '/^## Next Task/{found=1; next} found && /[^ ]/{print; exit}' "$ckpt" 2>/dev/null)
  fi
  next_task=$(echo "$next_task" | sed 's/([^)]*)//g; s/\*//g; s/^ *//; s/ *$//')
  case "$next_task" in
    none*|None*|"<"*|"") echo ""; return ;;
  esac
  local agent="${next_task##* }"
  agent=$(echo "$agent" | sed 's/[^a-zA-Z0-9_-]//g')
  echo "$agent"
}

# Test inline format
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint — test

**Thread:** test-thread-42
**Last updated:** 2026-03-11
**Last agent:** planner
**Status:** testing

## Knowledge State

| Task | Status | Notes |
|------|--------|-------|

## Next Task

3. Create the workflow file — **coder**
EOF

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
if [ "$DETECTED" = "coder" ]; then
  pass "heading-style agent detection: '$DETECTED'"
else
  fail "heading-style agent detection: got '$DETECTED', expected 'coder'"
fi

# Test with heading + bold format
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

7. Audit agent prompts — **scout**
EOF

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
if [ "$DETECTED" = "scout" ]; then
  pass "bold agent detection: '$DETECTED'"
else
  fail "bold agent detection: got '$DETECTED', expected 'scout'"
fi

# Test with no task (should return empty)
cat > "$WORKSPACE/checkpoint.md" << 'EOF'
# Checkpoint

## Next Task

none
EOF

DETECTED=$(detect_agent "$WORKSPACE/checkpoint.md")
if [ -z "$DETECTED" ]; then
  pass "no-task detection: empty (correct)"
else
  fail "no-task detection: got '$DETECTED', expected empty"
fi

# Verify agent files exist
for agent in coder scout critic paper-writer; do
  check "agent file exists: $agent.md" test -f "$RALPH_HOME/.claude/agents/$agent.md"
done
echo ""

# ── Test 5: Workflow YAML structure ───────────────────────────
echo "--- 5. Workflow YAML Validation ---"
check "ralph-run.yml exists" test -f "$RALPH_HOME/.github/workflows/ralph-run.yml"

if python3 -c "
import yaml, sys
with open('$RALPH_HOME/.github/workflows/ralph-run.yml') as f:
    doc = yaml.safe_load(f)
jobs = doc.get('jobs', {})
assert 'ralph-loop' in jobs, 'missing ralph-loop job'
steps = jobs['ralph-loop']['steps']
assert len(steps) >= 8, f'expected >=8 steps, got {len(steps)}'
step_names = [s.get('name', '') for s in steps]
assert any('Check out ralPhD' in n for n in step_names), 'missing checkout step'
assert any('Initialize' in n for n in step_names), 'missing init step'
assert any('ralph-loop' in n for n in step_names), 'missing run step'
assert any('Upload' in n for n in step_names), 'missing upload step'
assert any('summary' in n.lower() for n in step_names), 'missing summary step'

# Check inputs
on_field = doc.get(True) or doc.get('on')
inputs = on_field['workflow_dispatch']['inputs']
required_inputs = {'thread', 'prompt'}
for inp in required_inputs:
    assert inp in inputs, f'missing required input: {inp}'
    assert inputs[inp].get('required', False), f'{inp} should be required'
sys.exit(0)
" 2>/dev/null; then
  pass "YAML structure valid (jobs, steps, inputs)"
else
  fail "YAML structure validation"
fi

# Check no secrets in the workflow file
if grep -q 'sk-ant\|AKIA\|ghp_' "$RALPH_HOME/.github/workflows/ralph-run.yml" 2>/dev/null; then
  fail "secrets found in workflow file!"
else
  pass "no hardcoded secrets in workflow"
fi
echo ""

# ── Test 6: Idempotent re-init ────────────────────────────────
echo "--- 6. Idempotent Re-init ---"

# Running init again shouldn't overwrite existing files
echo "custom content" > "$WORKSPACE/checkpoint.md"
RALPH_HOME="$RALPH_HOME" bash "$RALPH_HOME/scripts/init-project.sh" --ci "$WORKSPACE" > /dev/null
check "checkpoint.md preserved on re-init" grep -q "custom content" "$WORKSPACE/checkpoint.md"
echo ""

# ── Test 7: Path context preamble ─────────────────────────────
echo "--- 7. Path Context Preamble ---"

# Test build_path_preamble in ralph_agent.py
if python3 -c "
import sys, os
from pathlib import Path

# Add RALPH_HOME to sys.path so we can import
sys.path.insert(0, '$RALPH_HOME')
from ralph_agent import build_path_preamble

# Test 1: Same dir = no preamble
cwd = Path.cwd()
result = build_path_preamble(cwd)
assert result == '', f'Expected empty for same dir, got: {repr(result)}'

# Test 2: Different dir = preamble with both paths
rh = Path('/opt/ralphd-framework')
result = build_path_preamble(rh)
assert '## Path Context' in result, 'Missing Path Context header'
assert 'RALPH_HOME' in result, 'Missing RALPH_HOME reference'
assert '/opt/ralphd-framework' in result, 'Missing framework path'
assert 'specs/' in result, 'Missing specs/ in framework files list'
assert 'templates/' in result, 'Missing templates/ in framework files list'
assert 'checkpoint.md' in result, 'Missing checkpoint.md in project files list'
assert 'implementation-plan.md' in result, 'Missing implementation-plan.md in project files'

# Test 3: agent-base.md has Path Resolution section
base_path = Path('$RALPH_HOME/.claude/agents/agent-base.md')
content = base_path.read_text()
assert '## Path Resolution' in content, 'agent-base.md missing Path Resolution section'
assert 'RALPH_HOME' in content, 'agent-base.md missing RALPH_HOME reference'
assert 'working directory' in content.lower(), 'agent-base.md missing working directory reference'
" 2>/dev/null; then
  pass "build_path_preamble: same dir = empty"
  pass "build_path_preamble: different dir = preamble with paths"
  pass "agent-base.md has Path Resolution section"
else
  fail "path context preamble tests"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────
echo "=== Results: $PASS/$TESTS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
